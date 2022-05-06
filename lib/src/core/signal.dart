import 'dart:typed_data';

import 'package:slim_protocol/slim_protocol.dart';
import 'package:slim_protocol/src/core/data.dart';
import 'package:slim_protocol/src/utils.dart';
import 'package:xxh3/xxh3.dart';

/// The 'magic' constant that is found at the start of each signal.
const kSignalMagicValue = 0x4D454154;

/// The list of possible signal types.
/// For each signal listed here, an entry should be provided in
/// [SignalTypeValue] to define the type byte.
enum SignalType {
  acknowledged,
  partiallyAcknowledged,
  rejected,
  ping,
  pong,
  close,
}

extension SignalTypeValue on SignalType {
  int get value {
    switch (this) {
      case SignalType.acknowledged:
        return 0x00;
      case SignalType.partiallyAcknowledged:
        return 0x01;
      case SignalType.rejected:
        return 0x02;
      case SignalType.ping:
        return 0x10;
      case SignalType.pong:
        return 0x11;
      case SignalType.close:
        return 0xFF;
    }
  }
}

enum RejectedSignalReason {
  hashMismatch,
  fieldTypeMismatch,
  badFieldValue,
}

extension RejectedSignalReasonValue on RejectedSignalReason {
  int get value {
    switch (this) {
      case RejectedSignalReason.hashMismatch:
        return 0x00;
      case RejectedSignalReason.fieldTypeMismatch:
        return 0x01;
      case RejectedSignalReason.badFieldValue:
        return 0x02;
    }
  }
}

/// Represents a signal.
class Signal {
  /// The type of signal this is.
  final SignalType type;

  /// The body of the signal.
  final Uint8List? body;

  Signal({
    required this.type,
    this.body,
  });

  factory Signal.acknowledged({required Uint8List snowflake}) {
    return Signal(
      type: SignalType.acknowledged,
      body: Uint8List(17)
        ..add(DataType.fixedBytes.value)
        ..addAll(snowflake),
    );
  }

  factory Signal.partiallyAcknowledged({required Uint8List snowflake, required List<int> missingChunks}) {
    return Signal(
      type: SignalType.partiallyAcknowledged,
      body: Uint8List(20 + missingChunks.length)
        ..add(DataType.fixedBytes.value) // + 1
        ..addAll(snowflake) // + 16
        ..add(DataType.array.value) // + 1
        ..add(DataType.byte.value) // + 1
        ..add(missingChunks.length) // + 1
        ..addAll(Uint8List.fromList(missingChunks)),
    );
  }

  factory Signal.rejected({required Uint8List snowflake, required RejectedSignalReason? reason}) {
    final body = Uint8List(17 + (reason != null ? 1 : 0))
      ..add(DataType.fixedBytes.value)
      ..addAll(snowflake);

    if (reason != null) body.add(reason.value);

    return Signal(
      type: SignalType.rejected,
      body: body,
    );
  }

  factory Signal.ping() {
    return Signal(type: SignalType.ping);
  }

  factory Signal.pong() {
    return Signal(type: SignalType.pong);
  }

  factory Signal.close() {
    return Signal(type: SignalType.close);
  }

  Uint8List pack() {
    final header = Uint8List(2)
      ..add(DataType.byte.value)
      ..add(type.value);

    final payloadBuilder = BytesBuilder(copy: false);
    payloadBuilder.add(header);
    if (body != null) payloadBuilder.add(body!);
    final payload = payloadBuilder.takeBytes();

    final prologue = Uint8List(16);

    // Magic
    prologue.add(DataType.magic.value);
    prologue.addAll(toBytes(4, (data) => data.setUint32(0, kSignalMagicValue)));

    // Length
    prologue.add(DataType.byte.value);
    prologue.add(body != null ? body!.lengthInBytes : 0);

    // Hash
    prologue.add(DataType.fixedBytes.value);
    prologue.addAll(toBytes(8, (data) => data.setUint64(0, xxh3(payload))));

    // Header + Body
    final signal = BytesBuilder(copy: false);
    signal.add(prologue);
    signal.add(header);
    if (body != null) signal.add(body!);
    return signal.takeBytes();
  }
}

/// Represents a received signal. This extends [Signal] to include data about
/// the sender of the signal as well as the received hash.
class IncomingSignal extends Signal {
  /// The length of the received signal body.
  final int length;

  /// The [NetworkEntity] that sent the signal.
  final NetworkEntity sender;

  /// An XXH3 hash of the signal body. Compared to ensure integrity of the
  /// signal body.
  final int hash;

  IncomingSignal({
    required this.sender,
    required this.hash,
    required this.length,
    required SignalType type,
    required Uint8List body,
  }) : super(
          type: type,
          body: body,
        );

  factory IncomingSignal.parse(NetworkEntity sender, Uint8List bytes) {
    throw UnimplementedError();
  }
}
