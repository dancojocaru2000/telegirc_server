import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:tdlib_types/base.dart';

import 'database.dart';
import 'globals.dart';
import 'irc.dart';
import 'irc_errors.dart';
import 'irc_handlers/register_handler.dart';
import 'irc_replies.dart';
import 'irc_socket.dart';
import 'logging.dart';
import 'tdlib.dart';
import 'package:tdlib_types/fn.dart' as td_fn;
import 'package:tdlib_types/fn.dart' show TdFunction;
import 'package:tdlib_types/obj.dart' as td_o;
import 'package:tdlib_types/abstract.dart' as td_a;

class SocketManager {
  final IrcSocketWrapper socketWrapper;
  final void Function(SocketManager) onDisconnect;
  SocketManagerState _state;

  SocketManagerState get state => _state;

  String? password;
  late String nickname;
  late String username;
  late String realname;
  late String dbId;
  UserEntry? dbUserEntry;
  TdClient? tdClient;

  final Completer<void> _telegramConnectionCompleter = Completer();
  Future<void> get telegramConnectionFuture => _telegramConnectionCompleter.future;

  late List<CommandHandler> _normalHandlers;

  late final List<ServerHandler> _generalHandlers = [
    RegisterHandler(
      onUnregisterRequest: (h) => _generalHandlers.remove(h),
      add: add,
      addNumeric: addNumeric,
      nickname: () => nickname,
      tdSend: (fn) => tdClient!.send(fn),
      onRegistered: () {
        dbUserEntry = Database.instance.addUser(UserEntry(
          dbId: dbId, 
          baseNick: nickname,
        ));
      },
    ),
  ];

  SocketManager(this.socketWrapper, {required this.onDisconnect}) : _state = SocketManagerState.waitingPassOrNick {
    socketWrapper.stream.listen(
      (message) async {
        try {
          await onMessage(message);
        }
        on IrcException catch (e) {
          add(e.message);
        }
      }, 
      onError: onError,
    );
    _normalHandlers = [
      CommandHandler.normal(command: 'PASS', handler: () => throw IrcErrAlreadyRegistered.withLocalHostname(nickname)),
      CommandHandler.normal(command: 'USER', handler: () => throw IrcErrAlreadyRegistered.withLocalHostname(nickname)),
      CommandHandler.async(command: 'MOTD', handler: sendMotd),
      CommandHandler.async(command: 'LUSERS', handler: sendLusers),
    ];
  }

  void add(IrcMessage message) {
    // Logging
    if (message.command != 'PING' && message.command != 'PONG') {
      lDebug(function: 'SocketManager.add', message: '${socketWrapper.innerSocket.remoteAddress} <- ${message.displayCommand}');
    }
    socketWrapper.add(message);
  }

  void addNumeric(IrcNumericReply reply) => add(reply.ircMessage);

  Future onMessage(IrcMessage message) async {
    // Logging
    if (message.command != 'PING' && message.command != 'PONG') {
      lDebug(function: 'SocketManager.onMessage', message: '${socketWrapper.innerSocket.remoteAddress} -> ${message.displayCommand}');
    }

    validateMessage(message);

    if (message.command == 'PING') {
      add(IrcMessagePong.hostnameReplyToUser(nickname));
      return;
    }

    switch(_state) {
      case SocketManagerState.waitingPassOrNick:
        if (message.command == 'PASS') {
          password = message.parameters[0];
          _state = SocketManagerState.waitingNick;
        }
        else if (message.command == 'NICK') {
          nickname = message.parameters[0];
          _state = SocketManagerState.waitingUser;
        }
        break;
      case SocketManagerState.waitingNick:
        if (message.command == 'NICK') {
          nickname = message.parameters[0];
          _state = SocketManagerState.waitingUser;
        }
        break;
      case SocketManagerState.waitingUser:
        if (message.command == 'USER') {
          username = message.parameters[0];
          realname = '~${message.parameters[3]}';
          await validateConnection();
        }
        break;
      case SocketManagerState.connected:
        var handled = false;
        for (final handler in _normalHandlers) {
          if (handler.command != message.command) {
            continue;
          }
          handled = true;
          if (handler.awaitable) {
            final future = handler.handler as Future Function();
            await future();
          }
          else {
            handler.handler();
          }
        }
        for (final handler in _generalHandlers) {
          if (await handler.handleIrcMessage(message)) {
            handled = true;
          }
        }
        if (!handled) {
          lError(function: 'SocketManager.onMessage', message: 'Unknown command: $message');
          throw IrcException.fromNumeric(IrcErrUnknownCommand.withLocalHostname(nickname, message.command));
        }
        break;
      case SocketManagerState.disconnected:
        break;
    }
  }

