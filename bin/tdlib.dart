import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';

import 'package:ffi/ffi.dart';
import 'package:tdlib_types/base.dart' show TdBase;
import 'package:tdlib_types/abstract.dart' as a show OptionValue;
import 'package:tdlib_types/obj.dart' as o show Error, UpdateOption, OptionValueEmpty, AuthorizationStateClosed;
import 'package:tdlib_types/fn.dart' show Close, LogOut, TdFunction, TestCallEmpty;

import 'logging.dart';

class TdClient {
  // static late SendPort _sendPort;
  static int _requestId = 0;
  static bool _initialized = false;
  static final Map<int, void Function(TdBase)> _updateReceivers = {};
  static final Map<int, Completer> _completers = {};
  static DynamicLibrary? dylib;
  static void _isolate(SendPort isolateToMain) async {
    final libraryPath = Platform.environment['TDLIB_LIB_PATH'];
    if (libraryPath == null) {
      throw Exception('No TDLIB_LIB_PATH environment variable given');
    }
    
    final dylib = DynamicLibrary.open(libraryPath);
    // final tdCreateClientId = dylib.lookupFunction<
    //   IntPtr Function(), 
    //   int Function()
    // >('td_create_client_id');
    // final tdSend = dylib.lookupFunction<
    //   Void Function(IntPtr, Pointer<Utf8>),
    //   void Function(int, Pointer<Utf8>)
    // >('td_send');
    final tdReceive = dylib.lookupFunction<
      Pointer<Utf8> Function(Double),
      Pointer<Utf8> Function(double)
    >('td_receive');
    // final tdExecute = dylib.lookupFunction<
    //   Pointer<Utf8> Function(Pointer<Utf8>),
    //   Pointer<Utf8> Function(Pointer<Utf8>)
    // >('td_execute');

    final mainToIsolateRecv = ReceivePort('mainToIsolate');
    isolateToMain.send(mainToIsolateRecv.sendPort);

    // mainToIsolateRecv.listen((isolateMessage) async {
    //   final requestId = isolateMessage[0] as int;
    //   final message = isolateMessage[1];
    //   final messageKind = message[0] as _TdIsolateRequestKind;
    //   final data = (message as List).skip(1).toList(growable: false);

    //   switch(messageKind) {
    //     case _TdIsolateRequestKind.init:
    //       final clientId = tdCreateClientId();
    //       isolateToMain.send([requestId, clientId]);
    //       break;
    //     case _TdIsolateRequestKind.send:
    //       final clientId = data[0] as int;
    //       final request = data[1] as Map<String, dynamic>;
    //       request['@extra'] = requestId.toString();
    //       final requestRaw = jsonEncode(request);
    //       final requestRawNative = requestRaw.toNativeUtf8();
    //       tdSend(clientId, requestRawNative);
    //       malloc.free(requestRawNative);
    //       break;
    //     case _TdIsolateRequestKind.execute:
    //       final request = data[0] as Map<String, dynamic>;
    //       final requestRaw = jsonEncode(request);
    //       final requestRawNative = requestRaw.toNativeUtf8();
    //       final resultRawNative = tdExecute(requestRawNative);
    //       malloc.free(requestRawNative);
    //       final resultRaw = resultRawNative.toDartString();
    //       final result = jsonDecode(resultRaw) as Map<String, dynamic>;
    //       isolateToMain.send([requestId, result]);
    //       break;
    //   }

    // });

    final messagesToDispatch = <dynamic>[];
    var lastDispatch = DateTime(2000);
    void dispatch() {
      if (messagesToDispatch.isNotEmpty) {
        isolateToMain.send(messagesToDispatch);
        messagesToDispatch.clear();
      }
      lastDispatch = DateTime.now();
    }

    while (true) {
      final resultRawNative = tdReceive(messagesToDispatch.isEmpty ? 10 : 0);
      if (resultRawNative.address == 0) {
      //   await Future.delayed(const Duration(milliseconds: 50));
        dispatch();
        continue;
      }
      else if (DateTime.now().difference(lastDispatch).inMilliseconds > 300) {
        dispatch();
      }
      // else {
      //   await Future.delayed(Duration.zero);
      // }
      final resultRaw = resultRawNative.toDartString();
      final result = jsonDecode(resultRaw) as Map<String, dynamic>;
      result['@epoch'] = DateTime.now().millisecondsSinceEpoch;
      if (result.containsKey('@extra')) {
        messagesToDispatch.add([int.parse(result['@extra'] as String), result]);
        // isolateToMain.send([int.parse(result['@extra'] as String), result]);
      }
      else {
        messagesToDispatch.add([null, result]);
        // isolateToMain.send([null, result]);
      }
    }
  }
  static Future _initIsolate() async {
    if (_initialized) {
      return;
    }
    _initialized = true;

    if (dylib == null) {
      final libraryPath = Platform.environment['TDLIB_LIB_PATH'];
      if (libraryPath == null) {
        throw Exception('No TDLIB_LIB_PATH environment variable given');
      }

      dylib = DynamicLibrary.open(libraryPath);
    }

    final completer = Completer();
    final isolateToMainRecv = ReceivePort('isolateToMain');

    isolateToMainRecv.listen((message) {
      if (message is SendPort) {
        // _sendPort = message;
        completer.complete();
      }
      else {
        for (final msg in message) {
          final requestId = msg[0] as int?;
          final data = msg[1];
          final epoch = data['@epoch'];
          final diff = DateTime.now().millisecondsSinceEpoch - epoch;
          if (diff > 1000) {
            lCritical(function: 'TdClient::_initIsolate->isolateToMainRecv', message: 'Processing ${data["@type"]} took $diff ms');
          }
          if (requestId != null) {
            final completer = _completers.remove(requestId);
            completer?.complete(data);
          }
          else {
            final clientId = data['@client_id'];
            if (_updateReceivers.containsKey(clientId)) {
              _updateReceivers[clientId]!(TdBase.fromJson(data)!);
            }
          }
        }
      }
    });

    await Isolate.spawn(_isolate, isolateToMainRecv.sendPort);
    await completer.future;
  }
  // static Future<Res> _makeIsolateRequest<Req, Res>(Req request) {
  //   final requestId = _requestId;
  //   _requestId++;

