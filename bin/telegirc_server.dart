import 'dart:io';

import 'database.dart';
import 'globals.dart';
import 'irc_socket.dart';
import 'telegirc_irc.dart';

List<SocketManager> managers = [];

String ensureEnv(String varName, {bool allowEmpty = false, bool allowWhitespace = false}) {
  final result = Platform.environment[varName];
  if (result == null) {
    throw Exception('Env: $varName does not exist');
  }
  else if (!allowEmpty && result.isEmpty) {
    throw Exception('Env: $varName is empty');
  }
  else if (!allowWhitespace && result.trim().isEmpty) {
    throw Exception('Env: $varName contains only whitespace');
  }
  else {
    return result;
  }
}

void main(List<String> arguments) async {
  Globals.instance.apiId = int.parse(ensureEnv('TDLIB_API_ID'));
  Globals.instance.apiHash = ensureEnv('TDLIB_API_HASH');
  Globals.instance.dbPath = Platform.environment['DB_PATH'] ?? './telegirc.sqlite';
  Database.initialize(Globals.instance.dbPath);

  Globals.instance.unsecurePort = int.tryParse(Platform.environment['IRC_UNSAFE_PORT'] ?? '') ?? 6667;
  Globals.instance.securePort = int.tryParse(Platform.environment['IRC_SAFE_PORT'] ?? '') ?? 6697;
  Globals.instance.loginPort = int.tryParse(Platform.environment['LOGIN_PORT'] ?? '') ?? 0;

  final unsecureIrcServer = await ServerSocket.bind(
    InternetAddress.anyIPv6, 
    Globals.instance.unsecurePort,
    shared: true,
  );
  Globals.instance.unsecurePort = unsecureIrcServer.port;
  print('Unsecure server started on port ${Globals.instance.unsecurePort}');
  final secureIrcServer = await SecureServerSocket.bind(
    InternetAddress.anyIPv6, 
    Globals.instance.securePort, 
    SecurityContext.defaultContext,
    shared: true,
  );
  Globals.instance.securePort = secureIrcServer.port;
  print('Secure server started on port ${Globals.instance.securePort}');

  unsecureIrcServer.map((socket) => IrcSocketWrapper(socket)).listen(onIrcConnection);
  secureIrcServer.map((socket) => IrcSocketWrapper(socket, secure: true,)).listen(onIrcConnection);
}

void onIrcConnection(IrcSocketWrapper socket) {
  final manager = SocketManager(socket);
  managers.add(manager);
}