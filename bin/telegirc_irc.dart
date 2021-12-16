import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:stack_trace/stack_trace.dart';
import 'package:tdlib_types/base.dart';

import 'database.dart';
import 'globals.dart';
import 'irc.dart';
import 'irc_errors.dart';
import 'irc_handlers/auth_handler.dart';
import 'irc_handlers/chat_handler.dart';
import 'irc_handlers/help_handler.dart';
import 'irc_handlers/logout_handler.dart';
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

  StreamSubscription? _socket;
  StreamSubscription? _tdlib;

  SocketManagerState get state => _state;

  String? password;
  late String nickname;
  late String username;
  late String realname;
  late String dbId;
  UserEntry? dbUserEntry;
  TdClient? tdClient;
  bool authenticated = false;

  final Completer<void> _telegramConnectionCompleter = Completer();
  Future<void> get telegramConnectionFuture =>
      _telegramConnectionCompleter.future;

  late List<CommandHandler> _normalHandlers;
  late List<CommandHandler> _noMatchHandlers;

  late final List<ServerHandler> _generalHandlers = [];

  void addRegisterHandler() {
    _generalHandlers.add(RegisterHandler(
      onUnregisterRequest: (h) => _generalHandlers.remove(h),
      add: add,
      addNumeric: addNumeric,
      nickname: () => nickname,
      tdSend: (fn) => tdClient!.send(fn),
      onRegistered: () {
        dbUserEntry = Database.instance.addUser(UserEntry(
          dbId: dbId,
          baseNick: nickname,
          loginPassword: '',
        ));
        authenticated = true;
        addLoggedInHandlers(skipA: true);
      },
    ));
  }

  void addLoggedInHandlers({skipA = false}) {
    _generalHandlers.addAll([
      LogoutHandler(
        add: add,
        addNumeric: addNumeric,
        nickname: () => nickname,
        tdSend: (fn) => tdClient!.send(fn),
        onLogout: onLogout,
      ),
      HelpHandler(
        add: add,
        addNumeric: addNumeric,
        nickname: () => nickname,
        tdSend: (fn) => tdClient!.send(fn),
      ),
      AuthHandler(
        add: add,
        addNumeric: addNumeric,
        nickname: () => nickname,
        tdSend: (fn) => tdClient!.send(fn),
        isAuthenticated: () => authenticated,
        setAuthenticated: (newVal) {
          authenticated = newVal;
          if (dbUserEntry != null) {
            dbUserEntry = Database.instance.getUser(id: dbUserEntry!.id);
          }
        },
        userId: dbUserEntry!.id,
      ),
      ChatHandler(
        add: add, 
        addNumeric: addNumeric, 
        nickname: () => nickname, 
        tdSend: (fn) => tdClient!.send(fn),
      ),
    ]);

    if (!skipA && dbUserEntry != null && (!authenticated || dbUserEntry!.loginPassword.isEmpty)) {
      Future.delayed(const Duration(seconds: 2), () async {
        final nrmHdl = _generalHandlers.toList(growable: false);
        for (final handler in nrmHdl.whereType<AuthHandler>()) {
          handler.joinA();
        }
      });
    }
  }

  SocketManager(this.socketWrapper, {required this.onDisconnect})
      : _state = SocketManagerState.waitingPassOrNickOrUser {
    _socket = socketWrapper.stream.listen(
      (message) async {
        
        try {
          try {
            await onMessage(message);
          } on IrcException catch (e) {
            add(e.message);
          }
        } catch (e, st) {
          lError(
              function: 'SocketManager::constructor/stream.listen',
              message: 'Exception: $e');
          stderr.writeln(Trace.from(st).terse);
        } 
      },
      onError: onError,
      onDone: () { 
        lInfo(function: 'SocketManager::constructor/stream.listen->onDone', message: 'Socket closed');
        onDisconnect(this); 
      },
    );
    _normalHandlers = [
      CommandHandler.normal(
          command: 'USER',
          handler: (_) =>
              throw IrcException.fromNumeric(IrcErrAlreadyRegistered.withLocalHostname(nickname))),
      CommandHandler.async(command: 'MOTD', handler: (_) => sendMotd()),
      CommandHandler.async(command: 'LUSERS', handler: (_) => sendLusers()),
      CommandHandler.async(command: 'LIST', handler: (_) async {
        lDebug(function: 'SocketManager._normalHandlers/LIST', message: 'Listing channels');
        addNumeric(IrcRplListStart.withLocalHostname(nickname));
        final gnrHdl = _generalHandlers.toList(growable: false);
        for (final handler in gnrHdl) {
          (await handler.channels).map((chan) => chan.toNumericReply(nickname: nickname)).forEach(addNumeric);
        }
        addNumeric(IrcRplListEnd.withLocalHostname(nickname));
      }),
      CommandHandler.async(command: 'WHO', handler: (c) async {
        lDebug(function: 'SocketManager._normalHandlers/WHO', message: 'Listing users');
        addNumeric(IrcRplListStart.withLocalHostname(nickname));
        final channel = c.parameters.isEmpty ? null : c.parameters[0];
        final gnrHdl = _generalHandlers.toList(growable: false);
        for (final handler in gnrHdl) {
          (await handler.getUsers(channel)).map((chan) => chan.toNumericReply(nickname: nickname)).forEach(addNumeric);
        }
        addNumeric(IrcRplEndOfWho.withLocalHostname(nickname, channel));
      }),
    ];
    _noMatchHandlers = [
      CommandHandler.normal(command: 'JOIN', handler: (msg) {
        throw IrcException.fromNumeric(IrcErrNoSuchChannel.withLocalHostname(nickname, msg.parameters[0]));
      }),
      CommandHandler.normal(command: 'PART', handler: (msg) {
        throw IrcException.fromNumeric(IrcErrNoSuchChannel.withLocalHostname(nickname, msg.parameters[0]));
      }),
    ];
  }

  void add(IrcMessage message) {
    // Logging
    if (message.command != 'PING' && message.command != 'PONG') {
      lDebug(
          function: 'SocketManager.add',
          message:
              '${socketWrapper.innerSocket.remoteAddress} <- ${message.displayCommand}');
    }
    socketWrapper.add(message);
  }

  void addNumeric(IrcNumericReply reply) => add(reply.ircMessage);

  void onLogout() {
    lInfo(function: 'SocketManager.onLogout', message: 'Logging out');
    add(IrcMessage(
        command: 'ERROR',
        parameters: ['Logging out... Reconnect to login again.']));
    if (dbUserEntry != null) {
      lDebug(function: 'SocketManager.onLogout', message: 'Removing user from database');
      Database.instance.logout(dbUserEntry!);
    }
    if (tdClient == null) {
      lDebug(function: 'SocketManager.onLogout', message: 'Logging out of tdlib');
      tdClient!.logout();
    }
    onDisconnect(this);
  }

  void dispose() {
    lDebug(function: 'SocketManager.dispose', message: 'Disposing');
    tdClient?.close();
    tdClient = null;
    _socket?.cancel();
    _tdlib?.cancel();
  }

  Future onMessage(IrcMessage message) async {
    // Logging
    if (message.command != 'PING' && message.command != 'PONG') {
      lDebug(
          function: 'SocketManager.onMessage',
          message:
              '${socketWrapper.innerSocket.remoteAddress} -> ${message.displayCommand}');
    }

    validateMessage(message);

    if (message.command == 'PING') {
      add(IrcMessagePong.hostnameReplyToUser(nickname));
      return;
    }

    switch (_state) {
      case SocketManagerState.waitingPassOrNickOrUser:
        if (message.command == 'PASS') {
          password = message.parameters[0];
          _state = SocketManagerState.waitingNickOrUser;
        } else if (message.command == 'NICK') {
          nickname = message.parameters[0];
          _state = SocketManagerState.waitingUser;
        } else if (message.command == 'USER') {
          username = message.parameters[0];
          realname = '~${message.parameters[3]}';
          _state = SocketManagerState.waitingNick;
        }
        break;
      case SocketManagerState.waitingNickOrUser:
        if (message.command == 'NICK') {
          nickname = message.parameters[0];
          _state = SocketManagerState.waitingUser;
        } else if (message.command == 'USER') {
          username = message.parameters[0];
          realname = '~${message.parameters[3]}';
          _state = SocketManagerState.waitingNick;
        }
        break;
      case SocketManagerState.waitingNick:
        if (message.command == 'NICK') {
          nickname = message.parameters[0];
          _state = SocketManagerState.waitingUser;
          await validateConnection();
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
            final future = handler.handler as Future Function(IrcMessage);
            await future(message);
          } else {
            handler.handler(message);
          }
        }
        final hdlCpy = _generalHandlers.toList(growable: false);
        for (final handler in hdlCpy) {
          try {
            if (await handler.handleIrcMessage(message)) {
              handled = true;
            }
          } catch (e, st) {
            lError(function: 'SocketManager.onMessage', message: 'Handler $handler threw on handleIrcMessage: $e');
            stderr.writeln(Trace.from(st).terse);
          }
        }
        if (!handled) {
          // Try finding specialized failure handlers
          for (final handler in _noMatchHandlers) {
            if (handler.command != message.command) {
              continue;
            }
            handled = true;
            if (handler.awaitable) {
              final future = handler.handler as Future Function(IrcMessage);
              await future(message);
            } else {
              handler.handler(message);
            }
          }
        }
        if (!handled) {
          lError(
              function: 'SocketManager.onMessage',
              message: 'Unknown command: $message');
          throw IrcException.fromNumeric(IrcErrUnknownCommand.withLocalHostname(
              nickname, message.command));
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
              try {
                await tdClient!.send(td_fn.SetTdlibParameters(
                    parameters: td_o.TdlibParameters(
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
              } on td_o.Error catch(e) {
                lError(function: 'tdClient.send', message: 'Unable to set parameters; error: $e');
                add(IrcMessage(
                  command: 'ERROR',
                  parameters: ['Failed to initialize TDLib'],
                ));
                onDisconnect(this);
              }
            },
            isAuthorizationStateWaitEncryptionKey: (_) async {
              await tdClient!.send(td_fn.CheckDatabaseEncryptionKey(
                  encryptionKey: Uint8List.fromList([])));
            },
            isAuthorizationStateReady: (_) async {
              _telegramConnectionCompleter.complete();
              if (dbUserEntry != null) {
                // Add handlers only if not registering
                addLoggedInHandlers();
              }
            },
            isAuthorizationStateLoggingOut: (_) {
              onLogout();
            },
            isAuthorizationStateWaitPhoneNumber: (_) {
              addRegisterHandler();
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
          throw IrcException.fromNumeric(IrcErrNeedMoreParams.withLocalHostname(
              nickname, message.command));
        }
        break;
      case 'NICK':
        if (message.parameters.isEmpty) {
          throw IrcException.fromNumeric(
              IrcErrNoNicknameGiven.withLocalHostname(nickname));
        }
        break;
      case 'USER':
        if (message.parameters.length < 4) {
          throw IrcException.fromNumeric(IrcErrNeedMoreParams.withLocalHostname(
              nickname, message.command));
        }
        break;
      case 'JOIN':
        if (message.parameters.isEmpty) {
          throw IrcException.fromNumeric(IrcErrNeedMoreParams.withLocalHostname(
              nickname, message.command));
        }
        break;
    }
  }

  Future validateConnection() async {
    dbUserEntry = Database.instance.getUser(baseNick: nickname);
    if (dbUserEntry != null) {
      dbId = dbUserEntry!.dbId;
      if (dbUserEntry!.loginPassword == '' || dbUserEntry!.loginPassword == password) {
        authenticated = true;
      }
    } else {
      dbId = Database.instance.newUserDbId();
    }
    tdClient = await TdClient.newClient();
    lInfo(
        function: 'SocketManager.validateConnection',
        message: 'Created tdClient: $tdClient');
    _tdlib = tdClient!.updateStream.listen(
      onTdEvent,
      onError: (error) {
        lError(function: 'TdClient.updateStream...', message: error);
      },
    );

    addNumeric(IrcRplWelcome.withDefaultMessage(nickname));
    addNumeric(
        IrcRplYourHost.withLocalHostname(nickname, Globals.instance.version));
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
        if (!socketWrapper.secure) ...[
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
        ] else ...[
          '',
          'Please join the \u0002#telegirc-signup\u0002 channel to proceed logging in to Telegram.'
        ],
      ]);
    } else {
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
        yield 'Please wait for connection to Telegram servers...';

        await telegramConnectionFuture;

        final telegramUser = await tdClient!.send(td_fn.GetMe()) as td_o.User;

        yield '';
        final usernameDisplay = telegramUser.username.isEmpty ? '' : '\u0002 (\u0002@${telegramUser.username}\u0002)\u0002';
        yield 'Hello, \u0002${telegramUser.firstName} ${telegramUser.lastName}$usernameDisplay\u0002!';
        yield '';

        if (!authenticated) {
          yield 'You are not authenticated!';
          yield 'You will soon join \u0002#a\u0002. Please follow the instructions there.';
          yield '';
        }
        else if (dbUserEntry!.loginPassword.isEmpty) {
          yield '\u0002Important!\u0002';
          yield 'You do not have a password set!';
          yield 'You will soon join \u0002#a\u0002.';
          yield 'Please follow the instructions there to set a password and secure your account.';
          yield '';
        }

        final usefulCommandsLines = [
          'Some useful custom commands:',
          '  /LIST-CHATS == Lists all chats and custom IDs that can be used to join the chat via IRC',
          'Join \u0002#telegirc-help\u0002 for more.',
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

  void onError(Object? error, StackTrace? st) {
    lError(function: 'SocketManager.onError', message: 'Stream error: $error, trace: $st');
    // stderr.writeln(error);
    // stderr.writeln(st);
  }
}

class CommandHandler {
  final String command;
  final dynamic Function(IrcMessage) handler;
  final bool awaitable;

  CommandHandler.normal({required this.command, required this.handler})
      : awaitable = false;
  CommandHandler.async(
      {required this.command, required Future Function(IrcMessage) handler})
      : handler = handler,
        awaitable = true;
}

enum SocketManagerState {
  waitingPassOrNickOrUser,
  waitingNick,
  waitingUser,
  waitingNickOrUser,
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

  Future<List<ChannelListing>> get channels;
  Future<List<UserListing>> getUsers([String? channel]);
}

class ChannelListing {
  final String channel;
  final int clientCount;
  final String topic;

  ChannelListing({
    required this.channel,
    required this.clientCount,
    required this.topic,
  });

  IrcNumericReply toNumericReply({
    required String nickname,
    String? serverName,
  }) =>
      serverName == null
          ? IrcRplList.withLocalHostname(nickname, channel, clientCount, topic)
          : IrcRplList(serverName, nickname, channel, clientCount, topic);
}

class UserListing {
  final String? channel;
  final String username;
  final String nickname;
  final bool away;
  final bool op;
  final bool chanOp;
  final bool voice;
  final String realname;

  UserListing({
    required this.channel,
    required this.username,
    required this.nickname,
    required this.away,
    required this.op,
    required this.chanOp,
    required this.voice,
    required this.realname,
  });


  IrcNumericReply toNumericReply({
    required String nickname,
    String? serverName,
  }) =>
      serverName == null
          ? IrcRplWhoReply.withLocalHostname(
              nickname, channel, username, this.nickname, away, op, chanOp, voice, realname)
          : IrcRplWhoReply(serverName, nickname, channel, username, this.nickname, away, op,
              chanOp, voice, realname);
}