  //   final completer = Completer<Res>();
  //   _completers[requestId] = completer;

  //   _sendPort.send([requestId, request]);

  //   return completer.future;
  // }

  final int _clientId;

  final StreamController<TdBase> _updateStreamController;
  Stream<TdBase> get updateStream => _updateStreamController.stream;

  final Map<String, a.OptionValue> _options;
  UnmodifiableMapView<String, a.OptionValue> get options => UnmodifiableMapView(_options);

  TdClient._(this._clientId)
      : _updateStreamController = StreamController(),
        _options = {} {
    _updateReceivers[_clientId] = (update) {
      if (update is o.Error) {
        _updateStreamController.addError(update);
      } else {
        if (update is o.UpdateOption) {
          if (update.value is o.OptionValueEmpty) {
            _options.remove(update.name);
          } else {
            _options[update.name] = update.value!;
          }
        }
        _updateStreamController.add(update);
        if (update is o.AuthorizationStateClosed) {
          _updateStreamController.close();
        }
      }
    };
  }

  Future<Map<String, dynamic>> sendRaw(Map<String, dynamic> request) {
    // return _makeIsolateRequest([_TdIsolateRequestKind.send, _clientId, request]);

    final tdSend = dylib!.lookupFunction<
      Void Function(IntPtr, Pointer<Utf8>),
      void Function(int, Pointer<Utf8>)
    >('td_send');

    final clientId = _clientId;
    final requestId = _requestId;
    _requestId++;

    request['@extra'] = requestId.toString();

    final completer = Completer<Map<String, dynamic>>();
    _completers[requestId] = completer;

    final requestRaw = jsonEncode(request);
    final requestRawNative = requestRaw.toNativeUtf8();
    tdSend(clientId, requestRawNative);
    malloc.free(requestRawNative);

    return completer.future;
  }

  Future<TdBase> send(TdFunction fn) async {
    final result = TdBase.fromJson(await sendRaw(fn.toJson()))!;
    if (result is o.Error) {
      throw result;
    }
    return result;
  }

  static Future<TdClient> newClient() async {
    await _initIsolate();

    final tdCreateClientId = dylib!.lookupFunction<
      IntPtr Function(), 
      int Function()
    >('td_create_client_id');

    // final clientId = await _makeIsolateRequest<List, int>([_TdIsolateRequestKind.init]);
    final clientId = tdCreateClientId();
    final client = TdClient._(clientId);
    await client.send(TestCallEmpty());
    return client;
  }

  static Future<Map<String, dynamic>> executeRaw(Map<String, dynamic> request) async {
    await _initIsolate();
    // return await _makeIsolateRequest([_TdIsolateRequestKind.execute, request]);

    final tdExecute = dylib!.lookupFunction<
      Pointer<Utf8> Function(Pointer<Utf8>),
      Pointer<Utf8> Function(Pointer<Utf8>)
    >('td_execute');
    final requestRaw = jsonEncode(request);
    final requestRawNative = requestRaw.toNativeUtf8();
    final resultRawNative = tdExecute(requestRawNative);
    malloc.free(requestRawNative);
    final resultRaw = resultRawNative.toDartString();
    final result = jsonDecode(resultRaw) as Map<String, dynamic>;
    return result;
  }

  static Future<TdBase> execute(TdFunction fn) async {
    final result = TdBase.fromJson(await executeRaw(fn.toJson()))!;
    if (result is o.Error) {
      throw result;
    }
    return result;
  } 

  Future<void> close() => send(Close());
  Future<void> logout() => send(LogOut());

  @override
  String toString() {
    return 'TdClient($_clientId)';
  }
}

// enum _TdIsolateRequestKind {
//   init,
//   send,
//   execute,
// }