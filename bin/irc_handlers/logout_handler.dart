import 'package:tdlib_types/base.dart';
import 'package:tdlib_types/fn.dart' show TdFunction;

import '../irc.dart';
import '../irc_replies.dart';
import '../telegirc_irc.dart';

class LogoutHandler extends ServerHandler {
  static const String logoutBotNick = 'telegirc-logout-bot';
  static const String logoutChannel = '#telegirc-logout';
  static const String logoutChannelTopic = 'Log out from Telegram and remove TelegIRC account';

  final void Function() onLogout;
  bool channelJoined = false;

  LogoutHandler({
    void Function(ServerHandler)? onUnregisterRequest,
    required void Function(IrcMessage) add,
    required void Function(IrcNumericReply) addNumeric,
    required String Function() nickname,
    required Future<T> Function<T extends TdBase>(TdFunction) tdSend,
    required this.onLogout,
  }) : super(
          add: add,
          addNumeric: addNumeric,
          nickname: nickname,
          tdSend: tdSend,
          onUnregisterRequest: onUnregisterRequest,
        );

  @override
  Future<bool> handleIrcMessage(IrcMessage message) async {
    if (message.command == 'JOIN' && message.parameters[0] == logoutChannel || message.command == 'LOGOUT') {
      if (channelJoined) {
        return true;
      }
      add(IrcMessage(
        prefix: nickname,
        command: 'JOIN',
        parameters: [logoutChannel],
      ));
      addNumeric(IrcRplTopic.withLocalHostname(nickname, logoutChannel, logoutChannelTopic));
      addNumeric(IrcRplNamReply.withLocalHostname(nickname, ChannelStatus.public, logoutChannel, [nickname, logoutBotNick]));
      addNumeric(IrcRplEndOfNames.withLocalHostname(nickname, logoutChannel));
      add(IrcMessage(
        prefix: logoutBotNick,
        command: 'PRIVMSG',
        parameters: [logoutChannel, 'Please send "REMOVE" without quotes to remove your TelegIRC account completely and sign TelegIRC out of Telegram.'],
      ));
      channelJoined = true;
      return true;
    }
    else if (message.command == 'PART' && message.parameters[0] == logoutChannel) {
      if (!channelJoined) {
        return true;
      }
      add(IrcMessage(
        prefix: nickname,
        command: 'PART',
        parameters: [logoutChannel],
      ));
      channelJoined = false;
      return true;
    }
    else if (channelJoined && message.command == 'PRIVMSG' && message.parameters[0] == logoutChannel) {
      final msg = message.parameters[1].trim().toUpperCase();
      if (msg == 'REMOVE') {
        add(IrcMessage(
          prefix: logoutBotNick,
          command: 'PRIVMSG',
          parameters: [logoutChannel, 'You are logging out... Goodbye!'],
        ));
        onLogout();
      }
      else {
        add(IrcMessage(
          prefix: logoutBotNick,
          command: 'PRIVMSG',
          parameters: [logoutChannel, 'Unknown message: $msg'],
        ));
      }
      return true;
    }
    return false;
  }

  @override
  Future<void> handleTdMessage(TdBase message) async {}

  @override
  Future<List<ChannelListing>> get channels async => [
    ChannelListing(
      channel: logoutChannel,
      clientCount: channelJoined ? 2 : 1,
      topic: logoutChannelTopic,
    ),
  ];

  @override
  Future<List<UserListing>> getUsers([String? channel]) async {
    if (channel == null && !channelJoined) {
      return [
        UserListing(
          channel: null,
          username: logoutBotNick,
          nickname: logoutBotNick,
          away: false,
          op: true,
          chanOp: false,
          voice: false,
          realname: logoutBotNick,
        ),
      ];
    }
    else if (channel == logoutChannel) {
      return [
        UserListing(
          channel: channel,
          username: logoutBotNick,
          nickname: logoutBotNick,
          away: false,
          op: true,
          chanOp: false,
          voice: false,
          realname: logoutBotNick,
        ),
        if (channelJoined)
        UserListing(
          channel: channel,
          username: nickname,
          nickname: nickname,
          away: false,
          op: false,
          chanOp: false,
          voice: false,
          realname: nickname,
        ),
      ];
    }
    else {
      return [];
    }
  }
}
