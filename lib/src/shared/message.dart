library chungus_protocol;

import 'dart:io';

class IncomingMessage {
  final InternetAddress address;
  final int port;
  final String message;

  IncomingMessage({
    required this.address,
    required this.port,
    required this.message,
  });
}
