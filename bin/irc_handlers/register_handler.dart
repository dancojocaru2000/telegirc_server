import 'package:qr/qr.dart';
import 'package:tdlib_types/base.dart';
import 'package:tdlib_types/fn.dart' show TdFunction;
import 'package:tdlib_types/fn.dart' as td_fn;
import 'package:tdlib_types/obj.dart' as td_o;

import '../irc.dart';
import '../irc_errors.dart';
import '../irc_replies.dart';
import '../telegirc_irc.dart';

class RegisterHandler extends ServerHandler {
  static const String signupChannel = '#telegirc-signup';
  static const String signupBotNick = 'telegirc-signup-bot';

  final void Function() onRegistered;

  RegisterHandler({
    void Function(ServerHandler)? onUnregisterRequest,
    required void Function(IrcMessage) add,
    required void Function(IrcNumericReply) addNumeric,
    required String Function() nickname,
    required Future<T> Function<T extends TdBase>(TdFunction) tdSend,
    required this.onRegistered,
  }) : super(
          onUnregisterRequest: onUnregisterRequest,
          add: add,
          addNumeric: addNumeric,
          nickname: nickname,
          tdSend: tdSend,
        );

  _RegisterState state = _RegisterState.waitingJoin;

  Future doJoin() async {
    add(IrcMessage(
      prefix: nickname,
      command: 'JOIN',
      parameters: [signupChannel],
    ));
    addNumeric(IrcRplTopic.withLocalHostname(nickname, signupChannel, 'Sign up to TelegIRC'));
    addNumeric(IrcRplNamReply.withLocalHostname(nickname, ChannelStatus.public, signupChannel, [nickname, signupBotNick]));
    addNumeric(IrcRplEndOfNames.withLocalHostname(nickname, signupChannel));
    // add(IrcMessage(
    //   prefix: signupBotNick,
    //   command: 'PRIVMSG',
    //   parameters: [signupChannel, "Hint: if your client doesn't allow you to send custom commands, you may send the commands without the slash in this channel."],
    // ));
  }