  Future onTdEvent(TdBase event) async {
    if (event is td_a.Update) {
      await event.match(
        isUpdateAuthorizationState: (uas) async {
          await uas.authorizationState!.match(
            isAuthorizationStateWaitTdlibParameters: (_) async {
              await tdClient!.send(td_fn.SetTdlibParameters(parameters: td_o.TdlibParameters(
                apiHash: Globals.instance.apiHash,
                apiId: Globals.instance.apiId,
                applicationVersion: Globals.applicationVersion,
                databaseDirectory: Globals.instance.tdlibPath(dbId)!,
                deviceModel: 'Generic Dart Server',
                enableStorageOptimizer: true,
                useTestDc: Globals.instance.useTestConnection,
                filesDirectory: '',
                ignoreFileNames: false,
                systemLanguageCode: 'en',
                systemVersion: '',
                useSecretChats: false,
                useMessageDatabase: true,
                useChatInfoDatabase: true,
                useFileDatabase: false,
              )));
            },
            isAuthorizationStateWaitEncryptionKey: (_) async {
              await tdClient!.send(td_fn.CheckDatabaseEncryptionKey(encryptionKey: Uint8List.fromList([])));
            },
            isAuthorizationStateReady: (_) async {
              _telegramConnectionCompleter.complete();
            },
            isAuthorizationStateLoggingOut: (_) {
              add(IrcMessage(
                command: 'ERROR',
                parameters: ['Logging out... Reconnect to login again.']
              ));
              if (dbUserEntry != null) {
                Database.instance.logout(dbUserEntry!);
              }
              onDisconnect(this);
            },
            otherwise: (_) => Future.value(null),
          );
        },
        otherwise: (_) => Future.value(null),
      );
    }
    await Future.wait(_generalHandlers.map((h) => h.handleTdMessage(event)));
  }

  void validateMessage(IrcMessage message) {
    switch (message.command) {
      case 'PASS':
        if (message.parameters.isEmpty) {
          throw IrcException.fromNumeric(IrcErrNeedMoreParams.withLocalHostname(nickname, message.command));
        }
        break;
      case 'NICK':
        if (message.parameters.isEmpty) {
          throw IrcException.fromNumeric(IrcErrNoNicknameGiven.withLocalHostname(nickname));
        }
        break;
      case 'USER':
        if (message.parameters.length < 4) {
          throw IrcException.fromNumeric(IrcErrNeedMoreParams.withLocalHostname(nickname, message.command));
        }
        break;
      case 'JOIN':
        if (message.parameters.isEmpty) {
          throw IrcException.fromNumeric(IrcErrNeedMoreParams.withLocalHostname(nickname, message.command));
        }
        break;
    }
  }

  Future validateConnection() async {
    dbUserEntry = Database.instance.getUser(baseNick: nickname);
    if (dbUserEntry != null) {
      dbId = dbUserEntry!.dbId;
    }
    else {
      dbId = Database.instance.newUserDbId();
    }
    tdClient = await TdClient.newClient();
    lInfo(function: 'SocketManager.validateConnection', message: 'Created tdClient: $tdClient');
    tdClient!.updateStream.listen(
      onTdEvent,
      onError: (error) {
        lError(function: 'TdClient.updateStream...', message: error);
      },
    );

    addNumeric(IrcRplWelcome.withDefaultMessage(nickname));
    addNumeric(IrcRplYourHost.withLocalHostname(nickname, Globals.instance.version));
    addNumeric(IrcRplCreated.withLocalHostname(nickname));

    await sendLusers();

    await sendMotd();

    _state = SocketManagerState.connected;
  }

