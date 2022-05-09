part of 'app.dart';

/// Base class that automatically defines [listen] for a class using a
/// ChunkCollector. This assumes that the field is named (and overrides)
/// [_collector].
abstract class ChunkCollectorSocket {
  final ChunkCollector _collector;
  final StreamController<IncomingSignal> _signalStreamController;

  ChunkCollectorSocket()
      : _collector = ChunkCollector(),
        _signalStreamController = StreamController() {
    _collector.stream.listen((IncomingPacket packet) {
      handleSignal(
        packet.sender,
        Signal.acknowledged(snowflake: packet.snowflake),
      );
    });
  }

  Stream<IncomingSignal> get signalStream {
    return _signalStreamController.stream.asBroadcastStream();
  }

  bool get isOpen {
    return !isCleanedUp;
  }

  /// Checks whether the client has been cleaned up by a call to [close].
  /// If it has, this client may no longer be used and a new one will need to
  /// be created for a new connection.
  bool get isCleanedUp {
    return _collector.isClosed;
  }

  /// Sends the specified [Signal] to the specified [NetworkEntity].
  void handleSignal(NetworkEntity to, Signal signal);

  /// Can be overridden to handle a [ChunkError] emitted when processing
  /// incoming datagrams from a [sender].
  void handleChunkError(NetworkEntity sender, ChunkError error);

  /// Can be overridden to handle a [PacketError] emitted when processing
  /// incoming datagrams from a [sender].
  void handlePacketError(NetworkEntity sender, PacketError error);

  Future<void> _bindSocketListener(RawDatagramSocket socket) async {
    socket.listen((RawSocketEvent event) async {
      if (!isOpen) return await _close();

      switch (event) {
        case RawSocketEvent.closed:
          return await _close(skipCleanup: true);
        case RawSocketEvent.read:
          {
            final datagram = socket.receive();
            if (datagram == null) return;

            printBlankDebugLine();
            logger.d(() => "Received datagram: ${datagram.log}");

            // Process incoming chunks.
            if (IncomingChunk.isChunk(datagram.data)) {
              try {
                final chunk = IncomingChunk.parse(
                  NetworkEntity(
                    host: datagram.address,
                    port: datagram.port,
                  ),
                  datagram.data,
                );

                logger.d(() => "Processed chunk: ${chunk.log}");
                printBlankDebugLine();

                _collector.addChunk(chunk);
              } on ChunkError catch (ex) {
                handleChunkError(NetworkEntity(host: datagram.address, port: datagram.port), ex);
                logger.e(ex.message, ex);
              } on PacketError catch (ex) {
                handlePacketError(NetworkEntity(host: datagram.address, port: datagram.port), ex);
                logger.e(ex.message, ex);
              }
            }

            // Process incoming signals.
            if (IncomingSignal.isSignal(datagram.data)) {
              try {
                final signal = IncomingSignal.parse(
                  NetworkEntity(
                    host: datagram.address,
                    port: datagram.port,
                  ),
                  datagram.data,
                );

                logger.d(() => "Processed signal: ${signal.log}");
                printBlankDebugLine();

                if (signal.type == SignalType.ping) {
                  handleSignal(NetworkEntity(host: datagram.address, port: datagram.port), Signal.pong());
                }

                _signalStreamController.add(signal);
              } on AssertionError catch (ex) {
                logger.e(ex.message, ex);
              }
            }

            return;
          }
        default:
          return;
      }
    });
  }

  /// Register a [StreamSubscription] for [IncomingPacket] events from the
  /// [ChunkCollector].
  StreamSubscription listen(
    void Function(IncomingPacket event)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) =>
      _collector.stream.listen(
        onData,
        onError: onError,
        onDone: onDone,
        cancelOnError: cancelOnError,
      );

  /// Closes the chunk collector.
  Future<void> _close({bool skipCleanup = false}) async {
    if (!skipCleanup) await _collector.close();
  }
}
