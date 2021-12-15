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
    required Future<dynamic> Function(TdFunction) tdSend,
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
        if (message.command == 'PHONE') {
          if (message.parameters.isEmpty) {
            throw IrcException.fromNumeric(IrcErrNeedMoreParams.withLocalHostname(nickname, 'PHONE'));
          }
          state = _RegisterState.loading;
          final phoneNo = message.parameters[0].trim();
          await tdSend(td_fn.SetAuthenticationPhoneNumber(
            phoneNumber: phoneNo, 
            settings: td_o.PhoneNumberAuthenticationSettings(
              allowFlashCall: false,
              allowSmsRetrieverApi: false,
              isCurrentPhoneNumber: false,
            ),
          ));
          return true;
        }
        break;
      case _RegisterState.waitingCode:
        if (message.command == 'CODE') {
          if (message.parameters.isEmpty) {
            throw IrcException.fromNumeric(IrcErrNeedMoreParams.withLocalHostname(nickname, 'CODE'));
          }
          state = _RegisterState.loading;
          final code = message.parameters[0].trim();
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
        if (message.command == 'PASSWORD') {
          if (message.parameters.isEmpty) {
            throw IrcException.fromNumeric(IrcErrNeedMoreParams.withLocalHostname(nickname, 'PASSWORD'));
          }
          state = _RegisterState.loading;
          final password = message.parameters[0].trim();
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
            'Please send your phone number using the command \u0002/PHONE +xxxxxxxx\u0002.',
            'Ensure your phone number is in international format.',
            'For example, an USA phone number is +1978765123, +1 representing the country code.',
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
            'Please send the code using the command \u0002/CODE ' + '0' * codeLength + '\u0002.',
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
            'Please send the password using the command \u0002/PASSWORD ${aswp.passwordHint}\u0002.',
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
          final user = await tdSend(td_fn.GetMe()) as td_o.User;
          final prompt = <String>[
            'Registration successful!',
            'Welcome to TelegIRC, ${user.firstName} ${user.lastName}!',
            '',
            '\u0002Username\u0002: ${user.username}',
            '\u0002Phone number\u0002: ${user.phoneNumber}',
            '\u0002User ID\u0002: ${user.id}',
            '',
            'Join \u0002#telegirc-help\u0002 to learn how to use TelegIRC.',
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
}

enum _RegisterState {
  loading,
  waitingJoin,
  waitingPhone,
  waitingCode,
  waitingPassword,
}