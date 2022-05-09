import 'dart:typed_data';

import 'package:slim_protocol/src/core/data.dart';
import 'package:slim_protocol/src/core/signal.dart';
import 'package:uuid/uuid.dart';

/// Thrown when an invalid protocol data type is used.
class UnknownTypeError extends Error {
  /// If the error was converting to a type ID from a type name, then this is
  /// set to the name of the type. Otherwise, see [typeId].
  /// In other words, iff [wasFromId] is false, then this is set.
  final String? typeName;

  /// If the error was converting to a type name from a type ID, then this is
  /// set to the type ID. Otherwise, see [typeName].
  /// In other words, iff [wasFromId] is true, then this is set.
  final int? typeId;

  /// Whether the error was thrown trying to convert from a type ID.
  /// If this is true then that was the case, otherwise the error was thrown
  /// trying to convert *to* a type ID instead of from.
  final bool wasFromId;

  /// Type error based on an invalid type name (type ID could not be found).
  UnknownTypeError(this.typeName)
      : wasFromId = false,
        typeId = null;

  /// Type error based on invalid type ID (type name could not be found).
  UnknownTypeError.fromId(this.typeId)
      : wasFromId = true,
        typeName = null;

  @override
  String toString() {
    if (wasFromId) {
      return "Unknown type ID: ${typeId!}";
    } else {
      return "Unknown type: ${typeName!}";
    }
  }
}

/// Thrown when the size of non-fixed-size data type is attempted to be
/// retrieved.
class NotSizedTypeError extends Error {
  final String typeName;

  NotSizedTypeError(this.typeName);

  @override
  String toString() {
    return "Attempted to get sized of non-fixed-size type: $typeName";
  }
}

/// Thrown when a field has an invalid value for its data type.
class InvalidValueError extends Error {
  /// The field's type.
  final DataType type;

  /// Optionally, the value of the field.
  final dynamic value;

  InvalidValueError(this.type, [this.value]);

  @override
  String toString() {
    return "Invalid value for ${type.name} field" + (value ? ": $value" : ".");
  }
}

/// Thrown when an invalid packet is received or processed.
class PacketError extends Error {
  /// Optionally, the snowflake the [ChunkError] was raised whilst processing.
  final Uint8List? snowflake;

  /// The reason for the [PacketError].
  final String? message;

  /// If specified, denotes that the packet was rejected and the reason the
  /// packet was rejected. Also indicates that a rejection signal should be
  /// sent with the specified [reason] byte value.
  /// [RejectedSignalReason].
  final RejectedSignalReason? reason;

  /// Whether the [PacketError] is because the packet was rejected.
  /// Simply checks if [reason] is not null.
  bool get rejected => reason != null;

  PacketError({this.snowflake, this.reason, this.message});

  PacketError.rejected({this.snowflake, required this.reason, String? message}) : message = reason!.message;

  @override
  String toString() {
    return "PacketError" + (message != null ? ": ${message!}" : '');
  }
}

/// Thrown when an invalid chunk is received or processed.
class ChunkError extends Error {
  /// Optionally, the snowflake the [ChunkError] was raised whilst processing.
  final Uint8List? snowflake;

  /// The reason for the [ChunkError].
  final String? message;

  /// If specified, denotes that the chunk was rejected and the reason the
  /// chunk was rejected. Also indicates that a rejection signal should be sent
  /// with the specified [reason] byte value.
  /// [RejectedSignalReason].
  final RejectedSignalReason? reason;

  /// Whether the [ChunkError] is because the chunk was rejected.
  /// Simply checks if [reason] is not null.
  bool get rejected => reason != null;

  ChunkError({this.snowflake, this.reason, this.message});

  ChunkError.rejected({this.snowflake, required this.reason, String? message}) : message = message ?? reason!.message;

  @override
  String toString() {
    return "ChunkError" + (snowflake != null ? "(chunk: ${Uuid.unparse(snowflake!)})" : "") + (message != null ? ": ${message!}" : '');
  }
}
