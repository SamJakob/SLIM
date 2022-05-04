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

  /// Represents an entity that may be communicated with over the SLIM
  /// protocol.
  const NetworkEntity({
    InternetAddress? host,
    required this.port,
  }) : _host = host;

  /// Creates a [NetworkEntity] based on the first result returned by
  /// looking up the specified [host].
  static Future<NetworkEntity> lookup({required String host, required int port}) async {
    return NetworkEntity(host: (await InternetAddress.lookup(host)).first, port: port);
  }

  @override
  int get hashCode => Object.hash(_host.hashCode, port.hashCode);

  @override
  bool operator ==(Object other) {
    return other is NetworkEntity && _host == other._host && port == other.port;
  }
}

enum NetworkDirectionality { incoming, outgoing }
