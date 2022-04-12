import 'dart:convert';
import 'dart:io';

import 'package:chungus_protocol/chungus_protocol.dart';

/// Client example for ChungusProtocol.
/// Refer to `server.dart` for an example server.
Future<void> main() async {
  var client = new ChungusClient(host: '127.0.0.1', port: 1234);
  await client.connect();

  while (true) {
    stdout.write("> ");
    var input = stdin.readLineSync(encoding: utf8);
    if (input == null) continue;

    client.send(input);
    var message = await client.receive();
    print('Server: ${message.message}');
  }
}
