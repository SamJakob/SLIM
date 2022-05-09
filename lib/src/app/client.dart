part of 'app.dart';

/// Client-side API for the protocol.
/// This is a high-level API for the protocol that abstracts the lower-level
/// packet construction.
abstract class SLIMClient extends ChunkCollectorSocket {
  /// The server that the client will connect to.
  NetworkEntity get server;

  /// Initializes a client for the protocol.
  factory SLIMClient({required NetworkEntity server}) => _SLIMClientImpl(server: server);

  /// Connects to the server specified on initialization.
  Future<void> connect();

  /// Sends the specified [OutgoingPacket] to the server.
  void send(OutgoingPacket packet);

  /// Sends the specified [Signal] to the server.
  void sendSignal(Signal signal);

  /// Closes the connection to the server.
  ///
  /// Due to the nature of UDP being unreliable sometimes the connection will
  /// be closed unexpectedly. In which case, the event handlers and chunk
  /// collector will not be cleaned up.
  ///
  /// Simply calling [close] again will cause these to be cleaned up.
  /// You may use [isCleanedUp] to check if this socket has been cleaned up.
  Future<void> close({bool skipCleanup = false});
}

class _SLIMClientImpl extends ChunkCollectorSocket implements SLIMClient {
  @override
  final NetworkEntity server;

  RawDatagramSocket? _socket;

  /// Returns true if the socket is open and connected, otherwise false.
  @override
  bool get isOpen {
    return _socket != null && super.isOpen;
  }

  _SLIMClientImpl({
    required this.server,
  }) : super();

  @override
  Future<void> connect() async {
    if (isCleanedUp) {
      throw StateError(
        "This client has been cleaned up (connection explicitly closed). "
        "You'll need to open a new one for a new connection.",
      );
    }

    // Bind to any available address and port on the machine.
    _socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
    _bindSocketListener(_socket!);
  }

  @override
  void send(OutgoingPacket packet) {
    if (!isOpen) {
      close();
      throw StateError("Attempted to send packet whilst connection was closed.");
    }

    List<Uint8List> chunks = packet.toChunks();
    for (final chunk in chunks) {
      _socket!.send(chunk, server.host, server.port);
    }
  }

  @override
  void sendSignal(Signal signal) {
    _socket!.send(signal.pack(), server.host, server.port);
  }

  @override
  void handleSignal(NetworkEntity to, Signal signal) {
    sendSignal(signal);
  }

  @override
  void handleChunkError(NetworkEntity sender, ChunkError error) {
    // If the error was because the chunk was rejected, and there is a chunk
    // snowflake, we'll send a chunk rejection signal.
    if (error.rejected && error.snowflake != null) {
      sendSignal(Signal.rejected(snowflake: error.snowflake!, reason: error.reason));
    }
  }

  @override
  void handlePacketError(NetworkEntity sender, PacketError error) {
    // If the error was because the packet was rejected, and there is a packet
    // snowflake, we'll send a packet rejection signal.
    if (error.rejected && error.snowflake != null) {
      sendSignal(Signal.rejected(snowflake: error.snowflake!, reason: error.reason));
    }
  }

  @override
  Future<void> close({bool skipCleanup = false}) async {
    return await _close(skipCleanup: skipCleanup);
  }

  @override
  Future<void> _close({bool skipCleanup = false}) async {
    _socket?.close();
    super._close(skipCleanup: skipCleanup);
    _socket = null;
  }
}
