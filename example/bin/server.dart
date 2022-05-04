import 'dart:io';

import 'package:slim_protocol/slim_protocol.dart';
import 'package:slim_protocol/src/core/packet.dart';

/// Server example for SLIM Protocol.
/// Refer to `client.dart` for an example client.
Future<void> main() async {
  var server = SLIMServer(host: InternetAddress.anyIPv4, port: 5895);
  await server.start();

  // Listen for packets and respond with the same packet ID and data.
  server.listen((IncomingPacket packet) {
    print(packet);
    server.send(packet.sender, OutgoingPacket.echo(packet));
  });

  print('Now listening on ${server.host.address}:${server.port}');
}
