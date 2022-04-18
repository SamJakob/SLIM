/// Thrown when an invalid protocol data type is used.
class UnknownTypeError extends Error {
  final String typeName;

  UnknownTypeError(this.typeName);

  @override
  String toString() {
    return "Unknown type: $typeName";
  }
}

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
  /// A sequence of items of dynamic length of a packet-specified type.
  list,

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
  signedLong
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

    if (signedValue == null) throw new UnknownTypeError(
        "signed${this.name[0].toUpperCase()}${this.name.substring(1)}"
    );
    return signedValue;
  }

  bool get isSigned => value & 0xA0 != 0;
}

/// Extension that defines an accessor, .value, for all data types to get the
/// data type ID.
extension DataTypeValue on DataType {
  /// Lookup table for the protocol integer Data Type ID for a given type.
  static const values = <DataType, int>{
    DataType.unknown:         -1, // Invalid value. Used to throw an error internally.

    DataType.none:            0x00,
    DataType.boolean:         0x01,

    DataType.byte:            0x02,
    DataType.signedByte:      0xA2,
    DataType.short:           0x03,
    DataType.signedShort:     0xA3,
    DataType.integer:         0x04,
    DataType.signedInteger:   0xA4,
    DataType.long:            0x05,
    DataType.signedLong:      0xA5,

    DataType.float:           0x06,
    DataType.double:          0x07,
    DataType.varInt:          0x08,
    DataType.varLong:         0x09,

    DataType.string:          0x20,
    DataType.bytes:           0x21,
    DataType.array:           0x22,
    DataType.list:            0x23
  };

  /// Get the data type ID (value) for a given DataType enum entry.
  /// Throws an [UnknownTypeError] if the type is not in the lookup table.
  int get value {
    final value = values[this];
    if (value == null) throw new UnknownTypeError(this.name);
    return value;
  }

  /// Checks if the current data type has the ID [typeId].
  /// You might use this when checking field IDs of incoming packets.
  /// e.g., `DataType.list.hasId(nextByte());`
  bool hasId(int typeId) {
    return value == typeId;
  }
}
