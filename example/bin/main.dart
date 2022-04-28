import 'dart:io';

import 'package:chungus_protocol/chungus_protocol.dart';
import 'package:chungus_protocol/src/core/packet.dart';

/// Client example for ChungusProtocol.
/// Refer to `server.dart` for an example server.
Future<void> main() async {
  var client = ChungusClient(server: const NetworkEntity(port: 5895));
  await client.connect();

  client.listen((IncomingPacket packet) {
    print("-- Incoming Packet: #${packet.id}");
    print(packet.reader.readInteger());
    print(packet.reader.readString());
  });

  client.send(OutgoingPacket(id: 0x01)
    ..writer.writeInteger(0xAB) // = 171
    ..writer.writeString("Howdy!")); // = 171
}
