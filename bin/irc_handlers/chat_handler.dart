import 'package:tdlib_types/base.dart';
import 'package:tdlib_types/fn.dart' show TdFunction;
import 'package:tdlib_types/fn.dart' as td_fn;
import 'package:tdlib_types/obj.dart' as td_o;

import '../extensions.dart';
import '../irc.dart';
import '../irc_replies.dart';
import '../logging.dart';
import '../settings_wrapper.dart';
import '../telegirc_irc.dart';

class ChatHandler extends ServerHandler {
  static const String chatBotNick = 'telegirc-chat-bot';
  static const dirChannel = '#telegirc-dir';
  static const dirChannelTopic = 'TelegIRC Directory - find channels here';

  final SettingsWrapper settings;

  List<td_o.Chat> chats = [];
  List<int> joinedChats = [];
  Map<String, int> usernameCache = {};

  bool flagNextSilent = false;
  bool flagNoWebpagePreview = false;
  int? flagReplyTo;

  bool dirJoined = false;
  
  final bool Function() _isAuth;
  final bool Function() _isAway;

  bool get authenticated => _isAuth();
  bool get away => _isAway();

  final Map<int, List<int>> messagesToRead = {};

  ChatHandler({
    void Function(ServerHandler)? onUnregisterRequest,
    required void Function(IrcMessage) add,
    required void Function(IrcNumericReply) addNumeric,
    required String Function() nickname,
    required Future<T> Function<T extends TdBase>(TdFunction) tdSend,
    required bool Function() isAuthenticated,
    required bool Function() isAway,
    required this.settings,
    List<String>? pendingJoins,
  }) : _isAuth = isAuthenticated, _isAway = isAway, super(
          add: add,
          addNumeric: addNumeric,
          nickname: nickname,
          tdSend: tdSend,
          onUnregisterRequest: onUnregisterRequest,
        ) {
          refreshChats().then((_) { channels; }).then((_) {
            return Future.wait(
              pendingJoins
                ?.map((chan) => IrcMessage(
                    command: 'JOIN',
                    parameters: [chan],
                  ))
                .map(handleIrcMessage)
                .toList() 
                ?? [],
            );
          });
        }

  Future refreshChats() async {
    final chatIds = await tdSend<td_o.Chats>(td_fn.GetChats(chatList: null,limit: 100));
    chats = (await Future.wait(chatIds.chatIds.map((chatId) async => (await tdSend<td_o.Chat>(td_fn.GetChat(chatId: chatId)))))).toList();
  }

  int? findChatId(String channelName) {
    if (channelName.startsWith('#')) {
      channelName = channelName.substring(1);
    }
    if (channelName.startsWith('@')) {
      channelName = channelName.substring(1);
    }
    if (usernameCache.containsKey(channelName.toLowerCase())) {
      return usernameCache[channelName.toLowerCase()];
    }
    for (final chat in chats) {
      if (chat.id.toString() == channelName) {
        return chat.id;
      }
    }
  }

  Future joinChat(int chatId, String channelName) async {
    joinedChats.add(chatId);
    final chat = chats.where((c) => c.id == chatId).first;
    final channel = await getChannel(chat);
    add(IrcMessage(
      prefix: nickname,
      command: 'JOIN',
      parameters: ['#$channelName'],
    ));
    addNumeric(IrcRplTopic.withLocalHostname(nickname, '#$channelName', channel.topic));
    addNumeric(IrcRplNamReply.withLocalHostname(
      nickname,
      ChannelStatus.public,
      '#$channelName',
      (await getUsers('#$channelName'))
          .map((u) => u.nickname)
          .toList(growable: false),
    ));
    await tdSend(td_fn.OpenChat(chatId: chatId));
    addNumeric(IrcRplEndOfNames.withLocalHostname(nickname, '#$channelName'));
    if (!authenticated) {
      void send(String msg) {
        add(IrcMessage(
          prefix: chatBotNick,
          command: 'PRIVMSG',
          parameters: ['#$channelName', msg],
        ));
      }
      send('You are not authenticated!');
      send('In order to communicate, you must authenticate.');
      send('Join \u0002#a\u0002 to proceed.');
      return;
    }

    if (settings.recallOnJoin) {
      await handleChatBotCmd('#$channelName', 'recall ${settings.recallLength}');
    }
  }

