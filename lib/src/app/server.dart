part of 'app.dart';

/// Server-side API for the protocol.
/// This is a high-level API for the protocol that abstracts the lower-level
/// packet construction.
abstract class SLIMServer extends ChunkCollectorSocket {
  InternetAddress get host;

  /// The port that the server will bind to.
  int get port;

  /// Initializes a server for the protocol.
  factory SLIMServer({required InternetAddress host, required int port}) => _SLIMServerImpl(host: host, port: port);

  /// Starts the server and listens for connections.
  Future<void> start();

  /// Sends a packet to the specified [NetworkEntity].
  void send(NetworkEntity to, OutgoingPacket packet);

  /// Sends the specified [Signal] to the specified [NetworkEntity].
  void sendSignal(NetworkEntity to, Signal signal);

  /// Closes the server, thereby disconnecting all connected clients.
  Future<void> close();
}

class _SLIMServerImpl extends ChunkCollectorSocket implements SLIMServer {
  @override
  final InternetAddress host;

  @override
  final int port;

  RawDatagramSocket? _socket;

  /// Returns true if the socket is open and connected, otherwise false.
  @override
  bool get isOpen {
    return _socket != null && super.isOpen;
  }

  _SLIMServerImpl({required this.host, required this.port}) : super();

  @override
  Future<void> start() async {
    if (isCleanedUp) {
      throw StateError(
        "This server has been cleaned up (connection explicitly closed). "
        "You'll need to open a new one for a new connection.",
      );
    }

    // Bind to the specified service port on any address.
    _socket = await RawDatagramSocket.bind(host, port);
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
  void sendSignal(NetworkEntity to, Signal signal) {
    _socket!.send(signal.pack(), to.host, to.port);
  }

  @override
  void handleSignal(NetworkEntity to, Signal signal) {
    sendSignal(to, signal);
  }

  @override
  void handleChunkError(NetworkEntity sender, ChunkError error) {
    // If the error was because the chunk was rejected, and there is a chunk
    // snowflake, we'll send a chunk rejection signal.
    if (error.rejected && error.snowflake != null) {
      sendSignal(sender, Signal.rejected(snowflake: error.snowflake!, reason: error.reason));
    }
  }

  @override
  void handlePacketError(NetworkEntity sender, PacketError error) {
    // If the error was because the packet was rejected, and there is a packet
    // snowflake, we'll send a packet rejection signal.
    if (error.rejected && error.snowflake != null) {
      sendSignal(sender, Signal.rejected(snowflake: error.snowflake!, reason: error.reason));
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
