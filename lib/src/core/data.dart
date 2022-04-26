library chungus_protocol;

import 'dart:typed_data';

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

//
// Protocol Data Types
//

/// The current list of data types implemented by the protocol and recognized
/// by the application.
enum DataType {
  /// Unknown type.
  unknown,

  //
  // Primitives.
  //

  /// Used to omit a value.
  none,

  /// Represents either true or false, encoded as 1 or 0 respectively.
  boolean,

  //
  // Integer types.
  //

  /// An unsigned 8-bit integer. There is a signed variant available as either
  /// [DataType.signedByte] or `DataType.byte.signed`.
  /// Represents an integer between 0 and 255.
  byte,

  /// An unsigned 16-bit integer. There is a signed variant available as either
  /// [DataType.signedShort] or `DataType.short.signed`.
  /// Represents an integer between 0 and 65535.
  short,

  /// An unsigned 32-bit integer. There is a signed variant available as either
  /// [DataType.signedInteger] or `DataType.integer.signed`.
  /// Represents an integer between 0 and 4294967295.
  integer,

  /// An unsigned 64-bit integer. There is a signed variant available as either
  /// [DataType.signedLong] or `DataType.long.signed`.
  /// Represents an integer between 0 and 2^64 - 1.
  long,

  //
  // IEEE 754 floating-point.
  //

  /// IEEE 754 single-precision floating point.
  float,

  /// IEEE 754 double-precision floating point.
  double,

  //
  // Variable-length integer types.
  //

  /// Variable-length signed integer.
  /// Uses any number of bytes from 1 to 5 bytes.
  /// If negative, will always use 5 bytes.
  varInt,

  /// Variable-length unsigned integer.
  /// Uses any number of bytes from 1 to 10 bytes.
  /// If negative, will always use 10 bytes.
  varLong,

  //
  // Arrays and Lists.
  //

  /// A UTF-8 character sequence prefixed with its size in bytes as a
  /// [DataType.varInt].
  string,

  /// A sequence of bytes prefixed with its size in bytes as a
  /// [DataType.varInt].
  bytes,

  /// A sequence of items of a packet-specified type of length n, where n is
  /// number of items and prefixed as a [DataType.varInt].
  array,

  //
  // Signed variants.
  //

  /// The signed variant of [DataType.byte] (8-bit integer).
  /// Represents an integer between -128 and 127.
  signedByte,

  /// The signed variant of [DataType.short] (16-bit integer).
  /// Represents an integer between -32768 and 32767.
  signedShort,

  /// The signed variant of [DataType.integer] (32-bit integer).
  /// Represents an integer between -2147483648 and 2147483647.
  signedInteger,

  /// The signed variant of [DataType.long] (64-bit integer).
  /// Represents an integer between -2^63 and 2^63 - 1.
  signedLong,

  /// Represents a field of bytes of a fixed length as defined in the
  /// packet format.
  fixedBytes,

  /// Represents a constant (otherwise known as a 'magic') value.
  ///https://en.wikipedia.org/wiki/Magic_number_(programming)
  magic,
}

/// Extension that defines an accessor, .signed, for integer types to
/// conveniently access the signed variants.
extension SignedDataType on DataType {
  /// Lookup table mapping unsigned values to signed values where appropriate.
  static const signedValues = <DataType, DataType>{
    DataType.byte: DataType.signedByte,
    DataType.short: DataType.signedShort,
    DataType.integer: DataType.signedInteger,
    DataType.long: DataType.signedInteger
  };

  /// Get the signed value for an unsigned data type.
  /// Throws an [UnknownTypeError] if the signed equivalent does not exist.
  DataType? get signed {
    final signedValue = signedValues[this];

    if (signedValue == null) throw UnknownTypeError("signed${name[0].toUpperCase()}${name.substring(1)}");
    return signedValue;
  }

  bool get isSigned => value & 0xA0 != 0;
}