  Future markAsRead() async {
    for (final entry in messagesToRead.entries) {
      final msg = entry.value.toList();
      entry.value.clear();
      await tdSend(td_fn.ViewMessages(
        chatId: entry.key,
        messageIds: msg,
        messageThreadId: 0,
        forceRead: true,
      ));
    }
  }

  Future sendMessage(int chatId, String ircMsg) async {
    final entities = <td_o.TextEntity>[];
    var ircMsgCodeUnits = ircMsg.codeUnits.toList();
    var entitiesStack = <td_o.TextEntity>[];
    for (var i = 0; i < ircMsgCodeUnits.length; i++) {
      switch(ircMsgCodeUnits[i]) {
        case 0x02: // bold
          if (entitiesStack.where((e) => e.type is td_o.TextEntityTypeBold).isNotEmpty) {
            // Finish current
            final otherEntities = entitiesStack.where((e) => e.type is! td_o.TextEntityTypeBold).toList(growable: false);
            entities.addAll(entitiesStack.map((e) {
              return td_o.TextEntity(
                offset: e.offset,
                type: e.type,
                length: i - e.offset,
              );
            }));
            entitiesStack = otherEntities.map((e) {
              return td_o.TextEntity(
                offset: i,
                length: -1,
                type: e.type,
              );
            }).toList();
          }
          else {
            entitiesStack.add(td_o.TextEntity(
              offset: i, 
              length: -1,
              type: td_o.TextEntityTypeBold(),
            ));
          }

          ircMsgCodeUnits.removeAt(i);
          i--;
          break;
        case 0x1d: // italic
          if (entitiesStack.where((e) => e.type is td_o.TextEntityTypeItalic).isNotEmpty) {
            // Finish current
            final otherEntities = entitiesStack.where((e) => e.type is! td_o.TextEntityTypeItalic).toList(growable: false);
            entities.addAll(entitiesStack.map((e) {
              return td_o.TextEntity(
                offset: e.offset,
                type: e.type,
                length: i - e.offset,
              );
            }));
            entitiesStack = otherEntities.map((e) {
              return td_o.TextEntity(
                offset: i,
                length: -1,
                type: e.type,
              );
            }).toList();
          }
          else {
            entitiesStack.add(td_o.TextEntity(
              offset: i, 
              length: -1,
              type: td_o.TextEntityTypeItalic(),
            ));
          }

          ircMsgCodeUnits.removeAt(i);
          i--;
          break;
        case 0x1f: // underline
          if (entitiesStack.where((e) => e.type is td_o.TextEntityTypeUnderline).isNotEmpty) {
            // Finish current
            final otherEntities = entitiesStack.where((e) => e.type is! td_o.TextEntityTypeUnderline).toList(growable: false);
            entities.addAll(entitiesStack.map((e) {
              return td_o.TextEntity(
                offset: e.offset,
                type: e.type,
                length: i - e.offset,
              );
            }));
            entitiesStack = otherEntities.map((e) {
              return td_o.TextEntity(
                offset: i,
                length: -1,
                type: e.type,
              );
            }).toList();
          }
          else {
            entitiesStack.add(td_o.TextEntity(
              offset: i, 
              length: -1,
              type: td_o.TextEntityTypeUnderline(),
            ));
          }

          ircMsgCodeUnits.removeAt(i);
          i--;
          break;
        case 0x1e: // strikethrough
          if (entitiesStack.where((e) => e.type is td_o.TextEntityTypeStrikethrough).isNotEmpty) {
            // Finish current
            final otherEntities = entitiesStack.where((e) => e.type is! td_o.TextEntityTypeStrikethrough).toList(growable: false);
            entities.addAll(entitiesStack.map((e) {
              return td_o.TextEntity(
                offset: e.offset,
                type: e.type,
                length: i - e.offset,
              );
            }));
            entitiesStack = otherEntities.map((e) {
              return td_o.TextEntity(
                offset: i,
                length: -1,
                type: e.type,
              );
            }).toList();
          }
          else {
            entitiesStack.add(td_o.TextEntity(
              offset: i, 
              length: -1,
              type: td_o.TextEntityTypeStrikethrough(),
            ));
          }

          ircMsgCodeUnits.removeAt(i);
          i--;
          break;
        case 0x11: // monospace
          if (entitiesStack.where((e) => e.type is td_o.TextEntityTypePre).isNotEmpty) {
            // Finish current
            final otherEntities = entitiesStack.where((e) => e.type is! td_o.TextEntityTypePre).toList(growable: false);
            entities.addAll(entitiesStack.map((e) {
              return td_o.TextEntity(
                offset: e.offset,
                type: e.type,
                length: i - e.offset,
              );
            }));
            entitiesStack = otherEntities.map((e) {
              return td_o.TextEntity(
                offset: i,
                length: -1,
                type: e.type,
              );
            }).toList();
          }
          else {
            entitiesStack.add(td_o.TextEntity(
              offset: i, 
              length: -1,
              type: td_o.TextEntityTypePre(),
            ));
          }

          ircMsgCodeUnits.removeAt(i);
          i--;
          break;
        case 0x0f: // reset
          while (entitiesStack.isNotEmpty) {
            final entity = entitiesStack.removeLast();
            final length = i - entity.offset;
            entities.add(td_o.TextEntity(
              length: length,
              offset: entity.offset,
              type: entity.type,
            ));
          }
          ircMsgCodeUnits.removeAt(i);
          i--;
          break;
        case 0x16: // reverse color
          ircMsgCodeUnits.removeAt(i);
          i--;
          break;
        case 0x04: // hex color
          ircMsgCodeUnits.removeAt(i);
          i--;
          // TODO: Clear message of color digits
          break;
        case 0x03: // color
          ircMsgCodeUnits.removeAt(i);
          i--;
          // TODO: Clear message of color digits
          break;
      }
    }
    while (entitiesStack.isNotEmpty) {
      final entity = entitiesStack.removeLast();
      final length = ircMsgCodeUnits.length - entity.offset;
      entities.add(td_o.TextEntity(
        length: length,
        offset: entity.offset,
        type: entity.type,
      ));
    }
    ircMsg = String.fromCharCodes(ircMsgCodeUnits);

    await tdSend(td_fn.SendMessage(
      chatId: chatId,
      messageThreadId: 0,
      replyMarkup: null,
      replyToMessageId: flagReplyTo ?? 0,
      options: td_o.MessageSendOptions(
        disableNotification: flagNextSilent,
        fromBackground: false,
        schedulingState: null,
      ),
      inputMessageContent: td_o.InputMessageText(
        clearDraft: true,
        disableWebPagePreview: flagNoWebpagePreview,
        text: td_o.FormattedText(
          text: ircMsg,
          entities: entities,
        ),
      )
    ));

    // Reset flags
    flagNextSilent = false;
    flagNoWebpagePreview = false;
    flagReplyTo = null;
  }

