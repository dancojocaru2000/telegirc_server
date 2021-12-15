import 'package:tdlib_types/base.dart';
import 'package:tdlib_types/fn.dart' show TdFunction;

import '../irc.dart';
import '../telegirc_irc.dart';

class HelpHandler extends ServerHandler {
  HelpHandler({
    void Function(ServerHandler)? onUnregisterRequest,
    required void Function(IrcMessage) add,
    required void Function(IrcNumericReply) addNumeric,
    required String Function() nickname,
    required Future<dynamic> Function(TdFunction) tdSend,
  }) : super(
          add: add,
          addNumeric: addNumeric,
          nickname: nickname,
          tdSend: tdSend,
          onUnregisterRequest: onUnregisterRequest,
        );

  @override
  Future<bool> handleIrcMessage(IrcMessage message) async {
    // TODO: implement handleIrcMessage
    return false;
  }

  @override
  Future<void> handleTdMessage(TdBase message) async {
    // TODO: implement handleTdMessage
  }
}