  Future sendMotd() async {
    addNumeric(IrcRplMotdStart.withDefaultStart(nickname));

    late Stream<String> lines;
    if (dbUserEntry == null) {
      lines = Stream.fromIterable([
        'Hello, guest!',
        '',
        if (!socketWrapper.secure) ... [
          '',
          'WARNING: Please be advised that you are currently connected through',
          'an unsecure, plain tedbIdxt connection. Anybody can read all the data',
          'communicated through this connection.',
          '',
          'While connecting to IRC unsecurely is supported, IT IS HEAVILY DISCOURAGED!',
          'You are fully responsible for any security issues that arise',
          'due to the unsecure connection.',
          '',
          'To connect securely, instruct your IRC client to use TLS',
          'and connect to port ${Globals.instance.securePort}.',
          '',
          'You will be unable to connect to Telegram and continue the setup',
          'through this connection.',
        ]
        else ... [
          '',
          'Please join the #telegirc-signup channel to proceed logging in to Telegram.'
        ],
      ]);
    }
    else {
      lines = () async* {
        yield 'Hello!';
        yield '';
        if (!socketWrapper.secure) {
          final insecureWarning = [
            'WARNING: You are connected through an unsecure, plain text connection.',
            'Anybody inspecting your network will see all the data you send in plain text.',
            'It is recommended that you disconnect and instead configure your IRC client',
            'to connect securely on port ${Globals.instance.securePort}.',
            '',
          ];
          for (final line in insecureWarning) {
            yield line;
          }
        }
        yield '';
        yield 'Please wait for connection to Telegram servers...';
        
        await telegramConnectionFuture;

        final telegramUser = await tdClient!.send(td_fn.GetMe()) as td_o.User;

        yield '';
        yield 'Hello, ${telegramUser.firstName} ${telegramUser.lastName}!';
        yield '';

        final usefulCommandsLines = [
          'Some useful custom commands:',
          '  LIST-CHATS == Lists all chats and custom IDs that can be used to join the chat via IRC',
        ];
        for (final line in usefulCommandsLines) {
          yield line;
        }
      }();
    }

    await for (final line in lines) {
      addNumeric(IrcRplMotd.withLocalHostname(nickname, line));
    }

    addNumeric(IrcRplEndOfMotd.withLocalHostname(nickname));
  }

  Future sendLusers() async {
    addNumeric(IrcRplLUserClient.withLocalHostname(
      nickname, 
      users: 1, 
      services: 0, 
      servers: 1,
    ));
    addNumeric(IrcRplLUserMe.withLocalHostname(
      nickname, 
      clients: 1, 
      servers: 1,
    ));
  }

  void onError(Object? error, StackTrace? stackTrace) {
    stderr.writeln(error);
    stderr.writeln(stackTrace);
  }
}

class CommandHandler {
  final String command;
  final dynamic Function() handler;
  final bool awaitable;

  CommandHandler.normal({required this.command, required this.handler}) : awaitable = false;
  CommandHandler.async({required this.command, required Future Function() handler}) : handler = handler, awaitable = true;
}

enum SocketManagerState {
  waitingPassOrNick,
  waitingNick,
  waitingUser,
  connected,
  disconnected,
}

abstract class ServerHandler {
  /// When the handler considers it isn't needed, this callback
  /// is called to request unregistration.
  final void Function(ServerHandler)? onUnregisterRequest;
  final void Function(IrcMessage) add;
  final void Function(IrcNumericReply) addNumeric;
  final Future<dynamic> Function(TdFunction) tdSend;
  final String Function() _nicknameGetter;

  const ServerHandler({
    this.onUnregisterRequest,
    required this.add,
    required this.addNumeric,
    required String Function() nickname,
    required this.tdSend,
  }) : _nicknameGetter = nickname;

  String get nickname => _nicknameGetter();

  /// When registered, the handler is called for every message.
  /// The handler should only handle messages relevant to it.
  /// If a message is not relevant, the handler should return false.
  Future<bool> handleIrcMessage(IrcMessage message);

  Future<void> handleTdMessage(TdBase message);
}
