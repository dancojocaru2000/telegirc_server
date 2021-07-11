import 'dart:io';

import 'globals.dart';
import 'irc.dart';
import 'irc_errors.dart';
import 'irc_replies.dart';
import 'irc_socket.dart';

class SocketManager {
  final IrcSocketWrapper socketWrapper;
  SocketManagerState _state;

  SocketManagerState get state => _state;

  String? password;
  late String nickname;
  late String username;
  late String realname;

  late List<CommandHandler> _normalHandlers;

  SocketManager(this.socketWrapper) : _state = SocketManagerState.waitingPassOrNick {
    socketWrapper.stream.listen(
      (message) {
        try {
          onMessage(message);
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
      print('${socketWrapper.innerSocket.remoteAddress} <- ${message.command}');
    }
    socketWrapper.add(message);
  }

  void addNumeric(IrcNumericReply reply) => add(reply.ircMessage);

  void onMessage(IrcMessage message) async {
    // Logging
    if (message.command != 'PING' && message.command != 'PONG') {
      print('${socketWrapper.innerSocket.remoteAddress} -> ${message.command}');
    }

    validateMessage(message);

    if (message.command == 'PING') {
      add(IrcMessagePong.withLocalHostname());
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
        if (!handled) {
          throw IrcErrUnknownCommand.withLocalHostname(nickname, message.command);
        }
        break;
      case SocketManagerState.disconnected:
        break;
    }
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
    }
  }

  Future validateConnection() async {
    // TODO: tdlib validation

    addNumeric(IrcRplWelcome.withDefaultMessage(nickname));
    addNumeric(IrcRplYourHost.withLocalHostname(nickname, Globals.instance.version));
    addNumeric(IrcRplCreated.withLocalHostname(nickname));

    await sendLusers();

    await sendMotd();

    _state = SocketManagerState.connected;
  }

  Future sendMotd() async {
    addNumeric(IrcRplMotdStart.withDefaultStart(nickname));

    final String? telegramName = null;

    late List<String> lines;
    if (telegramName == null) {
      lines = [
        'Hello, guest!',
        '',
        'The current login port is: ${Globals.instance.loginPort}',
        '',
        'Please use the login program in order to login on TelegIRC',
        'and obtain your account details for login via IRC.',
        if (!socketWrapper.secure) ... [
          '',
          'WARNING: Please be advised that you are currently connected through',
          'an unsecure, plain text connection. Anybody can read all the data',
          'communicated through this connection.',
          '',
          'While connecting to IRC unsecurely is supported, IT IS HEAVILY DISCOURAGED!',
          'You are fully responsible for any security issues that arise',
          'due to the unsecure connection.',
          '',
          'To connect securely, instruct your IRC client to use TLS',
          'and connect to port ${Globals.instance.securePort}.'
        ],
      ];
    }
    else {
      lines = [
        'Hello, $telegramName!',
        '',
        if (!socketWrapper.secure) ...[
          'WARNING: You are connected through an unsecure, plain text connection.',
          'Anybody inspecting your network will see all the data you send in plain text.',
          'It is recommended that you disconnect and instead configure your IRC client',
          'to connect securely on port ${Globals.instance.securePort}.',
          '',
        ],
        'Some useful custom commands:',
        '  LIST-CHATS == Lists all chats and custom IDs that can be used to join the chat via IRC',
      ];
    }

    for (final line in lines) {
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