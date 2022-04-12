import 'package:chungus_protocol/chungus_protocol.dart';

/// Server example for ChungusProtocol.
/// Refer to `client.dart` for an example client.
Future<void> main() async {
  var server = new ChungusServer(port: 1234);
  await server.start();

  while (true) {
    var message = await server.receive();
    print('Client: ${message.message}');
    server.send(message.address, message.port, message.message);
  }
}