  bool checkCmdOrMsg(IrcMessage message, String command, [String msgPrefix = '']) {
    try {
      return message.command == command ||
          message.command == 'PRIVMSG' &&
              message.parameters[0] == signupChannel &&
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
    switch (state) {
      case _RegisterState.waitingJoin:
        if (message.command == 'JOIN' && message.parameters[0] == signupChannel) {
          await doJoin();
          state = _RegisterState.loading;
          return true;
        }
        break;
      case _RegisterState.waitingPhone:
        if (checkCmdOrMsg(message, 'PHONE')) {
          final parameters = getParameters(message);
          if (parameters.isEmpty) {
            throw IrcException.fromNumeric(IrcErrNeedMoreParams.withLocalHostname(nickname, 'PHONE'));
          }
          state = _RegisterState.loading;
          final phoneNo = parameters[0].trim();
          await tdSend(td_fn.SetAuthenticationPhoneNumber(
            phoneNumber: phoneNo, 
            settings: td_o.PhoneNumberAuthenticationSettings(
              allowMissedCall: false,
              allowFlashCall: false,
              allowSmsRetrieverApi: false,
              isCurrentPhoneNumber: false,
              authenticationTokens: [],
            ),
          ));
          return true;
        }
        else if (checkCmdOrMsg(message, 'QR')) {
          state = _RegisterState.loading;
          await tdSend(td_fn.RequestQrCodeAuthentication(otherUserIds: []));
          return true;
        }
        break;
      case _RegisterState.waitingCode:
        if (checkCmdOrMsg(message, 'CODE')) {
          final parameters = getParameters(message);
          if (parameters.isEmpty) {
            throw IrcException.fromNumeric(IrcErrNeedMoreParams.withLocalHostname(nickname, 'CODE'));
          }
          state = _RegisterState.loading;
          final code = parameters[0].trim();
          try {
            await tdSend(td_fn.CheckAuthenticationCode(
              code: code, 
            ));
          } on td_o.Error catch (e) {
            if (e.code == 400) {
              add(IrcMessage(
                prefix: signupBotNick,
                command: 'PRIVMSG',
                parameters: [signupChannel, 'The code you entered is invalid. Try again.'],
              ));
              state = _RegisterState.waitingCode;
            }
            else {
              rethrow;
            }
          }
          return true;
        }
        break;
      case _RegisterState.waitingPassword:
        if (checkCmdOrMsg(message, 'PASSWORD')) {
          final parameters = getParameters(message);
          if (parameters.isEmpty) {
            throw IrcException.fromNumeric(IrcErrNeedMoreParams.withLocalHostname(nickname, 'PASSWORD'));
          }
          state = _RegisterState.loading;
          final password = parameters[0].trim();
          try {
            await tdSend(td_fn.CheckAuthenticationPassword(
              password: password, 
            ));
          } on td_o.Error catch (e) {
            if (e.code == 400) {
              add(IrcMessage(
                prefix: signupBotNick,
                command: 'PRIVMSG',
                parameters: [signupChannel, 'The password you entered is invalid. Try again.'],
              ));
              state = _RegisterState.waitingPassword;
            }
            else {
              rethrow;
            }
          }
          return true;
        }
        break;
      case _RegisterState.loading:
        break;
      case _RegisterState.waitingQr:
        break;
    }
    return false;
  }

  @override
  Future<void> handleTdMessage(TdBase message) async {
    if (message is td_o.UpdateAuthorizationState) {
      await message.authorizationState!.match(
        isAuthorizationStateWaitPhoneNumber: (_) async {
          if (state != _RegisterState.waitingPhone) {
            await doJoin();
          }
          final prompt = [
            'Please send your phone number using the command \u0002PHONE +xxxxxxxx\u0002.',
            'Ensure your phone number is in international format.',
            'For example, an USA phone number is +1978765123, +1 representing the country code.',
            '',
            'Alternatively, use the command \u0002QR\u0002 to connect by scanning a QR code on another device.',
          ];
          for (final msg in prompt) {
            add(IrcMessage(
              prefix: signupBotNick,
              command: 'PRIVMSG',
              parameters: [signupChannel, msg],
            ));
          }
          state = _RegisterState.waitingPhone;
        },
        isAuthorizationStateWaitCode: (aswc) async {
          final prompt = <String>[];
          var codeLength = 0;
          aswc.codeInfo!.type!.match(
            isAuthenticationCodeTypeCall: (ntc) {
              codeLength = ntc.length;
              prompt.add('You will receive a ${ntc.length} digit code via a phone call on ${aswc.codeInfo!.phoneNumber}.');
            },
            isAuthenticationCodeTypeTelegramMessage: (nttm) {
              codeLength = nttm.length;
              prompt.add('You will receive a ${nttm.length} digit code via Telegram on another device.');
            },
            isAuthenticationCodeTypeSms: (ntsms) {
              codeLength = ntsms.length;
              prompt.add('You will receive a ${ntsms.length} digit code via a SMS on ${aswc.codeInfo!.phoneNumber}.');
            },
            otherwise: (_) {},
          );
          prompt.addAll([
            'Please send the code using the command \u0002CODE ' + '0' * codeLength + '\u0002.',
          ]);
          for (final msg in prompt) {
            add(IrcMessage(
              prefix: signupBotNick,
              command: 'PRIVMSG',
              parameters: [signupChannel, msg],
            ));
          }
          state = _RegisterState.waitingCode;
        },
        isAuthorizationStateWaitPassword: (aswp) async {
          final prompt = <String>[
            'Your account is protected with a password.',
            ''
            'Please send the password using the command \u0002PASSWORD ${aswp.passwordHint}\u0002.',
          ];
          for (final msg in prompt) {
            add(IrcMessage(
              prefix: signupBotNick,
              command: 'PRIVMSG',
              parameters: [signupChannel, msg],
            ));
          }
          state = _RegisterState.waitingPassword;
        },
        isAuthorizationStateWaitOtherDeviceConfirmation: (odc) async {
          final prompt = <String>[
            'Please scan the following QR code using a Telegram app on another device.',
            'If a new QR code is generated before you scan a previous one, it will be sent to you.',
            'Please scan the latest one.',
          ];

          for (final msg in prompt) {
            add(IrcMessage(
              prefix: signupBotNick,
              command: 'PRIVMSG',
              parameters: [signupChannel, msg],
            ));
          }

          final qrCode = QrCode.fromData(data: odc.link, errorCorrectLevel: QrErrorCorrectLevel.M);
          final qrImage = QrImage(qrCode);
          final qrMessages = List.generate(
            qrCode.moduleCount, 
            (row) => List.generate(
              qrCode.moduleCount, 
              (col) => qrImage.isDark(row, col) ? '\u000301██' : '\u000300██',
            ).join(''),
          );
          for (final line in qrMessages) {
            add(IrcMessage(
              prefix: signupBotNick,
              command: 'PRIVMSG',
              parameters: [signupChannel, line],
            ));
          }

          state = _RegisterState.waitingQr;
        },
        isAuthorizationStateWaitRegistration: (aswr) async {
          final prompt = <String>[
            'Your do not have a Telegram account and need to register.',
            'For the moment, this cannot be done through TelegIRC.',
            'Please register using another Telegram application and then submit your phone number again.',
          ];
          for (final msg in prompt) {
            add(IrcMessage(
              prefix: signupBotNick,
              command: 'PRIVMSG',
              parameters: [signupChannel, msg],
            ));
          }
          state = _RegisterState.waitingPhone;
        },
        isAuthorizationStateReady: (_) async {
          final user = await tdSend<td_o.User>(td_fn.GetMe());
          final prompt = <String>[
            'Registration successful!',
            'Welcome to TelegIRC, ${user.firstName} ${user.lastName}!',
            '',
            '\u0002Username\u0002: ${user.username}',
            '\u0002Phone number\u0002: ${user.phoneNumber}',
            '\u0002User ID\u0002: ${user.id}',
            // TODO: Implement #telegirc-help
            // '',
            // 'Join \u0002#telegirc-help\u0002 to learn how to use TelegIRC.',
            '',
            '\u0002Important!\u0002',
            'Please take some time to secure your account by setting a password!',
            'Join \u0002#a\u0002 to proceed.',
            '',
            'You will automatically leave from this channel in 30 seconds.',
          ];
          for (final msg in prompt) {
            add(IrcMessage(
              prefix: signupBotNick,
              command: 'PRIVMSG',
              parameters: [signupChannel, msg],
            ));
          }
          onRegistered();
          Future.delayed(const Duration(seconds: 30), () async {
            add(IrcMessage(
              prefix: nickname,
              command: 'PART',
              parameters: [signupChannel],
            ));
          });
          onUnregisterRequest?.call(this);
        },
        otherwise: (_) => Future.value(null),
      );
    }
  }

  @override
  Future<List<ChannelListing>> get channels async => [
    ChannelListing(
      channel: signupChannel,
      clientCount: 1,
      topic: 'Sign up to TelegIRC',
    ),
  ];

  @override
  Future<List<UserListing>> getUsers([String? channel]) async {
    final channelJoined = state != _RegisterState.waitingJoin;
    if (channel == null && !channelJoined) {
      return [
        UserListing(
          channel: null,
          username: signupBotNick,
          nickname: signupBotNick,
          away: false,
          op: true,
          chanOp: false,
          voice: false,
          realname: signupBotNick,
        ),
      ];
    }
    else if (channel == signupChannel) {
      return [
        UserListing(
          channel: channel,
          username: signupBotNick,
          nickname: signupBotNick,
          away: false,
          op: true,
          chanOp: false,
          voice: false,
          realname: signupBotNick,
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

enum _RegisterState {
  loading,
  waitingJoin,
  waitingPhone,
  waitingCode,
  waitingPassword,
  waitingQr,
}