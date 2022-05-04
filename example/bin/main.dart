import 'package:slim_protocol/slim_protocol.dart';
import 'package:slim_protocol/src/core/packet.dart';

/// Client example for SLIM Protocol.
/// Refer to `server.dart` for an example server.
Future<void> main() async {
  var client = SLIMClient(server: const NetworkEntity(port: 5895));
  await client.connect();

  client.listen((IncomingPacket packet) {
    print("-- Incoming Packet: #${packet.id}");
    print(packet.reader.readInteger());
    print(packet.reader.readString());
  });

  client.send(OutgoingPacket(id: 0x00)
    ..writer.writeString("Sam")
    ..writer.writeString("Howdy!"));
}
