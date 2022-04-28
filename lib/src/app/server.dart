part of 'app.dart';

/// Server-side API for the protocol.
/// This is a high-level API for the protocol that abstracts the lower-level
/// packet construction.
abstract class ChungusServer extends ChunkCollectorSocket {
  /// The port that the server will bind to.
  int get port;

  /// Initializes a server for the protocol.
  factory ChungusServer({required int port}) => _ChungusServerImpl(port: port);

  /// Starts the server and listens for connections.
  Future<void> start();

  /// Sends a packet to the specified [NetworkEntity].
  void send(NetworkEntity to, OutgoingPacket packet);

  /// Closes the server, thereby disconnecting all connected clients.
  Future<void> close();
}

class _ChungusServerImpl extends ChunkCollectorSocket implements ChungusServer {
  @override
  final int port;

  RawDatagramSocket? _socket;

  /// Returns true if the socket is open and connected, otherwise false.
  @override
  bool get isOpen {
    return _socket != null && super.isOpen;
  }

  _ChungusServerImpl({required this.port}) : super();

  @override
  Future<void> start() async {
    if (isCleanedUp) {
      throw StateError(
        "This server has been cleaned up (connection explicitly closed). "
        "You'll need to open a new one for a new connection.",
      );
    }

    // Bind to the specified service port on any address.
    _socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, port);
    _bindSocketListener(_socket!);
  }

  @override
  void send(NetworkEntity to, OutgoingPacket packet) {
    List<Uint8List> chunks = packet.toChunks();
    for (final chunk in chunks) {
      _socket!.send(chunk, to.host, to.port);
    }
  }

  @override
  Future<void> close() async {
    return await _close();
  }

  @override
  Future<void> _close({bool skipCleanup = false}) async {
    _socket?.close();
    super._close(skipCleanup: false);
    _socket = null;
  }
}
