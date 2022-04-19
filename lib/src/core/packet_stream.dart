library chungus_protocol;

import 'dart:convert' show utf8;
import 'dart:typed_data';

import 'package:chungus_protocol/src/core/data.dart';
import 'package:chungus_protocol/src/core/packet.dart';

/// Exposes a convenient API for receiving binary packet data as structured
/// data.
class PacketBodyInputStream {
  /// The current position into the byte array that the next value(s) should be
  /// read from.
  int position = 0;

  PacketBodyInputStream({
    required Packet packet,
  }) {
    if (!packet.hasBody) {
      throw ArgumentError.value(
        packet.body,
        "packet.body",
        "The specified packet must have a body.",
      );
    }
  }
}

class _PacketBodyOutputSinkField {
  /// The buffer containing all of the data for the field.
  final Uint8List buffer;

  /// The sublist view into the buffer that data should be written into.
  /// This allows for translucently prepending header values.
  final ByteData data;

  /// The offset for the sublistView into the buffer.
  final int offset;

  _PacketBodyOutputSinkField({
    required this.buffer,
    this.offset = 1,
  }) : data = ByteData.sublistView(buffer, offset, buffer.lengthInBytes - 1);
}

/// Exposes a convenient API for writing structured binary data as packet data.
class PacketBodyOutputSink with _DataFieldWriter {
  @override
  final List<Uint8List> _byteFields;

  PacketBodyOutputSink() : _byteFields = [];

  /// Whether the output sink has any bytes written into it.
  bool get hasBytes => _byteFields.isNotEmpty;

  /// Collects all of the written fields as a single [Uint8List].
  Uint8List get bytes {
    final builder = BytesBuilder(copy: false);
    for (var element in _byteFields) {
      if (element.lengthInBytes > 0) builder.add(element);
    }
    return builder.takeBytes();
  }

  @override
  _PacketBodyOutputSinkField _createField(DataType type, {required int length}) {
    // Ensure that the length of the field is valid; 0 or a positive integer.
    if (length < 0) {
      throw RangeError.value(
        length,
        "length",
        "The length of a field must be 0 or a positive integer.",
      );
    }

    // Create a buffer with the field length plus one for the type byte.
    final buffer = Uint8List(1 + length);
    // Write the type byte into the buffer before returning it.
    buffer[0] = type.value;
    return _PacketBodyOutputSinkField(buffer: buffer);
  }

  /// Creates a builder for an array field.
  /// Optionally, [length] may be specified to validate the length of the
  /// resultant array. If [length] is unspecified, it will be set dynamically.
  /// You can create an untyped array by instantiating [ArrayBuilder] yourself,
  /// however as the protocol only supports typed arrays, this create method
  /// forces you to specify a type.
  ArrayBuilder createArrayBuilder(DataType type, {int? length}) {
    return ArrayBuilder(elementType: type, validateLength: length);
  }

  /// Writes an array field based on the specified [ArrayBuilder].
  /// You should use [createArrayBuilder] to obtain a typed array builder.
  void writeArray(ArrayBuilder value) {
    // Get the Uint8List of all the bytes in the array.
    final arrayData = value.build();

    // Then, simply create a field for it and write the result into the output
    // sink.
    _byteFields.add(
      _createField(DataType.array, length: arrayData.lengthInBytes).buffer,
    );
  }
}

/// A utility class to build protocol arrays.
class ArrayBuilder with _DataFieldWriter {
  @override
  final List<Uint8List> _byteFields;

  /// The type of each element. This is fixed for the entire array.
  final DataType? elementType;

  /// If set, the [ArrayBuilder] will validate that the array's length is equal
  /// to this value on build.
  final int? validateLength;

  ArrayBuilder({
    this.elementType,
    this.validateLength,
  }) : _byteFields = [];

  /// Collects all of the array elements as a single [Uint8List].
  Uint8List get fieldBytes {
    final builder = BytesBuilder(copy: false);
    for (var element in _byteFields) {
      if (element.lengthInBytes > 0) builder.add(element);
    }
    return builder.takeBytes();
  }

