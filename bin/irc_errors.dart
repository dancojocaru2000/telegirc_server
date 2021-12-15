import 'dart:io';

import 'irc.dart';

class IrcErrUnknownCommand extends IrcNumericReply {
  IrcErrUnknownCommand(String serverName, String client, String command) : super(serverName, 421, [client, command, 'Unknown command'], messageName: 'ERR_UNKNOWNCOMMAND');
  factory IrcErrUnknownCommand.withLocalHostname(String client, String command)
    => IrcErrUnknownCommand(Platform.localHostname, client, command);
}

class IrcErrNeedMoreParams extends IrcNumericReply {
  IrcErrNeedMoreParams(String serverName, String client, String command) : super(serverName, 461, [client, command, 'Not enough parameters'], messageName: 'ERR_NEEDMOREPARAMS');
  factory IrcErrNeedMoreParams.withLocalHostname(String client, String command)
    => IrcErrNeedMoreParams(Platform.localHostname, client, command);
}

class IrcErrNoNicknameGiven extends IrcNumericReply {
  IrcErrNoNicknameGiven(String serverName, String client) : super(serverName, 431, [client, 'No nickname given'], messageName: 'ERR_NONICKNAMEGIVEN',);
  factory IrcErrNoNicknameGiven.withLocalHostname(String client)
    => IrcErrNoNicknameGiven(Platform.localHostname, client);
}

class IrcErrAlreadyRegistered extends IrcNumericReply {
  IrcErrAlreadyRegistered(String serverName, String client) : super(serverName, 462, [client, 'You may not reregister'], messageName: 'ERR_ALREADYREGISTERED');
  factory IrcErrAlreadyRegistered.withLocalHostname(String client)
    => IrcErrAlreadyRegistered(Platform.localHostname, client);
}

class IrcErrNoSuchChannel extends IrcNumericReply {
  IrcErrNoSuchChannel(String serverName, String client, String channel) : super(serverName, 403, [client, channel, 'No such channel'], messageName: 'ERR_NOSUCHCHANNEL',);
  factory IrcErrNoSuchChannel.withLocalHostname(String client, String channel)
    => IrcErrNoSuchChannel(Platform.localHostname, client, channel);
}

class IrcException implements Exception {
  final IrcMessage message;

  const IrcException(this.message);

  factory IrcException.fromNumeric(IrcNumericReply reply) => IrcException(reply.ircMessage);

  @override
  String toString() {
    return 'IrcException: $message';
  }
}