  Future handleChatBotCmd(String channel, String cmd) async {
    final chatId = findChatId(channel)!;
    cmd = cmd.trim();
    if (cmd.isEmpty) {
      return;
    }
    final params = cmd.split(' ');
    switch (params[0].toLowerCase()) {
      case 'recall':
        final defaultLength = settings.getSetting<int>(Setting.recallLength);
        final length = (params.length > 1 ? (int.tryParse(params[1])) ?? defaultLength : defaultLength).clamp(1, 1000);
        final messages = <td_o.Message>[];
        while (messages.length < length) {
          final msg = await tdSend<td_o.Messages>(td_fn.GetChatHistory(
            chatId: chatId,
            fromMessageId: messages.isEmpty ? 0 : messages.last.id,
            limit: length.clamp(1, 100),
            offset: 0,
            onlyLocal: false,
          ));
          if (msg.totalCount == 0 || msg.messages.isEmpty) {
            break;
          }
          messages.addAll(msg.messages.map((e) => e!));
        }
        add(IrcMessage(
          prefix: chatBotNick,
          command: 'PRIVMSG',
          parameters: [channel, '== Message Recall ==']
        ));
        for (final message in messages.reversed) {
          await tdMsgToIrc(channel, message);
        }
        add(IrcMessage(
          prefix: chatBotNick,
          command: 'PRIVMSG',
          parameters: [channel, '== Recall End ==']
        ));
        break; 
      case 'silent':
      case 'quiet':
        flagNextSilent = true;
        break;
      case 'no_webpage_preview':
        flagNoWebpagePreview = true;
        break;
      case 'reply':
        if (params.length > 1) {
          flagReplyTo = int.tryParse(params[1]);
        }
        break;
      case 'del':
        await tdSend(td_fn.DeleteMessages(
          chatId: chatId,
          messageIds: params.skip(1).map((e) => int.tryParse(e)).whereType<int>().toList(growable: false),
          revoke: true,
        ));
        break;
      case 'del_me':
        await tdSend(td_fn.DeleteMessages(
          chatId: chatId,
          messageIds: params.skip(1).map((e) => int.tryParse(e)).whereType<int>().toList(growable: false),
          revoke: false,
        ));
        break;
      default:
        add(IrcMessage(
          prefix: chatBotNick,
          command: 'PRIVMSG',
          parameters: [channel, 'Unknown command: ${params[0]}']
        ));
    }
  }

