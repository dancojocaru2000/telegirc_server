import 'dart:async';
import 'dart:convert' show utf8;
import 'dart:io';
import 'dart:typed_data';

import 'irc.dart';

extension SocketIrcMessage on Socket {
  void addIrcMessage(IrcMessage message) {
    final socketMessage = '${message.ircFormat}\r\n';
    add(utf8.encode(socketMessage));
  }
}

class IrcSocketWrapper {
  final StreamController<IrcMessage> _controller;
  Stream<IrcMessage> get stream => _controller.stream;

  final Socket innerSocket;
  final bool secure;

  String _buffer;

  late final StreamSubscription _innerSocketSubscription;

  IrcSocketWrapper(Socket wrappedSocket, {this.secure = false,})
    : innerSocket = wrappedSocket,
      _controller = StreamController(),
      _buffer = '' {
    _innerSocketSubscription = innerSocket.listen(
      _onSocketMessageReceived,
      onError: (error, st) => _controller.addError(error, st),
      onDone: () => _controller.close(),
    );
    innerSocket.done.onError((error, stackTrace) {
      if (error == null) {
        return;
      }
      if (!_controller.isClosed) {
        _controller.addError(error, stackTrace);
        _controller.close();
      }
    });
  }

  void _onSocketMessageReceived(Uint8List data) {
    var encodedData = utf8.decode(data);
    while (encodedData.contains('\r\n')) {
      final crlfPosition = encodedData.indexOf('\r\n');
      final firstChunk = encodedData.substring(0, crlfPosition);
      encodedData = encodedData.substring(crlfPosition + 2);

      _buffer += firstChunk;
      try {
        final message = IrcMessage.parse(_buffer);
        _controller.add(message);
      }
      catch (e, st) {
        _controller.addError(e, st);
      }
      _buffer = '';
    }
    _buffer += encodedData;
  }

  void add(IrcMessage message) {
    innerSocket.addIrcMessage(message);
  }

  Future<dynamic> close() async {
    await _innerSocketSubscription.cancel();
    await _controller.close();
    return await _controller.close();
  }
}
