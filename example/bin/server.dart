import 'package:chungus_protocol/chungus_protocol.dart';
import 'package:chungus_protocol/src/core/packet.dart';

/// Server example for ChungusProtocol.
/// Refer to `client.dart` for an example client.
Future<void> main() async {
  var server = ChungusServer(port: 5895);
  await server.start();

  // Listen for packets and respond with the same packet ID and data.
  server.listen((IncomingPacket packet) {
    server.send(packet.sender, OutgoingPacket.echo(packet));
  });
}
