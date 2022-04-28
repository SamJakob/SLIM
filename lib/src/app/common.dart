part of 'app.dart';

/// Base class that automatically defines [listen] for a class using a
/// ChunkCollector. This assumes that the field is named (and overrides)
/// [_collector].
abstract class ChunkCollectorSocket {
  final ChunkCollector _collector;

  ChunkCollectorSocket() : _collector = ChunkCollector();

  bool get isOpen {
    return !isCleanedUp;
  }

  /// Checks whether the client has been cleaned up by a call to [close].
  /// If it has, this client may no longer be used and a new one will need to
  /// be created for a new connection.
  bool get isCleanedUp {
    return _collector.isClosed;
  }

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

            _collector.addChunk(IncomingChunk.parse(
              NetworkEntity(
                host: datagram.address,
                port: datagram.port,
              ),
              datagram.data,
            ));
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
