import 'dart:io';

import 'database.dart';
import 'globals.dart';
import 'irc_socket.dart';
import 'logging.dart';
import 'tdlib.dart';
import 'telegirc_irc.dart';

import 'package:tdlib_types/fn.dart' as td_fn;
import 'package:tdlib_types/obj.dart' as td_o;

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
  try {
    Globals.instance.apiId = int.parse(ensureEnv('TDLIB_API_ID'));
    Globals.instance.apiHash = ensureEnv('TDLIB_API_HASH');
    lInfo(function: 'main', message: 'Obtained TDLIB env');
    Globals.instance.dbDir = Platform.environment['DB_PATH'] ?? '.';
    if (Globals.instance.dbDir?.trim().isEmpty == true) {
      Globals.instance.dbDir = null;
    }
    lDebug(function: 'main', message: 'Db dir: ${Globals.instance.dbDir}');
    lDebug(function: 'main', message: 'Db path: ${Globals.instance.dbPath}');
    Database.initialize(Globals.instance.dbPath);
    lInfo(function: 'main', message: 'Initialized database');
  }
  catch (ex) {
    lError(function: 'main', message: ex.toString());
    rethrow;
  }

  Globals.instance.unsecurePort = int.tryParse(Platform.environment['IRC_UNSAFE_PORT'] ?? '') ?? 6667;
  lDebug(function: 'main', message: 'IRC unsecurePort: ${Globals.instance.unsecurePort}');
  Globals.instance.securePort = int.tryParse(Platform.environment['IRC_SAFE_PORT'] ?? '') ?? 6697;
  lDebug(function: 'main', message: 'IRC securePort: ${Globals.instance.securePort}');
  Globals.instance.loginPort = int.tryParse(Platform.environment['LOGIN_PORT'] ?? '') ?? 0;
  lDebug(function: 'main', message: 'IRC loginPort: ${Globals.instance.loginPort}');

  await TdClient.execute(td_fn.SetLogStream(logStream: td_o.LogStreamEmpty()));

  final unsecureIrcServer = await ServerSocket.bind(
    InternetAddress.anyIPv6, 
    Globals.instance.unsecurePort,
    shared: true,
  );
  Globals.instance.unsecurePort = unsecureIrcServer.port;
  lInfo(function: 'main', message: 'Unsecure server started on port ${Globals.instance.unsecurePort}');
  final securityContext = SecurityContext.defaultContext;
  securityContext.usePrivateKey(Platform.environment['SSL_PK'] ?? './ssl/key.pem');
  securityContext.useCertificateChain(Platform.environment['SSL_CERTIFICATE'] ?? './ssl/certificate.pem');
  final secureIrcServer = await SecureServerSocket.bind(
    InternetAddress.anyIPv6, 
    Globals.instance.securePort, 
    securityContext,
    shared: true,
  );
  Globals.instance.securePort = secureIrcServer.port;
  lInfo(function: 'main', message: 'Secure server started on port ${Globals.instance.securePort}');

  unsecureIrcServer.map((socket) => IrcSocketWrapper(socket)).listen(onIrcConnection);
  secureIrcServer.map((socket) => IrcSocketWrapper(socket, secure: true,)).listen(onIrcConnection);
}

void onIrcConnection(IrcSocketWrapper socket) {
  final manager = SocketManager(
    socket,
    onDisconnect: (mgr) {
      socket.close();
      managers.remove(mgr);
    },
  );
  managers.add(manager);
}