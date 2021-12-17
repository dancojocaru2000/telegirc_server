import 'dart:math';

import 'package:tdlib_types/base.dart';
import 'package:tdlib_types/fn.dart' show TdFunction;
import 'package:tdlib_types/fn.dart' as td_fn;
import 'package:tdlib_types/obj.dart' as td_o;

import '../database.dart';
import '../irc.dart';
import '../irc_errors.dart';
import '../irc_replies.dart';
import '../logging.dart';
import '../telegirc_irc.dart';

class AuthHandler extends ServerHandler {
  static const String authBotNick = 'telegirc-auth-bot';
  static const String authChannel = '#a';
  static const String authChannelTopic = 'TelegIRC Authentication Management';

  final bool Function() _isAuth;
  final void Function(bool) _setAuth;
  final int userId;

  bool get authenticated => _isAuth();
  set authenticated(bool newVal) => _setAuth(newVal);

  bool channelJoined = false;
  int chpassChallengeStep = -1;
  String? chpassChallengeRecovery;

  AuthHandler({
    void Function(ServerHandler)? onUnregisterRequest,
    required void Function(IrcMessage) add,
    required void Function(IrcNumericReply) addNumeric,
    required String Function() nickname,
    required Future<T> Function<T extends TdBase>(TdFunction) tdSend,
    required bool Function() isAuthenticated,
    required void Function(bool) setAuthenticated,
    required this.userId,
  }) : _isAuth = isAuthenticated, _setAuth = setAuthenticated, super(
          add: add,
          addNumeric: addNumeric,
          nickname: nickname,
          tdSend: tdSend,
          onUnregisterRequest: onUnregisterRequest,
        );

  void pm(String message) {
    add(IrcMessage(
      prefix: authBotNick,
      command: 'PRIVMSG',
      parameters: [authChannel, message],
    ));
  }

  void joinA({bool suppressMessages = false}) {
    if (channelJoined) {
      return;
    }
    channelJoined = true;

    add(IrcMessage(
      prefix: nickname,
      command: 'JOIN',
      parameters: [authChannel],
    ));
    addNumeric(IrcRplTopic.withLocalHostname(nickname, authChannel, authChannelTopic));
    addNumeric(IrcRplNamReply.withLocalHostname(nickname, ChannelStatus.public, authChannel, [nickname, authBotNick]));
    addNumeric(IrcRplEndOfNames.withLocalHostname(nickname, authChannel));
    pm('Welcome to \u0002#a\u0002.');

    if (!suppressMessages) {
      if (!authenticated) {
        pm('You are not authenticated. The following commands are available:');
        pm('  - /PASS password == supply password in order to authenticate');
        pm('  - /CHPASS == change or reset the password');
      }
      else if (authenticated) {
        if (Database.instance.getUser(id: userId)!.loginPassword.isEmpty) {
          pm("You are authenticated, however you don't have a password on your account.");
          pm('You are strongly encouraged to set a password on your account.');
          pm('The choice is yours, however. Feel free to leave this channel if you wish to continue without a password.');
          pm('');
          pm('The following commands are available:');
          pm('  - /CHPASS == change or reset the password');
        }
        else {
          pm('You are authenticated. The following commands are available:');
          pm('  - /CHPASS == change or reset the password');
          pm('  - /LOCK == lock the current session, requiring the password to once again authenticate');
        }
      }
    }
  }

  bool checkCmdOrMsg(IrcMessage message, String command, [String msgPrefix = '']) {
    try {
      return message.command == command ||
          message.command == 'PRIVMSG' &&
              message.parameters[0] == authChannel &&
              message.parameters[1].split(' ')[0].toUpperCase() == msgPrefix + command;
    } catch (_) {
      return false;
    }
  }

  List<String> getParameters(IrcMessage message) {
    if (message.command == 'PRIVMSG') {
      return message.parameters[1].split(' ').skip(1).toList(growable: false);
    }
    else {
      return message.parameters;
    }
  }

