import 'package:chungus_protocol/chungus_protocol.dart';

/// Server example for ChungusProtocol.
/// Refer to `client.dart` for an example client.
Future<void> main() async {
  var server = ChungusServer(port: 5895);
  await server.start();

  while (true) {
    var incomingPacket = await server.receive();
    if (incomingPacket.message == "exit") {
      server.close();
      break;
    }

    print('Client: ${incomingPacket.message}');
    server.send(incomingPacket.address, incomingPacket.port, incomingPacket.message);
  }

  print("Shutting down!");
}
