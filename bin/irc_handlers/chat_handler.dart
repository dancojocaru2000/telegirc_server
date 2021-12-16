import 'package:tdlib_types/base.dart';
import 'package:tdlib_types/fn.dart' show TdFunction;
import 'package:tdlib_types/fn.dart' as td_fn;
import 'package:tdlib_types/obj.dart' as td_o;

import '../irc.dart';
import '../irc_replies.dart';
import '../logging.dart';
import '../telegirc_irc.dart';

class ChatHandler extends ServerHandler {
  static const String chatBotNick = 'telegirc-chat-bot';

  List<td_o.Chat> chats = [];
  List<int> joinedChats = [];
  Map<String, int> usernameCache = {};

  bool flagNextSilent = false;
  bool flagNoWebpagePreview = false;
  int? flagReplyTo;

  ChatHandler({
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
        ) {
          refreshChats().then((_) { channels; });
        }

  Future refreshChats() async {
    final chatIds = await tdSend(td_fn.GetChats(chatList: null,limit: 100)) as td_o.Chats;
    chats = (await Future.wait(chatIds.chatIds.map((chatId) async => (await tdSend(td_fn.GetChat(chatId: chatId))) as td_o.Chat))).toList();
  }

  int? findChatId(String channelName) {
    if (channelName.startsWith('#')) {
      channelName = channelName.substring(1);
    }
    if (channelName.startsWith('@')) {
      channelName = channelName.substring(1);
    }
    if (usernameCache.containsKey(channelName)) {
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
    addNumeric(IrcRplEndOfNames.withLocalHostname(nickname, '#$channelName'));
    await handleChatBotCmd('#$channelName', 'recall');
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
        final length = (params.length > 1 ? (int.tryParse(params[1])) ?? 50 : 50).clamp(1, 250);
        final messages = <td_o.Message>[];
        while (messages.length < length) {
          final msg = (await tdSend(td_fn.GetChatHistory(
            chatId: chatId,
            fromMessageId: messages.isEmpty ? 0 : messages.last.id,
            limit: length.clamp(1, 100),
            offset: 0,
            onlyLocal: false,
          ))) as td_o.Messages;
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
        await Future.wait(messages.reversed.map((message) => tdMsgToIrc(channel, message)));
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
    ircMsg += '[id: ${msg.id}] ';

    td_o.FormattedText? fmtTxt;
    msg.content!.match(
      isMessageAnimatedEmoji: (ae) {
        ircMsg += ae.emoji;
      },
      isMessageAnimation: (a) {
        if (a.isSecret) {
          ircMsg += '[Secret] ';
        }
        ircMsg += '[Animation] ';
        fmtTxt = a.caption;
      },
      isMessageAudio: (a) {
        ircMsg += '[Audio] ';
        fmtTxt = a.caption;
      },
      isMessageDice: (d) {
        ircMsg += '[Dice] ${d.value}';
      },
      isMessageExpiredPhoto: (e) {
        ircMsg += '[Expired Photo]';
      },
      isMessageExpiredVideo: (e) {
        ircMsg += '[Expired Video]';
      },
      isMessagePhoto: (p) {
        if (p.isSecret) {
          ircMsg += '[Secret] ';
        }
        ircMsg += '[Photo] ';
        fmtTxt = p.caption;
      },
      isMessageSticker: (s) {
        ircMsg += '[Sticker] ${s.sticker!.emoji}';
      },
      isMessageText: (t) {
        fmtTxt = t.text;
      },
      isMessageVideo: (v) {
        if (v.isSecret) {
          ircMsg += '[Secret] ';
        }
        ircMsg += '[Video] ';
        fmtTxt = v.caption;
      },
      otherwise: (_) {
        ircMsg += '[Unable to process]';
      }
    );

    if (fmtTxt != null) {
      var s = fmtTxt!.text;
      for (final entity in fmtTxt!.entities) {
        if (entity == null) {
          continue;
        }
        entity.type!.match(
          isTextEntityTypeBold: (b) {
            
          },
          otherwise: (_) {},
        );
      }
      ircMsg += s;
    }

    for (final msg in ircMsg.split(RegExp(r'\r?\n'))) {
      add(IrcMessage(
        prefix: sender,
        command: 'PRIVMSG',
        parameters: [channel, msg],
      ));
    }
  }

  @override
  Future<bool> handleIrcMessage(IrcMessage message) async {
    if (message.command == 'JOIN') {
      final channelName = message.parameters[0].startsWith('#')
          ? message.parameters[0].substring(1)
          : message.parameters[0];
      final chatId = findChatId(channelName);
      if (chatId == null) {
        return false;
      }

      await joinChat(chatId, channelName);

      return true;
    }
    else if (message.command == 'PART') {
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

      return true;
    }
    else if (message.command == 'PRIVMSG') {
      final channelName = message.parameters[0];
      final chatId = findChatId(channelName);
      if (chatId == null) {
        return false;
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

      return true;
    }
    return false;
  }

  @override
  Future<void> handleTdMessage(TdBase message) async {
    if (message is td_o.UpdateNewMessage) {
      if (joinedChats.contains(message.message!.chatId)) {
        final channel = await getChannel(chats.where((e) => e.id == message.message!.chatId).first);
        await tdMsgToIrc(channel.channel, message.message!);
      }
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
        topic = 'Chat: ${chat.title}';
        if (user.username.isNotEmpty) {
          topic += ' (@${user.username})';
          channelName = '@${user.username}';
          usernameCache[user.username.toLowerCase()] = chat.id;
        }
      },
      isChatTypeBasicGroup: (g) async {
        final group = (await tdSend(td_fn.GetBasicGroup(basicGroupId: g.basicGroupId))) as td_o.BasicGroup;
        clientCount = group.memberCount;
        topic = 'Group: ${chat.title}';
      },
      isChatTypeSupergroup: (g) async {
        final group = (await tdSend(td_fn.GetSupergroup(supergroupId: g.supergroupId))) as td_o.Supergroup;
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
    ...chats.map(getChannel),
  ]);

  Future<UserListing> getUser({required int userId, String? channel}) async {
    final user = (await tdSend(td_fn.GetUser(userId: userId))) as td_o.User;
    final me = (await tdSend(td_fn.GetMe())) as td_o.User;
    final nickname = me.id == user.id ? this.nickname : user.username.isNotEmpty ? user.username : user.id.toString();
    return UserListing(
      channel: channel, 
      username: user.username.isNotEmpty ? user.username : user.id.toString(),
      nickname: nickname, 
      away: false, 
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
          final group = (await tdSend(td_fn.GetBasicGroupFullInfo(basicGroupId: g.basicGroupId))) as td_o.BasicGroupFullInfo;
          final users = await Future.wait(group.members.map((m) => m!.memberId!.match(
            isMessageSenderUser: (u) {
              return u.userId;
            },
            otherwise: (_) => null,
          )).whereType<int>().map((uid) => getUser(userId: uid, channel: channel,)));
          otherUsers.addAll(users);
        },
        isChatTypeSupergroup: (g) async {
          // final group = (await tdSend(td_fn.GetSupergroupFullInfo(supergroupId: g.supergroupId))) as td_o.SupergroupFullInfo;
          // final users = Stream.fromFutures(group.members.map((m) => m!.memberId!.match(
          //   isMessageSenderUser: (u) {
          //     return u.userId;
          //   },
          //   otherwise: (_) => null,
          // )).whereType<int>().map((uid) async => (tdSend(td_fn.GetUser(userId: uid))) as td_o.User));
          // await for (final user in users) {
          //   if (user.id == myId) {
          //     continue;
          //   }
          //   otherUsers.add(UserListing(
          //     channel: channel, 
          //     username: user.username.isNotEmpty ? user.username : user.id.toString(),
          //     nickname: user.username.isNotEmpty ? user.username : user.id.toString(), 
          //     away: false, 
          //     op: false, 
          //     chanOp: false, 
          //     voice: false, 
          //     realname: '${user.firstName} ${user.lastName}',
          //   ));
          // }
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
        ...otherUsers,
      ];
    }
  }
}


