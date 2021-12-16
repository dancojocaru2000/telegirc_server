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

class IrcRplListStart extends IrcNumericReply {
  IrcRplListStart(String serverName, String client)
      : super(serverName, 321, [client, 'Channel', 'Users  Name'],
            messageName: 'RPL_LISTSTART');
  factory IrcRplListStart.withLocalHostname(String client)
    => IrcRplListStart(Platform.localHostname, client);
}


class IrcRplList extends IrcNumericReply {
  IrcRplList(String serverName, String client, String channel, int clientCount, String topic)
      : super(serverName, 322, [client, channel, clientCount.toString(), topic],
            messageName: 'RPL_LIST');
  factory IrcRplList.withLocalHostname(String client, String channel, int clientCount, String topic)
    => IrcRplList(Platform.localHostname, client, channel, clientCount, topic);
}

class IrcRplListEnd extends IrcNumericReply {
  IrcRplListEnd(String serverName, String client)
      : super(serverName, 323, [client, 'End of /LIST'],
            messageName: 'RPL_LISTEND');
  factory IrcRplListEnd.withLocalHostname(String client)
    => IrcRplListEnd(Platform.localHostname, client);
}

class IrcRplWhoReply extends IrcNumericReply {
  static const int hopcount = 0;

  IrcRplWhoReply(
      String serverName,
      String client,
      String? channel,
      String username,
      String nickname,
      bool away,
      bool op,
      bool chanOp,
      bool voice,
      String realname)
      : super(
          serverName,
          352,
          [
            client,
            channel ?? '*',
            username,
            serverName,
            serverName,
            nickname,
            away ? 'G' : 'H', // Gone or Here
            if (op) '*',
            if (chanOp) '@' else if (voice) '+',
            '$hopcount $realname'
          ],
          messageName: 'RPL_WHOREPLY',
        );
  factory IrcRplWhoReply.withLocalHostname(
      String client,
      String? channel,
      String username,
      String nickname,
      bool away,
      bool op,
      bool chanOp,
      bool voice,
      String realname  
    ) =>
      IrcRplWhoReply(
        Platform.localHostname,
        client,
        channel,
        username,
        nickname,
        away,
        op,
        chanOp,
        voice,
        realname,
      );
}

class IrcRplEndOfWho extends IrcNumericReply {
  IrcRplEndOfWho(String serverName, String client, String? request)
      : super(serverName, 315, [client, request ?? '*', 'End of /WHO list'],
            messageName: 'RPL_ENDOFWHO');
  factory IrcRplEndOfWho.withLocalHostname(String client, String? request)
    => IrcRplEndOfWho(Platform.localHostname, client, request);
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
