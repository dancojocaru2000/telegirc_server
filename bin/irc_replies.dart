import 'dart:io';

import 'globals.dart';
import 'irc.dart';

class IrcRplWelcome extends IrcNumericReply {
  IrcRplWelcome(String serverName, String client, String welcomeMessage) : super(serverName, 1, [client, welcomeMessage], messageName: 'RPL_WELCOME');
  factory IrcRplWelcome.withLocalHostname(String client, String welcomeMessage)
    => IrcRplWelcome(Platform.localHostname,client,  welcomeMessage);
  factory IrcRplWelcome.withDefaultMessage(String client)
    => IrcRplWelcome.withLocalHostname(client, 'Welcome to TelegIRC!');
}

class IrcRplYourHost extends IrcNumericReply {
  IrcRplYourHost(String serverName, String client, String version) : super(serverName, 2, [client, 'Your host is $serverName, runnning version $version'], messageName: 'RPL_YOURHOST');
  factory IrcRplYourHost.withLocalHostname(String client, String version)
    => IrcRplYourHost(Platform.localHostname, client, version);
}

class IrcRplCreated extends IrcNumericReply {
  IrcRplCreated(String serverName, String client) : super(serverName, 3, [client, 'This server was created at ${Globals.instance.startTime}'], messageName: 'RPL_CREATED');
  factory IrcRplCreated.withLocalHostname(String client)
    => IrcRplCreated(Platform.localHostname, client);
}

class IrcRplMotdStart extends IrcNumericReply {
  IrcRplMotdStart(String serverName, String client, String motdStartLine) : super(serverName, 375, [client, motdStartLine], messageName: 'RPL_MOTDSTART');
  factory IrcRplMotdStart.withLocalHostname(String client, String motdStartLine)
    => IrcRplMotdStart(Platform.localHostname, client, motdStartLine);
  factory IrcRplMotdStart.withDefaultStart(String client)
    => IrcRplMotdStart.withLocalHostname(client, '- TelegIRC Message of the day - ');
}

class IrcRplMotd extends IrcNumericReply {
  IrcRplMotd(String serverName, String client, String motdLine) : super(serverName, 372, [client, motdLine], messageName: 'RPL_MOTD');
  factory IrcRplMotd.withLocalHostname(String client, String motdLine)
    => IrcRplMotd(Platform.localHostname, client, motdLine);
}

class IrcRplEndOfMotd extends IrcNumericReply {
  IrcRplEndOfMotd(String serverName, String client) : super(serverName, 376, [client, 'End of /MOTD command.'], messageName: 'RPL_ENDOFMOTD');
  factory IrcRplEndOfMotd.withLocalHostname(String client)
    => IrcRplEndOfMotd(Platform.localHostname, client);
}

class IrcRplLUserClient extends IrcNumericReply {
  IrcRplLUserClient(
    String serverName, 
    String client, 
    {required int users, 
    required int services, 
    required int servers,}
  ) : super(serverName, 251, [client, 'There are $users users and $services services on $servers servers'], messageName: 'RPL_LUSERCLIENT');
  factory IrcRplLUserClient.withLocalHostname(String client, {required int users, required int services, required int servers})
    => IrcRplLUserClient(
      Platform.localHostname, 
      client,
      users: users,
      services: services,
      servers: servers,
    );
}

class IrcRplLUserMe extends IrcNumericReply {
  IrcRplLUserMe(
    String serverName, 
    String client, 
    {required int clients, 
    required int servers,}
  ) : super(serverName, 255, [client, 'I have $clients clients and $servers servers'], messageName: 'RPL_LUSERME');
  factory IrcRplLUserMe.withLocalHostname(String client, {required int clients, required int servers,})
    => IrcRplLUserMe(
      Platform.localHostname, 
      client,
      clients: clients,
      servers: servers,
    );
}

class IrcRplTopic extends IrcNumericReply {
  IrcRplTopic(String serverName, String client, String channel, String topic) : super(serverName, 332, [client, channel, topic], messageName: 'RPL_TOPIC');
  factory IrcRplTopic.withLocalHostname(String client, String channel, String topic)
    => IrcRplTopic(Platform.localHostname, client, channel, topic);
}

class IrcRplNamReply extends IrcNumericReply {
  IrcRplNamReply(
      String serverName, String client, ChannelStatus symbol, String channel, List<String> nicknames)
      : super(serverName, 353, [client, symbol.toSymbol(), channel, ...nicknames],
            messageName: 'RPL_NAMREPLY');
  factory IrcRplNamReply.withLocalHostname(String client, ChannelStatus symbol, String channel, List<String> nicknames)
    => IrcRplNamReply(Platform.localHostname, client, symbol, channel, nicknames);
}

class IrcRplEndOfNames extends IrcNumericReply {
  IrcRplEndOfNames(String serverName, String client, String channel)
      : super(serverName, 366, [client, channel, 'End of /NAMES list'],
            messageName: 'RPL_ENDOFNAMES');
  factory IrcRplEndOfNames.withLocalHostname(String client, String channel)
    => IrcRplEndOfNames(Platform.localHostname, client, channel);
}

enum ChannelStatus {
  public,
  secret,
  private,
}

extension ChannelStatusString on ChannelStatus {
  String toSymbol() {
    switch (this) {
      case ChannelStatus.public:
        return '=';
      case ChannelStatus.secret:
        return '@';
      case ChannelStatus.private:
        return '*';
    }
  }
}