  Future tdMsgToIrc(String channel, td_o.Message msg) async {
    var sender = '';
    var ircMsg = '';
    await msg.senderId!.match(
      isMessageSenderChat: (_) async {
        sender = chatBotNick;
        ircMsg += '[Chat Message] ';
      },
      isMessageSenderUser: (u) async {
        sender = (await getUser(userId: u.userId, channel: '')).nickname;
      }
    );

    // Show message id
    ircMsg += '\u000314[id: ${msg.id}]\u0003 ';

    td_o.FormattedText? fmtTxt;
    await msg.content!.match(
      isMessageAnimatedEmoji: (ae) async {
        ircMsg += ae.emoji;
      },
      isMessageAnimation: (a) async {
        if (a.isSecret) {
          ircMsg += '[Secret] ';
        }
        ircMsg += '[Animation] ';
        fmtTxt = a.caption;
      },
      isMessageAudio: (a) async {
        ircMsg += '[Audio] ';
        fmtTxt = a.caption;
      },
      isMessageDice: (d) async {
        ircMsg += '[Dice] ${d.value}';
      },
      isMessageExpiredPhoto: (e) async {
        ircMsg += '[Expired Photo]';
      },
      isMessageExpiredVideo: (e) async {
        ircMsg += '[Expired Video]';
      },
      isMessagePhoto: (p) async {
        if (p.isSecret) {
          ircMsg += '[Secret] ';
        }
        ircMsg += '[Photo] ';
        fmtTxt = p.caption;
      },
      isMessageSticker: (s) async {
        ircMsg += '[Sticker] ${s.sticker!.emoji}';
      },
      isMessageText: (t) async {
        fmtTxt = t.text;
      },
      isMessageVideo: (v) async {
        if (v.isSecret) {
          ircMsg += '[Secret] ';
        }
        ircMsg += '[Video] ';
        fmtTxt = v.caption;
      },
      isMessageContact: (contact) async {
        ircMsg += '[Contact] ';
        final fields = [];
        if (contact.contact!.userId > 0) {
          fields.add('Id: ${contact.contact!.userId}');
        }
        if (contact.contact!.firstName.isNotEmpty) {
          fields.add('Name: ${contact.contact!.firstName} ${contact.contact!.lastName}');
        }
        if (contact.contact!.phoneNumber.isNotEmpty) {
          fields.add('Phone number: ${contact.contact!.phoneNumber}');
        }
        ircMsg += fields.join(', ');
      },
      isMessageGame: (game) async {
        ircMsg += '[Game] ${game.game!.title}';
      },
      isMessageGameScore: (gs) async {
        ircMsg += '[Game Score] New Score: ${gs.score}';
      },
      isMessageCall: (call) async {
        if (call.isVideo) {
          ircMsg += '[Video Call] ';
        }
        else {
          ircMsg += '[Call] ';
        }
        final duration = Duration(seconds: call.duration);
        ircMsg += '$duration ';
        call.discardReason?.match(
          isCallDiscardReasonDeclined: (_) {
            ircMsg += 'Declined';
          },
          isCallDiscardReasonDisconnected: (_) {
            ircMsg += 'Disconnected';
          },
          isCallDiscardReasonMissed: (_) {
            ircMsg += 'Missed';
          },
          otherwise: (_) {},
        );
      },
      isMessageChatChangeTitle: (titleChange) async {
        ircMsg += '[Chat Title Change] ${titleChange.title}';
      },
      isMessageUnsupported: (_) async {
        ircMsg += '[Unsupported by TelegIRC]';
      },
      isMessageLocation: (location) async {
        ircMsg += '[Location] ';
        final latLng = '${location.location!.latitude},${location.location!.longitude}';
        ircMsg += latLng;
        if (location.location!.horizontalAccuracy != 0) {
          ircMsg += ', ${location.location!.horizontalAccuracy} m accuracy';
        }
        if (location.heading != 0) {
          ircMsg += ', heading ';
          if (location.heading >= 337.5 || location.heading < 22.5) {
            ircMsg += 'North';
          }
          else if (location.heading < 67.5) {
            ircMsg += 'North-East';
          }
          else if (location.heading < 112.5) {
            ircMsg += 'East';
          }
          else if (location.heading < 157.5) {
            ircMsg += 'South-East';
          }
          else if (location.heading < 202.5) {
            ircMsg += 'South';
          }
          else if (location.heading < 247.5) {
            ircMsg += 'South-West';
          }
          else if (location.heading < 292.5) {
            ircMsg += 'West';
          }
          else if (location.heading < 337.5) {
            ircMsg += 'North-West';
          }
          else {
            ircMsg += 'unknown, report this error please';
          }
        }
      },
      isMessageScreenshotTaken: (st) async {
        ircMsg += '[Screenshot taken!]';
      },
      isMessageContactRegistered: (cr) async {
        final senderId = (msg.senderId as td_o.MessageSenderUser).userId;
        final sender = await tdSend<td_o.User>(td_fn.GetUser(userId: senderId));
        final senderName = sender.lastName.isEmpty ? sender.firstName : '${sender.firstName} ${sender.lastName}';
        ircMsg += '[$senderName joined Telegram!]';
      },
      otherwise: (_) async {
        ircMsg += '[Unable to process, message kind: ${msg.content.runtimeType}]';
      }
    );

    if (fmtTxt != null) {
      var s = fmtTxt!.text;
      var insertedAt = [];

      void insertAt(String toInsert, int pos) {
        pos += insertedAt.where((element) => element <= pos).length;
        insertedAt.add(pos);
        s = s.substring(0, pos) + toInsert + s.substring(pos);
      }

      for (final entity in fmtTxt!.entities) {
        if (entity == null) {
          continue;
        }
        var entityChar = entity.type!.match(
          isTextEntityTypeBold: (_) => '\u0002',
          isTextEntityTypeItalic: (_) => '\u001D',
          isTextEntityTypeUnderline: (_) => '\u001F',
          isTextEntityTypeStrikethrough: (_) => '\u001E',
          isTextEntityTypeCode: (_) => '\u0011',
          isTextEntityTypePre: (_) => '\u0011',
          isTextEntityTypePreCode: (_) => '\u0011',
          otherwise: (_) => '',
        );
        if (entityChar.isEmpty) {
          continue;
        }

        insertAt(entityChar, entity.offset);
        insertAt(entityChar, entity.offset + entity.length);
      }

      ircMsg += s;
    }

    var startedInPrevious = '';
    final formattingChars = ['\u0002', '\u001D', '\u001F', '\u001E', '\u0011'];
    for (var msg in ircMsg.split(RegExp(r'\r?\n'))) {
      msg = '$startedInPrevious$msg';

      final foundFormattingChars = msg.codeUnits
        .map((cu) => String.fromCharCode(cu))
        .where(formattingChars.contains)
        .toList(growable: false);
      for (final fmtChar in formattingChars) {
        if (foundFormattingChars.where((e) => e == fmtChar).length % 2 != 0) {
          startedInPrevious += fmtChar;
        }
      }

      add(IrcMessage(
        prefix: sender,
        command: 'PRIVMSG',
        parameters: [channel, msg],
      ));

    }

    // Mark message as read
    if (!messagesToRead.containsKey(msg.chatId)) {
      messagesToRead[msg.chatId] = [];
    }
    messagesToRead[msg.chatId]!.add(msg.id);
    if (!away) {
      await markAsRead();
    }
  }

