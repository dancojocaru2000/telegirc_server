class Globals {
  late DateTime startTime;
  int unsecurePort;
  int securePort;
  int loginPort;
  int apiId;
  String apiHash;
  String? dbDir;
  String? get dbPath => dbDir != null ? '$dbDir/telegirc.sqlite' : null;
  String? tdlibPath(String dbId) => dbDir != null ? '$dbDir/tdlib/$dbId' : null;
  String version = '0.0.1';
  bool useTestConnection;

  Globals._() : unsecurePort = 0, securePort = 0, loginPort = 0, apiId = 0, apiHash = '', dbDir = '', useTestConnection = false {
    startTime = DateTime.now();
  }

  static final Globals _instance = Globals._();
  static Globals get instance => _instance;

  static String applicationVersion = '0.0.1';
}