  /// Builds the array, prepends the data type byte (of the elements) and array
  /// length value and returns the resultant [Uint8List].
  Uint8List build() {
    int arrayLength = _byteFields.length;

    // If [validateLength] is specified, assert that it equals the current
    // array length.
    if (validateLength != null && validateLength != arrayLength) {
      throw AssertionError("The array length ($arrayLength) does not match the specified array length ($validateLength).");
    }

    final arrayLengthBytes = arrayLength.toVarInt();
    final fields = fieldBytes;

    // [array length as a VarInt] +
    // [data type of array elements (if elementType is null this is untyped and the type is set per-field] +
    // [...fields]
    final buffer = Uint8List(arrayLengthBytes.lengthInBytes + (elementType != null ? 1 : 0) + fields.lengthInBytes);

    // Write the array length.
    buffer.setRange(0, arrayLengthBytes.lengthInBytes - 1, arrayLengthBytes);

    // Write the element data type byte.
    if (elementType != null) buffer[arrayLengthBytes.lengthInBytes] = elementType!.value;

    // Write the fields.
    buffer.setRange(arrayLengthBytes.lengthInBytes + (elementType != null ? 1 : 0), buffer.length - 1, fields);

    // Return the built buffer.
    return buffer;
  }

  @override
  _PacketBodyOutputSinkField _createField(DataType type, {required int length}) {
    // Ensure that the element type of the field matches that of the array.
    if (type != elementType) {
      throw ArgumentError.value(
        type,
        "type",
        "The specified field type, $type, does not match the type for this array, $elementType.",
      );
    }

    // Next, if validateLength is set, ensure that we have not exceeded the
    // length for the array.
    if (validateLength != null && _byteFields.length >= validateLength!) {
      throw RangeError(
        "This array can only hold at most $validateLength elements. "
        "Adding this element would cause the array to have ${validateLength! + 1} elements",
      );
    }

    // Finally, as with the PacketDataOutputSink, ensure that the length of the
    // field is 0 or a positive integer.
    if (length < 0) {
      throw RangeError.value(
        length,
        "length",
        "The length of a field must be 0 or a positive integer.",
      );
    }

    if (elementType != null) {
      // Create a buffer with the field length but do not include the type byte
      // as that is specified by the array.
      final buffer = Uint8List(length);
      return _PacketBodyOutputSinkField(buffer: buffer, offset: 0);
    } else {
      // Create a buffer with the field length and include the field type by
      // prepending it.
      final buffer = Uint8List(length + 1);
      return _PacketBodyOutputSinkField(buffer: buffer);
    }
  }
}

//
// DataFieldWriter
//

/// Utility mixin that contains methods for writing all of the protocol's
/// supported fields into a resulting byte array list that can be packed
/// together.
///
/// Classes using [_DataFieldWriter] override [_createField] to optionally
/// include the type byte and/or perform additional validation.
///
/// Additionally, the getter _byteFields may be overridden by simply declaring
/// a private field _byteFields to store the list of fields.
abstract class _DataFieldWriter {
  List<Uint8List> get _byteFields;
  _PacketBodyOutputSinkField _createField(DataType type, {required int length});

  /// Intended to be used as a mixin and should not be extended directly.
  factory _DataFieldWriter._() => throw Exception("_DataFieldWriter should not be extended directly.");

  /// An alias for [writeNull].
  void writeNone() => writeNull();

  /// Writes a null field. As a null field is empty this simply writes just the
  /// field data type byte.
  void writeNull() {
    // Create a field of type 'none' and add the field buffer to the the list
    // of fields.
    _byteFields.add(_createField(DataType.none, length: 0).buffer);
  }

  /// Writes a boolean field.
  void writeBoolean(bool value) {
    // Create a boolean field.
    final field = _createField(DataType.boolean, length: 1);
    // Encode the boolean and add the field buffer to the the list of fields.
    field.data.setUint8(0, value ? 0x1 : 0x0);
    _byteFields.add(field.buffer);
  }

  /// Creates a FixInt field.
  /// A FixInt, as opposed to a VarInt, is an integer field of a fixed number
  /// of bytes.
  _PacketBodyOutputSinkField _createFixIntField(int value, DataType type, {bool signed = false}) {
    // If we're writing a signed value and the specified type is unsigned,
    // we'll convert the type to its signed variant. This does nothing except
    // denote to the receiving end (via the data type byte) that the integer
    // should be signed.
    if (signed && !type.isSigned) type = type.signed!;

    // Size, in bytes.
    int size = type.size;
    // Size, in bits.
    int sizeBits = size * 8;

    if (value != (signed ? value.toSigned(sizeBits) : value.toUnsigned(sizeBits))) {
      throw ArgumentError.value(
        value,
        'value',
        "The value must be " + (signed ? 'a signed' : 'an unsigned') + " $sizeBits-bit integer.",
      );
    }

    // Create the field for the type.
    return _createField(type, length: type.size);
  }

  /// Writes a byte (8-bit integer) field.
  void writeByte(int value, {bool signed = false}) {
    // Create the field.
    final field = _createFixIntField(value, DataType.byte, signed: signed);
    // Encode the number and add the field buffer to the the list of fields.
    if (signed) {
      field.data.setInt8(0, value);
    } else {
      field.data.setUint8(0, value);
    }
    _byteFields.add(field.buffer);
  }

