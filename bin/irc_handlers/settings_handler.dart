import 'package:tdlib_types/base.dart';
import 'package:tdlib_types/fn.dart';

import '../extensions.dart';
import '../irc.dart';
import '../irc_replies.dart';
import '../settings_wrapper.dart';
import '../telegirc_irc.dart';

class SettingsHandler extends ServerHandler {
  static const String settingsBotNick = 'telegirc-settings-bot';
  static const String settingsChannel = '#telegirc-settings';
  static const String settingsChannelTopic = 'Change TelegIRC settings';

  final SettingsWrapper settings;

  final bool Function() _isAuth;

  bool get authenticated => _isAuth();

  bool flagJoined = false;

  SettingsHandler({
    required this.settings,
    required void Function(IrcMessage) add,
    required void Function(IrcNumericReply) addNumeric,
    required Future<T> Function<T extends TdBase>(TdFunction) tdSend,
    required String Function() nickname,
    void Function(ServerHandler)? onUnregisterRequest,
    required bool Function() isAuthenticated,
  }) : _isAuth = isAuthenticated, super(
    add: add,
    addNumeric: addNumeric,
    nickname: nickname,
    tdSend: tdSend,
    onUnregisterRequest: onUnregisterRequest,
  );

  void pm(String message) {
    add(IrcMessage(
      prefix: settingsBotNick,
      command: 'PRIVMSG',
      parameters: [settingsChannel, message],
    ));
  }

  String formatSetting(dynamic value) {
    if (value is bool) {
      return value ? 'YES' : 'NO';
    }
    else {
      return value.toString();
    }
  }

  dynamic parseSetting(Setting setting, String value) {
    if (settingTypes[setting] == bool) {
      final nv = value.toLowerCase();
      if (nv == 'f' || nv == 'false' || nv == 'n' || nv == 'no') {
        return false;
      }
      else if (nv == 't' || nv == 'true' || nv == 'y' || nv == 'yes') {
        return true;
      }
      else {
        throw FormatException('Unable to parse bool value');
      }
    }
    else if (settingTypes[setting] == int) {
      return int.parse(value);
    }
    else if (settingTypes[setting] == double) {
      return double.parse(value);
    }
    else {
      return value;
    }
  }

  Future<void> handleJoin() async {
    if (flagJoined) return;
    flagJoined = true;

    add(IrcMessage(
      prefix: nickname,
      command: 'JOIN',
      parameters: [settingsChannel],
    ));
    addNumeric(IrcRplTopic.withLocalHostname(nickname, settingsChannel, settingsChannelTopic));
    addNumeric(IrcRplNamReply.withLocalHostname(nickname, ChannelStatus.public, settingsChannel, [nickname, settingsBotNick]));
    addNumeric(IrcRplEndOfNames.withLocalHostname(nickname, settingsChannel));
    pm('Welcome to \u0002$settingsChannel\u0002.');
    pm('');
    pm('Use the following commands to modify your settings:');
    pm('  - \u0002SET <settingName> <settingValue>\u0002 == set <settingName> to <settingValue>');
    pm('  - \u0002GET <settingName>\u0002 == get the current value of <settingName>');
    pm('  - \u0002RESET <settingName>\u0002 == set the value of <settingName> to the default');
    pm('');
    if (authenticated) {
      pm('Here are your current settings and their values:');
      for (final setting in Setting.values) {
        final value = settings.getSettingTyped(setting, !settingDefaults.containsKey(setting));
        pm('  ${setting.name}[${formatSetting(value)}] - ${settingDescriptions[setting]}');
      }
    }
    else {
      pm('You can only see or change settings if you are authenticated. Please join #a.');
    }
  }

  Future<void> handleMessage(String message) async {
    final tokens = message.splitLimit(' ', 2);
    final params = tokens[1];
    switch (tokens[0].toLowerCase()) {
      case 'get': {
        final paramName = params;
        try {
          final setting = Setting.values.singleWhere((element) => element.name == paramName);
          final value = settings.getSettingTyped(setting, !settingDefaults.containsKey(setting));
          pm('${setting.name}[${formatSetting(value)}]');
        } on StateError {
          pm('GET: Unknown setting name $paramName');
        }
      }
      break;
      case 'set': {
        final tokens = params.splitLimit(' ', 2);
        final paramName = tokens[0];
        try {
          final setting = Setting.values.singleWhere((element) => element.name == paramName);
          settings.setSetting(setting, parseSetting(setting, tokens[1]));
          final newValue = settings.getSettingTyped(setting, !settingDefaults.containsKey(setting));
          pm('SET: Setting $paramName set to ${formatSetting(newValue)}');
        } on StateError {
          pm('SET: Unknown setting name $paramName');
        }
      }
      break;
      case 'reset': {
        final paramName = params;
        try {
          final setting = Setting.values.singleWhere((element) => element.name == paramName);
          settings.setSetting(setting, settingDefaults[setting]);
          pm('RESET: Setting $paramName reset to default');
        } on StateError {
          pm('RESET: Unknown setting name $paramName');
        }
      }
      break;
      default: {
        pm('Unknown command: \u0002${tokens[0]}\u0002');
      }
    }
  }

  @override
  Future<bool> handleIrcMessage(IrcMessage message) async {
    if (message.command == 'JOIN' && message.parameters[0] == settingsChannel) {
      await handleJoin();
      return true;
    }
    else if (message.command == 'PART' && message.parameters[0] == settingsChannel) {
      if (flagJoined) {
        flagJoined = false;
        add(IrcMessage(
          prefix: nickname,
          command: 'PART',
          parameters: [settingsChannel],
        ));
      }
      return true;
    }
    else if (message.command == 'PRIVMSG' && message.parameters[0] == settingsChannel) {
      await handleMessage(message.parameters[1]);
      return true;
    }
    else {
      return false;
    }
  }

  @override
  Future<void> handleTdMessage(TdBase message) async {
    return;
  }

  @override
  Future<List<ChannelListing>> get channels async => [
    ChannelListing(
      channel: settingsChannel,
      clientCount: flagJoined ? 2 : 1,
      topic: settingsChannelTopic,
    ),
  ];

  @override
  Future<List<UserListing>> getUsers([String? channel]) async {
    if (channel == null && !flagJoined) {
      return [
        UserListing(
          channel: null,
          username: settingsBotNick,
          nickname: settingsBotNick,
          away: false,
          op: true,
          chanOp: false,
          voice: false,
          realname: settingsBotNick,
        ),
      ];
    }
    else if (channel == settingsChannel) {
      return [
        UserListing(
          channel: channel,
          username: settingsBotNick,
          nickname: settingsBotNick,
          away: false,
          op: true,
          chanOp: false,
          voice: false,
          realname: settingsBotNick,
        ),
        if (flagJoined)
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