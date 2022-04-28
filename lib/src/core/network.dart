import 'dart:io';

/// Represents an entity (socket).
/// One such use is for the return address of a received packet.
class NetworkEntity {
  final InternetAddress? _host;

  /// The Internet Address of the host corresponding to the entity.
  /// If the [host] is not specified, then this [NetworkEntity] refers to a
  /// service (port) running on the local host and
  /// [InternetAddress.loopbackIPv4] will be used instead.
  InternetAddress get host {
    return _host ?? InternetAddress.loopbackIPv4;
  }

  /// The software port of the entity.
  final int port;

  const NetworkEntity({
    InternetAddress? host,
    required this.port,
  }) : _host = host;

  @override
  int get hashCode => Object.hash(_host.hashCode, port.hashCode);

  @override
  bool operator ==(Object other) {
    return other is NetworkEntity && _host == other._host && port == other.port;
  }
}

enum NetworkDirectionality { incoming, outgoing }
