import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:chungus_protocol/chungus_protocol.dart';

/// Client example for ChungusProtocol.
/// Refer to `server.dart` for an example server.
Future<void> main() async {
  var client = ChungusClient(host: '127.0.0.1', port: 5895);
  await client.connect();

  while (true) {
    stdout.write("> ");
    var input = stdin.readLineSync(encoding: utf8, retainNewlines: false);
    if (input == null) continue;
    if (input == "exit") {
      client.send(input);
      client.close();
      break;
    }

    client.send(input);
    var incomingPacket = await client.receive();
    print('Server: ${incomingPacket.message}');
  }

  print("Shutting down!");
}