  void dirPrivMsgSend(String msg) {
    add(IrcMessage(
      prefix: chatBotNick,
      command: 'PRIVMSG',
      parameters: [dirChannel, msg],
    ));
  }

  void dirJoin() {
    add(IrcMessage(
      prefix: nickname,
      command: 'JOIN',
      parameters: [dirChannel],
    ));
    addNumeric(IrcRplTopic.withLocalHostname(nickname, dirChannel, dirChannelTopic));
    addNumeric(IrcRplNamReply.withLocalHostname(
      nickname,
      ChannelStatus.public,
      dirChannel,
      [chatBotNick, nickname,],
    ));
    addNumeric(IrcRplEndOfNames.withLocalHostname(nickname, dirChannel));

    if (!authenticated) {
      dirPrivMsgSend('You are not authenticated!');
      dirPrivMsgSend('In order to access TelegIRC Directory, you must authenticate.');
      dirPrivMsgSend('Join \u0002#a\u0002 to proceed.');
      dirPart();
      return;
    }

    final welcomeMessages = [
      'Welcome to TelegIRC Directory!',
      '',
      'Use the following commands to view the channels you can join:',
      '  - \u0002chats main [<query>]\u0002 == list chats in your main chat list, only those matching <query> if provided',
      '  - \u0002chats archive [<query>]\u0002 == list chats in your archived chats, only those matching <query> if provided',

    ];

    welcomeMessages.forEach(dirPrivMsgSend);

    dirJoined = true;
  }

