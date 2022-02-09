import 'database.dart';

enum Setting {
  recallOnJoin,
  recallLength,
}

const Map<Setting, String> settingDescriptions = {
  Setting.recallLength: 'The number of messages to return on recall when no explicit number is provided',
  Setting.recallOnJoin: 'Whether TelegIRC should recall the messages when joining a channel',
};

const Map<Setting, dynamic> settingDefaults = {
  Setting.recallLength: 50,
  Setting.recallOnJoin: true,
};

const Map<Setting, Type> settingTypes = {
  Setting.recallLength: int,
  Setting.recallOnJoin: bool,
};

class SettingsWrapper {
  final UserEntry Function() _getUser;
  final void Function(UserEntry)? onDbChange;

  UserEntry get user => _getUser();

  const SettingsWrapper({required UserEntry Function() user, this.onDbChange}) : _getUser = user;

  T getSetting<T>(Setting setting) {
    return getSettingTyped(setting, null is T);
  }

  dynamic getSettingTyped(Setting setting, bool nullable) {
    final result = user.settings[setting.name];
    if (result != null) {
      return result;
    }
    else if (nullable) {
      return result;
    }
    else if (settingDefaults.containsKey(setting)) {
      return settingDefaults[setting];
    }
    else {
      throw TypeError();
    }
  }

  void setSetting<T>(Setting setting, T newValue) {
    user.settings[setting.name] = newValue;
    if (onDbChange != null) onDbChange!(user);
  }

  bool get recallOnJoin => getSetting<bool>(Setting.recallOnJoin);
  set recallOnJoin(bool newValue) => setSetting(Setting.recallOnJoin, newValue);
  
  int get recallLength => getSetting<int>(Setting.recallLength);
  set recallLength(int newValue) => setSetting(Setting.recallLength, newValue);
}

extension Settings on UserEntry {
  SettingsWrapper get settings => SettingsWrapper(user: () => this);
}
