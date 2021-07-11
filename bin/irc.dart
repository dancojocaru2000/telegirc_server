import 'dart:io';

class IrcMessage {
  final String? prefix;
  final String command;
  final String? _customCommandName;
  final List<String> parameters;

  IrcMessage({
    this.prefix,
    required this.command,
    List<String>? parameters,
  }) : parameters = parameters ?? [], _customCommandName = null;
  IrcMessage._({
    this.prefix,
    required this.command,
    List<String>? parameters,
    String? customCommandName,
  }) : parameters = parameters ?? [], _customCommandName = customCommandName;

  factory IrcMessage.numeric(String serverName, int message, {List<String>? parameters, String? messageName}) {
    return IrcMessage._(
      prefix: serverName,
      command: message.toString().padLeft(3, '0'),
      parameters: parameters,
      customCommandName: messageName != null ? '$messageName($message)' : null,
    );
  }

  factory IrcMessage.parse(String message) {
    message = message.trimLeft();
    final charIt = message.runes.iterator;
    charIt.moveNext();

    // Check for prefix
    String? prefix;
    if (charIt.currentAsString == ':') {
      var prefixBuilder = '';
      while(charIt.moveNext() && charIt.currentAsString.trim().isNotEmpty) {
        prefixBuilder += charIt.currentAsString;
      }
      prefix = prefixBuilder;
      while (charIt.moveNext() && charIt.currentAsString.trim().isEmpty) {
        // Skip whitespace
      }
    }

    var command = '';
    while(charIt.currentAsString.trim().isNotEmpty) {
      command += charIt.currentAsString;
      if (!charIt.moveNext()) {
        break;
      }
    }
    var itemsRemaining = false;
    while ((itemsRemaining = charIt.moveNext()) && charIt.currentAsString.trim().isEmpty) {
      // Skip whitespace
    }
    
    // Parse parameters
    var parameters = <String>[];
    while (itemsRemaining) {
      var param = '';
      if (charIt.currentAsString == ':') {
        // Last param
        while ((itemsRemaining = charIt.moveNext())) {
          param += charIt.currentAsString;
        }
      }
      else {
        // Middle param
        do {
          param += charIt.currentAsString;
        } while (
          (itemsRemaining = charIt.moveNext()) && 
          charIt.currentAsString.trim().isNotEmpty
        );
        while ((itemsRemaining = charIt.moveNext()) && charIt.currentAsString.trim().isEmpty) {
          // Skip whitespace
        }
      }
      parameters.add(param);
    }

    return IrcMessage(
      prefix: prefix,
      command: command.toUpperCase(),
      parameters: parameters,
    );
  }

  @override
  String toString() {
    var result = '';
    if (prefix != null) {
      result += ':$prefix ';
    }
    result += _customCommandName ?? command;
    if (parameters.isNotEmpty) {
      for (var param in parameters.sublist(0, parameters.length - 1)) {
        result += ' $param';
      }
      final lastParam = parameters.last;
      result += ' :$lastParam';
    }
    return result;
  }
}


class IrcMessagePing extends IrcMessage {
  IrcMessagePing(String serverName) : super(
    command: 'PONG',
    parameters: [serverName]
  );
  factory IrcMessagePing.withLocalHostname() => IrcMessagePing(Platform.localHostname);
}
class IrcMessagePong extends IrcMessage {
  IrcMessagePong(String serverName) : super(
    command: 'PONG',
    parameters: [serverName]
  );
  factory IrcMessagePong.withLocalHostname() => IrcMessagePong(Platform.localHostname);
}

class IrcNumericReply {
  final String serverName;
  final int message;
  final List<String> parameters;
  final String? messageName;

  IrcNumericReply(this.serverName, this.message, this.parameters, {this.messageName});
  
  factory IrcNumericReply.withLocalHostname(int message, List<String> parameters) 
    => IrcNumericReply(Platform.localHostname, message, parameters);

  IrcMessage get ircMessage => IrcMessage.numeric(serverName, message, parameters: parameters, messageName: messageName,);
}