  void dirPart() {
    add(IrcMessage(
      prefix: nickname,
      command: 'PART',
      parameters: [dirChannel],
    ));
    dirJoined = false;
  }

  Future dirPrivMsg(String message) async {
    if (!authenticated) {
      dirPrivMsgSend('You are not authenticated!');
      dirPrivMsgSend('In order to access TelegIRC Directory, you must authenticate.');
      dirPrivMsgSend('Join \u0002#a\u0002 to proceed.');
      return;
    }
    message = message.trim().toLowerCase();
    if (message.startsWith('chats ')) {
      final kinds = {
        'main': td_o.ChatListMain(),
        'archive': td_o.ChatListArchive(),
      };
      final tmp = message.substring(6).splitLimit(' ', 2);
      final kind = tmp[0];
      message = tmp.length > 1 ? tmp[1] : '';

      if (!kinds.containsKey(kind)) {
        dirPrivMsgSend('Unknown chat list kind: $kind');
        return;
      }
      final tdKind = kinds[kind]!;
      dirPrivMsgSend('== Chat Listing [$kind] ==');

      final chatIds = await tdSend<td_o.Chats>(td_fn.GetChats(
        chatList: tdKind,
        limit: 1000,
      ));
      final chats = await Future.wait(chatIds.chatIds.map((id) => tdSend<td_o.Chat>(td_fn.GetChat(chatId: id))));
      for (final chat in chats) {
        if (this.chats.where((c) => c.id == chat.id).isEmpty) {
          this.chats.add(chat);
        }

        final channel = await getChannel(chat);

        bool doesMatch() {
          if (message.isEmpty) {
            return true;
          }
          if (channel.channel.toLowerCase().contains(message.toLowerCase())) {
            return true;
          }
          if (channel.topic.toLowerCase().contains(message.toLowerCase())) {
            return true;
          }

          return false;
        }

        if (doesMatch()) {
          dirPrivMsgSend('${channel.channel} - ${channel.topic}');
        }
      }

      dirPrivMsgSend('== Listing End ==');
    }
    else {
      dirPrivMsgSend('Unknown message: $message');
    }
  }

