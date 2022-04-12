library chungus_protocol;

import 'dart:io';

import 'package:chungus_protocol/src/shared/message.dart';

class ChungusServer {
  final int port;

  RawDatagramSocket? _socket;

  ChungusServer({
    required this.port,
  });

  Future<void> start() async {
    // Bind to the specified service port on any address.
    _socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, port);
  }

  void send(InternetAddress address, int port, String message) {
    _socket!.send(message.codeUnits, address, port);
  }

  Future<IncomingMessage> receive() async {
    Datagram? datagram;
    while (datagram == null) datagram = _socket!.receive();
    return IncomingMessage(
      address: datagram.address,
      port: datagram.port,
      message: String.fromCharCodes(datagram.data),
    );
  }
}
