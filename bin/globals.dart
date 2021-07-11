class Globals {
  late DateTime startTime;
  int unsecurePort;
  int securePort;
  int loginPort;
  int apiId;
  String apiHash;
  String dbPath;
  String version = '0.0.1';

  Globals._() : unsecurePort = 0, securePort = 0, loginPort = 0, apiId = 0, apiHash = '', dbPath = '' {
    startTime = DateTime.now();
  }

  static final Globals _instance = Globals._();
  static Globals get instance => _instance;
}