  @override
  Future<bool> handleIrcMessage(IrcMessage message) async {
    if (!away) {
      await markAsRead();
    }

    if (message.command == 'JOIN') {
      if (message.parameters[0] == dirChannel) {
        if (!dirJoined) {
          dirJoin();
        }
      }
      else {
        final channelName = message.parameters[0].startsWith('#')
            ? message.parameters[0].substring(1)
            : message.parameters[0];
        final chatId = findChatId(channelName);
        if (chatId == null) {
          return false;
        }

        await joinChat(chatId, channelName);
      }

      return true;
    }
    else if (message.command == 'PART') {
      if (message.parameters[0] == dirChannel) {
        if (dirJoined) {
          dirPart();
        }
      }
      else {
        final channelName = message.parameters[0].startsWith('#')
            ? message.parameters[0].substring(1)
            : message.parameters[0];
        final chatId = findChatId(channelName);
        if (!joinedChats.contains(chatId)) {
          return false;
        }

        joinedChats.remove(chatId);
        add(IrcMessage(
          prefix: nickname,
          command: 'PART',
          parameters: ['#$channelName'],
        ));
        await tdSend(td_fn.CloseChat(chatId: chatId!));
      }

      return true;
    }
    else if (message.command == 'PRIVMSG') {
      if (message.parameters[0] == dirChannel) {
        await dirPrivMsg(message.parameters[1].trim());
      }
      else {
        final channelName = message.parameters[0];

        final chatId = findChatId(channelName);
        if (chatId == null) {
          return false;
        }

        if (!authenticated) {
          void send(String message) {
            add(IrcMessage(
              prefix: chatBotNick,
              command: 'PRIVMSG',
              parameters: [channelName, message],
            ));
          }

          send('You are not authenticated!');
          send('In order to send messages, you must authenticate.');
          send('Join \u0002#a\u0002 to proceed.');
          send('After that, send ![recall] to see what messages you received while unauthenticated.');
          return true;
        }

        var msg = message.parameters[1];
        while (true) {
          if (msg.startsWith('!!')) {
            msg = msg.substring(1);
          }
          else if (msg.startsWith('![')) {
            final endIdx = msg.indexOf(']');
            if (endIdx == -1) {
              break;
            }
            final chatBotCmd = msg.substring(2, endIdx);
            msg = msg.substring(endIdx + 1);

            await handleChatBotCmd(channelName, chatBotCmd);
            continue;
          }
          break;
        }

        msg = msg.trim();
        if (msg.isNotEmpty) {
          await sendMessage(chatId, msg);
        }
      }

      return true;
    }
    return false;
  }

  @override
  Future<void> handleTdMessage(TdBase message) async {
    if (!authenticated) {
      return;
    }
    if (message is td_o.UpdateNewMessage) {
      if (joinedChats.contains(message.message!.chatId)) {
        final channel = await getChannel(chats.where((e) => e.id == message.message!.chatId).first);
        await tdMsgToIrc(channel.channel, message.message!);
      }
    }
    else if (message is td_o.UpdateUserStatus) {
      final user = await getUser(userId: message.userId);
      add(IrcMessage(
        prefix: user.nickname,
        command: 'AWAY',
        parameters: [
          if (user.away) 'User is offline on Telegram',
        ],
      ));
    }
  }

  Future<ChannelListing> getChannel(td_o.Chat chat) async {
    var clientCount = 0;
    var topic = '';
    var channelName = chat.id.toString();
    await chat.type!.match(
      isChatTypePrivate: (p) async {
        clientCount = 2;
        final user = (await tdSend(td_fn.GetUser(userId: p.userId))) as td_o.User;
        user.type?.match(
          isUserTypeBot: (b) {
            topic = 'Bot: ${chat.title}';
          },
          isUserTypeDeleted: (d) {
            topic = 'Deleted User';
          },
          isUserTypeRegular: (r) {
            topic = 'Chat: ${chat.title}';
          },
          otherwise: (_) {
            topic = 'Unknown User';
          },
        );
        if (user.username.isNotEmpty) {
          channelName = '@${user.username}';
          usernameCache[user.username.toLowerCase()] = chat.id;
        }
      },
      isChatTypeBasicGroup: (g) async {
        final group = await tdSend<td_o.BasicGroup>(td_fn.GetBasicGroup(basicGroupId: g.basicGroupId));
        clientCount = group.memberCount;
        topic = 'Group: ${chat.title}';
      },
      isChatTypeSupergroup: (g) async {
        final group = await tdSend<td_o.Supergroup>(td_fn.GetSupergroup(supergroupId: g.supergroupId));
        clientCount = group.memberCount;
        topic = 'Supergroup: ${chat.title}';
        if (group.username.isNotEmpty) {
          topic += ' (@${group.username})';
          channelName = '@${group.username}';
          usernameCache[group.username.toLowerCase()] = chat.id;
        }
      },
      otherwise: (_) async {},
    );
    if (clientCount > 0 && !joinedChats.contains(chat.id)) {
      clientCount -= 1;
    }
    return ChannelListing(
      channel: '#$channelName', 
      clientCount: clientCount, 
      topic: topic,
    );
  }