  /// Writes a short (16-bit integer) field.
  void writeShort(int value, {bool signed = false}) {
    // Create the field.
    final field = _createFixIntField(value, DataType.short, signed: signed);
    // Encode the number and add the field buffer to the the list of fields.
    if (signed) {
      field.data.setInt16(0, value);
    } else {
      field.data.setUint16(0, value);
    }
    _byteFields.add(field.buffer);
  }

  /// Writes an integer (32-bit integer) field.
  void writeInteger(int value, {bool signed = false}) {
    // Create the field.
    final field = _createFixIntField(value, DataType.integer, signed: signed);
    // Encode the number and add the field buffer to the the list of fields.
    if (signed) {
      field.data.setInt32(0, value);
    } else {
      field.data.setUint32(0, value);
    }
    _byteFields.add(field.buffer);
  }

  /// Writes an integer (64-bit integer) field.
  void writeLong(int value, {bool signed = false}) {
    // Create the field.
    final field = _createFixIntField(value, DataType.long, signed: signed);
    // Encode the number and add the field buffer to the the list of fields.
    if (signed) {
      field.data.setInt64(0, value);
    } else {
      field.data.setUint64(0, value);
    }
    _byteFields.add(field.buffer);
  }

  /// Writes a single-precision IEEE 754 floating point number.
  void writeFloat(double value, {bool signed = false}) {
    // Create the field.
    final field = _createField(DataType.float, length: 4);
    // Encode the float and add the field buffer to the list of fields.
    field.data.setFloat32(0, value);
    _byteFields.add(field.buffer);
  }

  /// Writes a double-precision IEEE 754 floating point number.
  void writeDouble(double value, {bool signed = false}) {
    // Create the field.
    final field = _createField(DataType.double, length: 8);
    // Encode the double and add the field buffer to the list of fields.
    field.data.setFloat64(0, value);
    _byteFields.add(field.buffer);
  }

  /// Writes a variable length signed integer (up to a 32-bit integer).
  void writeVarInt(int value) {
    // Encode the value as a VarInt.
    final varInt = value.toVarInt();

    // Create the field and add the field buffer to the list of fields.
    final field = _createField(DataType.varInt, length: varInt.lengthInBytes);
    field.buffer.setRange(1, field.buffer.lengthInBytes - 1, varInt);
    _byteFields.add(field.buffer);
  }

  /// Writes a variable length long signed integer (up to a 64-bit integer).
  void writeVarLong(int value) {
    // Encode the value as a VarLong.
    final varLong = value.toVarLong();

    // Create the field and add the field buffer to the list of fields.
    final field = _createField(DataType.varInt, length: varLong.lengthInBytes);
    field.buffer.setRange(1, field.buffer.lengthInBytes - 1, varLong);
    _byteFields.add(field.buffer);
  }

  /// Writes a UTF-8 encoded string, prefixed with its size in bytes as a
  /// VarInt.
  void writeString(String value) {
    // Encode the string value as a UTF-8 byte array.
    final stringBytes = Uint8List.fromList(utf8.encode(value));

    // Encode the length in bytes as a VarInt.
    final stringLength = stringBytes.length.toVarInt();

    // Create the field...
    final field = _createField(
      DataType.string,
      length: stringLength.lengthInBytes + stringBytes.lengthInBytes,
    );

    // ...add the length to the field...
    field.buffer.setRange(1, stringLength.lengthInBytes, stringLength);

    // ...add the actual string data to the field...
    field.buffer.setRange(1 + stringLength.lengthInBytes, field.buffer.lengthInBytes - 1, stringBytes);

    // ...and finally, add the field buffer to the list of fields.
    _byteFields.add(field.buffer);
  }

  /// Writes the byte list, prefixed with its size in bytes as a VarInt.
  void writeBytes(Uint8List bytes) {
    // Encode the length of bytes as a VarInt.
    final bytesLength = bytes.lengthInBytes.toVarInt();

    // Create the field...
    final field = _createField(
      DataType.bytes,
      length: bytesLength.lengthInBytes + bytes.length,
    );

    // ...add the length to the field...
    field.buffer.setRange(1, bytesLength.lengthInBytes, bytesLength);

    // ...add the actual bytes data to the field...
    field.buffer.setRange(1 + bytesLength.lengthInBytes, field.buffer.lengthInBytes - 1, bytes);

    // ...and finally, add the field buffer to the list of fields.
    _byteFields.add(field.buffer);
  }
}
