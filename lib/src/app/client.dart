library chungus_protocol;

import 'dart:io';

class ChungusClient {
  final String host;
  final int port;

  RawDatagramSocket? _socket;

  ChungusClient({
    required this.host,
    required this.port,
  });

  Future<void> connect() async {
    // Bind to any available address and port on the machine.
    _socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
  }

  void send(String message) {
    _socket!.send(message.codeUnits, _socket!.address, port);
  }

  // Future<IncomingMessage> receive() async {
  //   Datagram? datagram;
  //   while (datagram == null) datagram = _socket!.receive();
  //   return IncomingMessage(
  //     address: datagram.address,
  //     port: datagram.port,
  //     message: String.fromCharCodes(datagram.data),
  //   );
  // }

  void close() {
    _socket?.close();
    _socket = null;
  }
}