  @override
  Future<List<ChannelListing>> get channels => Future.wait([
    Future.value(ChannelListing(
      channel: dirChannel, 
      clientCount: dirJoined ? 2 : 1, 
      topic: dirChannelTopic,
    )),
    ...chats.map(getChannel),
  ]);

  Future<UserListing> getUser({required int userId, String? channel}) async {
    final user = await tdSend<td_o.User>(td_fn.GetUser(userId: userId));
    final me = await tdSend<td_o.User>(td_fn.GetMe());
    final nickname = me.id == user.id ? this.nickname : user.username.isNotEmpty ? user.username : user.id.toString();
    final away = user.status?.match(
      isUserStatusEmpty: (_) => false,
      isUserStatusLastMonth: (_) => true,
      isUserStatusLastWeek: (_) => true,
      isUserStatusOffline: (_) => true,
      isUserStatusOnline: (_) => false,
      isUserStatusRecently: (_) => true,
      otherwise: (_) => false,
    );
    return UserListing(
      channel: channel, 
      username: user.username.isNotEmpty ? user.username : user.id.toString(),
      nickname: nickname, 
      away: away ?? false, 
      op: false, 
      chanOp: false, 
      voice: false, 
      realname: '${user.firstName} ${user.lastName}',
    );
  }

  @override
  Future<List<UserListing>> getUsers([String? channel]) async {
    if (channel == null) {
      return [];
    }
    else {
      final chatId = findChatId(channel);
      if (chatId == null) {
        return [];
      }
      final chat = chats.where((c) => c.id == chatId).first;

      final otherUsers = <UserListing>[];
      await chat.type!.match(
        isChatTypePrivate: (p) async {
          otherUsers.add(await getUser(userId: p.userId, channel: channel,));
        },
        isChatTypeBasicGroup: (g) async {
          final group = await tdSend<td_o.BasicGroupFullInfo>(td_fn.GetBasicGroupFullInfo(basicGroupId: g.basicGroupId));
          final users = await Future.wait(group.members.map((m) => m!.memberId!.match(
            isMessageSenderUser: (u) {
              return u.userId;
            },
            otherwise: (_) => null,
          )).whereType<int>().map((uid) => getUser(userId: uid, channel: channel,)));
          otherUsers.addAll(users);
        },
        isChatTypeSupergroup: (g) async {
          final group = (await tdSend(td_fn.GetSupergroupFullInfo(supergroupId: g.supergroupId))) as td_o.SupergroupFullInfo;
          if (group.canGetMembers) {
            final members = <td_o.ChatMember>[];
            while (true) {
              final mbrs = await tdSend<td_o.ChatMembers>(td_fn.GetSupergroupMembers(
                supergroupId: g.supergroupId,
                filter: null,
                offset: members.length,
                limit: 200,
              ));
              if (mbrs.members.isEmpty) {
                break;
              }
              members.addAll(mbrs.members.map((m) => m!));
            }

            final users = await Future.wait(members.map((m) => m.memberId!.match(
              isMessageSenderUser: (u) {
                return u.userId;
              },
              otherwise: (_) => null,
            )).whereType<int>().map((uid) => getUser(userId: uid, channel: channel,)));
            otherUsers.addAll(users);
          }
        },
        otherwise: (_) async {},
      );

      return [
        if (joinedChats.contains(chatId)) ...[
          UserListing(
            channel: channel,
            username: chatBotNick,
            nickname: chatBotNick,
            away: false,
            op: true,
            chanOp: true,
            voice: true,
            realname: chatBotNick,
          ),
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
        ],
        ...otherUsers.where((u) => u.nickname != nickname),
      ];
    }
  }
}
