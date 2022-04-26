import 'dart:io';

/// Represents an entity (socket).
/// One such use is for the return address of a received packet.
class NetworkEntity {
  /// The Internet Address of the host corresponding to the entity.
  final InternetAddress address;

  /// The software port of the entity.
  final int port;

  NetworkEntity({
    required this.address,
    required this.port,
  });

  @override
  int get hashCode => Object.hash(address.hashCode, port.hashCode);

  @override
  bool operator ==(Object other) {
    return other is NetworkEntity && address == other.address && port == other.port;
  }
}

enum NetworkDirectionality { incoming, outgoing }