/// Extension that defines an accessor, .value, for all data types to get the
/// data type ID.
extension DataTypeValue on DataType {
  /// Lookup table for the protocol data type byte for the [DataType].
  static const values = <DataType, int>{
    DataType.unknown: -1, // Invalid value. Used to throw an error internally.

    DataType.none: 0x00,
    DataType.boolean: 0x01,

    DataType.byte: 0x02,
    DataType.signedByte: 0xA2,
    DataType.short: 0x03,
    DataType.signedShort: 0xA3,
    DataType.integer: 0x04,
    DataType.signedInteger: 0xA4,
    DataType.long: 0x05,
    DataType.signedLong: 0xA5,

    DataType.float: 0x06,
    DataType.double: 0x07,
    DataType.varInt: 0x08,
    DataType.varLong: 0x09,

    DataType.string: 0x20,
    DataType.bytes: 0x21,
    DataType.array: 0x22,

    DataType.fixedBytes: 0xFE,
    DataType.magic: 0xFF,
  };

  static Map<int, DataType>? _typeFromValuesCache;

  /// Lookup table mapping a [DataType] from a protocol data type byte.
  static Map<int, DataType> get valuesInverse {
    if (_typeFromValuesCache != null) {
      return _typeFromValuesCache!;
    } else {
      return _typeFromValuesCache = values.map((key, value) => MapEntry(value, key));
    }
  }

  /// Get the data type ID (value) for a given DataType enum entry.
  /// Throws an [UnknownTypeError] if the type is not in the lookup table.
  int get value {
    final value = values[this];
    if (value == null) throw UnknownTypeError(name);
    return value;
  }

  /// Checks if the current data type has the ID [typeId].
  /// You might use this when checking field IDs of incoming packets.
  /// e.g., `DataType.array.hasId(nextByte());`
  bool hasId(int typeId) {
    return value == typeId;
  }

  /// Locates the [DataType] based on the specified ID, [value].
  static DataType of(int value) {
    if (value < 0 || value > 0xFF) throw RangeError.range(value, 0, 0xFF, 'value', 'The specified value must be an integer between 0 and 255 (0xFF).');
    var type = valuesInverse[value];
    if (type == null) throw UnknownTypeError.fromId(value);
    return type;
  }
}

/// Extension that defines an accessor, .size, for all data types to get the
/// number of bytes used by that data type.
extension DataTypeSize on DataType {
  /// Lookup table for the sizes of each data type.
  static const sizes = <DataType, int>{
    DataType.none: 0,
    DataType.boolean: 1,
    DataType.byte: 1,
    DataType.signedByte: 1,
    DataType.short: 2,
    DataType.signedShort: 2,
    DataType.integer: 4,
    DataType.signedInteger: 4,
    DataType.long: 8,
    DataType.signedLong: 8,
    DataType.float: 4,
    DataType.double: 8,
  };

  /// Gets the size in bytes for a given DataType enum entry.
  /// Throws a [NotSizedTypeError] if the type does not have a fixed size.
  int get size {
    if (!hasSize) throw NotSizedTypeError(name);
    return sizes[this]!;
  }

  bool get hasSize => sizes[this] != null;
}

//
// Variable Length Number implementation
//

// Based on a reference implementation I created here:
// https://github.com/SamJakob/ProtocolExperiments/blob/master/src/main/java/com/samjakob/protocol_experiments/data/VarLengthNumbers.java

typedef WriteByteFunction = void Function(int byte);
typedef ReadByteFunction = int Function();

/// Implementation of VarInt and VarLong.
///
/// These were originally going to either have a fixed 3-byte length prefix to
/// determine the length of the remaining data in continuation bytes OR an
/// additional separate sign bit.
///
/// However, as the use case for these variable length integers doesn't really
/// feature negative numbers, these have ended up mirroring the Minecraft
/// implementation for VarInts where negative numbers require the maximum
/// length.
///
/// For more information see:
/// https://wiki.vg/Protocol#VarInt_and_VarLong
class VarLengthNumbers {
  /// Represents 0b1000_0000.
  static const kContinueBit = 1 << 8;

  /// Represents 0b0111_1111.
  static const kSegmentBits = 127;

  /// A proxy for [writeVarNumber] that first ensures the value is a
  /// 32-bit integer.
  static void writeVarInt(WriteByteFunction writer, int value) {
    if (value != value.toSigned(32)) {
      throw ArgumentError.value(
        value,
        "value",
        "The specified value must be a 32-bit integer.",
      );
    }

    writeVarNumber(writer, value);
  }

  /// A proxy for [writeVarNumber] that first ensures the value is a 64-bit
  /// integer.
  static void writeVarLong(WriteByteFunction writer, int value) {
    if (value != value.toSigned(64)) {
      throw ArgumentError.value(
        value,
        "value",
        "The specified value must be a 32-bit integer.",
      );
    }

    writeVarNumber(writer, value);
  }