  @override
  Future<bool> handleIrcMessage(IrcMessage message) async {
    if (message.command == 'JOIN' && message.parameters[0] == authChannel) {
      joinA();
      return true;
    }
    else if (message.command == 'PART' && message.parameters[0] == authChannel) {
      chpassChallengeStep = -1;
      if (channelJoined) {
        channelJoined = false;
        add(IrcMessage(
          prefix: nickname,
          command: 'PART',
          parameters: [authChannel],
        ));
      }
      return true;
    }
    else if (checkCmdOrMsg(message, 'CHPASS')) {
      if (!channelJoined) {
        joinA(suppressMessages: true);
      }
      chpassChallengeStep = 0;
      final r = Random();
      final alpha = 'ABCDEFGHIJKLMNPQRSTUVWXYZ123456789';
      chpassChallengeRecovery = List.generate(6, (_) => alpha[r.nextInt(alpha.length)]).join();
      if (Database.instance.getUser(id: userId)!.loginPassword.isEmpty) {
        pm('You currently have no password set.');
        pm('Use the following command:');
        pm('  - /NEWPASS password == set a new password');
        chpassChallengeStep++;
      }
      else if (authenticated) {
        pm('In order to change your password, you need to authenticate again.');
        pm('Use the following command:');
        pm('  - /PASS password == supply password in order to authenticate');
        pm("Alternatively, if you don't know your password, use another device to send the following message in your Saved Messages:");
        pm(chpassChallengeRecovery!);

        authenticated = false;
      }
      else {
        pm('In order to change your password, you need to authenticate.');
        pm('Use the following command:');
        pm('  - /PASS password == supply password in order to authenticate');
        pm("Alternatively, if you don't know your password, use another device to send the following message in your Saved Messages:");
        pm(chpassChallengeRecovery!);
      }
      return true;
    }
    else if (checkCmdOrMsg(message, 'LOCK')) {
      chpassChallengeStep = -1;
      lDebug(function: 'AuthHandler.handleIrcMessage', message: 'Lock command');
      if (!authenticated || Database.instance.getUser(id: userId)!.loginPassword.isEmpty) {
        lDebug(function: 'AuthHandler.handleIrcMessage', message: 'Lock: Not authenticated or empty password');
        return false;
      }
      if (!channelJoined) {
        joinA(suppressMessages: true);
      }
      authenticated = false;
      pm('This session is now locked and you are no longer authenticated.');
      pm('The following commands are available:');
      pm('  - /PASS password == supply password in order to authenticate');
      pm('  - /CHPASS == change or reset the password');
      return true;
    }
    else if (checkCmdOrMsg(message, 'PASS')) {
      if (authenticated) {
        return false;
      }
      if (!channelJoined) {
        joinA(suppressMessages: true);
      }
      final parameters = getParameters(message);
      if (parameters[0] == Database.instance.getUser(id: userId)!.loginPassword) {
        authenticated = true;
        pm('You have authenticated! Welcome.');
        pm('The following commands are available:');
        pm('  - /CHPASS == change or reset the password');
        pm('  - /LOCK == lock the current session, requiring the password to once again authenticate');
        if (chpassChallengeStep != -1) {
          chpassChallengeStep++;
          pm('  - /NEWPASS password == set a new password');
        }
      }
      else {
        Future.delayed(const Duration(milliseconds: 500), () async {
          pm('You have supplied the wrong password. Please try again.');
        });
      }
      return true;
    }
    else if (channelJoined && chpassChallengeStep > 0 && checkCmdOrMsg(message, 'NEWPASS')) {
      final parameters = getParameters(message);
      if (parameters.isEmpty) {
        throw IrcErrNeedMoreParams.withLocalHostname(nickname, message.command);
      }

      chpassChallengeStep = -1;

      final user = Database.instance.getUser(id: userId)!;
      Database.instance.updateUser(user.copyWith(
        loginPassword: parameters[0],
      ));
      authenticated = true;
      pm('You have changed your password and are now authenticated.');
      pm('The following commands are now available.');
      pm('  - /CHPASS == change or reset the password');
      pm('  - /LOCK == lock the current session, requiring the password to once again authenticate');

      return true;
    }
    return false;
  }

  @override
  Future<void> handleTdMessage(TdBase message) async {
    if (message is td_o.UpdateNewMessage) {
      final chatId = message.message!.chatId;
      final chat = await tdSend<td_o.Chat>(td_fn.GetChat(chatId: chatId));
      await chat.type!.match(
        isChatTypePrivate: (pc) async {
          if (pc.userId == (await tdSend<td_o.User>(td_fn.GetMe())).id) {
            await message.message!.content!.match(
              isMessageText: (msgText) async {
                if (chpassChallengeStep != -1 && msgText.text!.text.toUpperCase() == chpassChallengeRecovery) {
                  chpassChallengeStep++;
                  chpassChallengeRecovery = null;
                  pm('You have confirmed password recovery via Telegram Saved Messages.');
                  pm('Use the following command:');
                  pm('  - /NEWPASS password == set a new password');
                  await tdSend(td_fn.DeleteMessages(
                    chatId: chatId,
                    messageIds: [message.message!.id],
                    revoke: true,
                  ));
                }
              },
              otherwise: (_) async {},
            );
          }
        },
        otherwise: (_) async {},
      );
    }
  }

  @override
  Future<List<ChannelListing>> get channels async => [
    ChannelListing(
      channel: authChannel,
      clientCount: channelJoined ? 2 : 1,
      topic: authChannelTopic,
    ),
  ];

  @override
  Future<List<UserListing>> getUsers([String? channel]) async {
    if (channel == null && !channelJoined) {
      return [
        UserListing(
          channel: null,
          username: authBotNick,
          nickname: authBotNick,
          away: false,
          op: true,
          chanOp: false,
          voice: false,
          realname: authBotNick,
        ),
      ];
    }
    else if (channel == authChannel) {
      return [
        UserListing(
          channel: channel,
          username: authBotNick,
          nickname: authBotNick,
          away: false,
          op: true,
          chanOp: false,
          voice: false,
          realname: authBotNick,
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