  /// Writes the variable length number specified as [value] using the
  /// specified [writer] function.
  static void writeVarNumber(WriteByteFunction writer, int value) {
    do {
      // Start by writing the value. This automatically handles the edge
      // case where value = 0.
      writer((
              // Write the segment bits (7 least significant bits) of the
              // value and OR it with the appropriate 'Continue Bit' value.
              (value & kSegmentBits) |
                  // The 'Continue Bit' is the most significant bit and should be
                  // 1 if we need to write more bytes to send the entire value.
                  //
                  // We check this by seeing if there are any bits in 'value',
                  // (excluding the segment bits we just wrote) that are set.
                  // If there are, then we know that we need to write another
                  ((value & ~kSegmentBits) != 0 ? kContinueBit : 0))
          .toUnsigned(8));

      // Shift value right, with the sign bit.
      value >>>= 7;
    } while (value != 0);
  }

  static int readVarInt(ReadByteFunction reader) {
    // The index of the current byte being processed.
    // Incremented every time a new byte is fetched due to the continuation
    // bit being set.
    int currentByteIndex = 0;

    // The value of the current byte being processed.
    // Set every time a new byte is fetched.
    int currentByte;

    // The final resulting value.
    int value = 0;

    do {
      // Read the next byte from the input stream.
      currentByte = reader().toUnsigned(8);

      // Read the current byte's segment bits and write them into the
      // resulting value. Offset the bits by the number of bytes we've
      // already processed.
      value |= (currentByte & kSegmentBits) << (currentByteIndex * 7);
      currentByteIndex++;

      // If we're on the last byte (i.e., currentByteIndex is 5), and we
      // get a set continuation bit or more than 4 overflow bytes, we
      // know that something's gone wrong.
      //
      // We factor in 1 byte for our continuation bit and determine
      // maxPosition trivially from the number of bits in a regular
      // (4-byte) integer = 8 * 4 = 32 bits.
      // (7 * 5 = 35) - (maxPosition = 32) + (1 = continuation bit)
      // = (35 - 32) + 1 = 4.
      if (currentByteIndex == 5 && (currentByte & 240) != 0) {
        throw InvalidValueError(DataType.varInt);
      }
    } while ((currentByte & kContinueBit) != 0);

    return value;
  }

  static int readVarLong(ReadByteFunction reader) {
    // The index of the current byte being processed.
    // Incremented every time a new byte is fetched due to the continuation
    // bit being set.
    int currentByteIndex = 0;

    // The value of the current byte being processed.
    // Set every time a new byte is fetched.
    int currentByte;

    // The final resulting value.
    int value = 0;

    do {
      // Read the next byte from the input stream.
      currentByte = reader().toUnsigned(8);

      // Read the current byte's segment bits and write them into the
      // resulting value. Offset the bits by the number of bytes we've
      // already processed.
      value |= (currentByte & kSegmentBits) << (currentByteIndex * 7);
      currentByteIndex++;

      // If we're on the last byte (i.e., currentByteIndex is 10), and we
      // get a set continuation bit or more than 7 overflow bytes, we
      // know that something's gone wrong.
      //
      // We factor in 1 byte for our continuation bit and determine
      // maxPosition trivially from the number of bits in a long (8-byte)
      // integer = 8 * 8 = 64 bits.
      // (7 * 10 = 70) - (maxPosition = 64) + (1 = continuation bit)
      // = (70 - 64) + 1 = 7.
      //
      // In this case, the only time the bit in the last byte is set, is
      // if the number was negative, because the sign bit overflows.
      if (currentByteIndex == 10 && (currentByte & 254) != 0) {
        throw InvalidValueError(DataType.varLong);
      }
    } while ((currentByte & kContinueBit) != 0);

    return value;
  }
}

extension VarLengthNumbersConversions on int {
  Uint8List toVarInt() {
    List<int> bytes = [];
    VarLengthNumbers.writeVarInt((byte) => bytes.add(byte), this);
    return Uint8List.fromList(bytes);
  }

  Uint8List toVarLong() {
    List<int> bytes = [];
    VarLengthNumbers.writeVarLong((byte) => bytes.add(byte), this);
    return Uint8List.fromList(bytes);
  }
}
