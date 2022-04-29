import 'dart:convert' show utf8;
import 'dart:typed_data';

import 'package:chungus_protocol/src/core/data.dart';
import 'package:chungus_protocol/src/core/packet.dart';

class _PacketBodyInputStreamField {
  /// The buffer containing the field data itself.
  /// Nullable because for fields that do not have a fixed length additional
  /// processing will need to be done to determine how many bytes must be
  /// read.
  final Uint8List? buffer;

  /// If the buffer is set, the ByteData view for the entire buffer.
  final ByteData? data;

  /// The data type of the read value.
  final DataType type;

  /// Whether or not the field's buffer was read. True if it was, otherwise
  /// false.
  bool get didReadBuffer => buffer != null;

  _PacketBodyInputStreamField({
    required this.buffer,
    required this.type,
  }) : data = buffer != null ? ByteData.sublistView(buffer, 0, buffer.length) : null;
}

/// Exposes a convenient API for receiving binary packet data as structured
/// data.
class PacketBodyInputSource {
  /// The packet the input source is reading from.
  final Packet packet;

  int __position = 0;

  /// The current position into the byte array that the next value(s) should be
  /// read from.
  int get position => __position;

  /// Mark the current position as read and increment the position counter
  /// by one if [delta] is not specified.
  /// Otherwise, mark [delta] positions as read and increment the position
  /// counter by [delta] to reflect as such.
  int _readPos([int? delta]) {
    // Assert that doing this read won't cause the position pointer to exceed
    // the bounds of the buffer.
    if (__position + (delta ?? 1) > bytes.lengthInBytes) {
      throw RangeError.index(
        __position + (delta ?? 1),
        bytes,
        'position',
        "Attempted to read a value outside the bounds of the packet buffer.",
        bytes.lengthInBytes,
      );
    }

    // If delta is not specified, assuming only the current position is being
    // read; return the current position and then increment the position
    // counter by one to reflect as such.
    if (delta == null) return __position++;

    // If the delta is specified, instead mark [delta] positions as read and
    // increment the position counter by [delta] to reflect as such.
    int retVal = __position;
    __position += delta;
    return retVal;
  }

  /// Returns the raw bytes from the packet body.
  Uint8List get bytes {
    if (!packet.hasBody) {
      throw AssertionError("Tried to read from packet with no body.");
    }

    return packet.body!;
  }

  PacketBodyInputSource({
    required this.packet,
  });

  /// Reads the next field from the packet (the one after the current
  /// [position]).
  ///
  /// Checks if the packet's data type matches the specified [expectedType],
  /// throwing an [AssertionError] if it does not.
  ///
  /// Optionally [isField] may be set to false to skip reading a data type
  /// byte.
  _PacketBodyInputStreamField? _readField(DataType expectedType, {bool isField = true}) {
    // Read the data type.
    DataType type;
    if (isField) {
      type = DataTypeValue.of(bytes[_readPos()]);
      if (type == DataType.none) {
        return null;
      } else if (type != expectedType) {
        throw AssertionError("Type mismatch: expected ${expectedType.name}, got ${type.name}");
      }
    } else {
      type = expectedType;
    }

    // If the type has a size, read that many bytes.
    Uint8List? buffer;
    if (type.hasSize) {
      buffer = bytes.sublist(__position, __position + type.size);
      _readPos(type.size);
    }

    return _PacketBodyInputStreamField(buffer: buffer, type: type);
  }

  /// Reads the next field as a typed array from the packet.
  /// Checks that the field data type byte matches [DataType.array], throwing
  /// an [AssertionError] if it does not.
  /// Then, reads all the elements with the specified [readElementFunction].
  ///
  /// The protocol specification specifies that all array elements have fixed
  /// non-nullable type. But to parse a non-conformant array with null bytes,
  /// you can manually use [readArray].
  ///
  /// To read an array without null-checking it you can do so as follows:
  /// ```dart
  /// // Return type: List<bool?>?
  /// readArray(DataType.boolean, () => readBoolean());
  /// ```
  /// Simply specify the data type and the corresponding element read function
  /// for that data type (requiring specification of the element read function
  /// gives greater flexibility and ensures Dart's type system can correctly
  /// resolve all of the types at compile time).
  List<T>? readArray<T>(
    DataType elementType,
    T Function() readElementFunction,
  ) {
    // Read the data type.
    final type = DataTypeValue.of(bytes[_readPos()]);
    if (type == DataType.none) {
      return null;
    } else if (type != DataType.array) {
      throw AssertionError("Type mismatch: expected array, got ${type.name}");
    }

    // Read the subsequent VarInt as the number of elements in the array.
    int arraySize = readVarInt(isField: false)!;
    if (arraySize < 1) return null;

    // Finally, read all the fields with the specified function.
    List<dynamic> result = [];
    for (int i = 0; i < arraySize; i++) {
      result.add(readElementFunction()!);
    }
    return result.cast();
  }

  /// Read the next field as a boolean field.
  /// If the field is of type [DataType.none] then null is returned instead.
  /// Throws an [InvalidValueError] if the field is not a boolean field.
  ///
  /// Optionally, [isField] may be set to false to skip reading and checking
  /// the data type byte.
  bool? readBoolean({bool isField = true}) {
    final field = _readField(DataType.boolean, isField: isField);
    if (field == null) return null;

    final value = field.buffer![0];
    if (value == 0) return false;
    if (value == 1) return true;
    throw InvalidValueError(DataType.boolean, field);
  }

  /// Reads an array of boolean fields with [readBoolean].
  /// This null-checks all the values as a default. See the documentation of
  /// [readArray] for details.
  List<bool>? readBooleanArray() => readArray(DataType.boolean, () => readBoolean(isField: false)!);

  _PacketBodyInputStreamField? _readFixIntField(DataType type, {bool signed = false, bool isField = true}) {
    // If we're reading a signed value and the specified type is unsigned,
    // we'll convert the type to its signed variant. This will ensure that
    // the type validation is correct.
    if (signed && !type.isSigned) type = type.signed!;
    return _readField(type, isField: isField);
  }

  /// Read a byte (8-bit integer) field.
  ///
  /// Optionally, [isField] may be set to false to skip reading and checking
  /// the data type byte.
  int? readByte({bool signed = false, bool isField = true}) {
    // Read the field data type and field byte(s).
    final field = _readFixIntField(DataType.byte, signed: signed, isField: isField);
    if (field == null) return null;
    // Decode the number and return it.
    if (signed) {
      return field.data!.getInt8(0);
    } else {
      return field.data!.getUint8(0);
    }
  }

  /// Reads an array of byte fields with [readByte].
  /// NOTE: the name `readByteFieldArray` is selected to avoid confusion with
  /// [readBytes] which reads a byte array.
  ///
  /// In this implementation of the protocol, this is functionally the same
  /// (although [readByteFieldArray] is implemented with [readArray] to ensure
  /// the fields are handled correctly) - however this is not always a
  /// guarantee. Implementations may choose to skip reading fields of certain
  /// arrays for performance reasons and this one may be updated to do so in
  /// future, so the correct data type should be selected.
  ///
  /// This null-checks all the values as a default. See the documentation of
  /// [readArray] for details.
  List<int>? readByteFieldArray({bool signed = false}) => readArray(DataType.byte, () => readByte(signed: signed, isField: false)!);

  /// Read a short (16-bit integer) field.
  ///
  /// Optionally, [isField] may be set to false to skip reading and checking
  /// the data type byte.
  int? readShort({bool signed = false, bool isField = true}) {
    // Read the field data type and field byte(s).
    final field = _readFixIntField(DataType.short, signed: signed, isField: isField);
    if (field == null) return null;
    // Decode the number and return it.
    if (signed) {
      return field.data!.getInt16(0);
    } else {
      return field.data!.getUint16(0);
    }
  }

  /// Reads an array of short fields with [readShort].
  /// This null-checks all the values as a default. See the documentation of
  /// [readArray] for details.
  List<int>? readShortArray({bool signed = false}) => readArray(DataType.short, () => readShort(signed: signed, isField: false)!);

  /// Read an integer (32-bit integer) field.
  ///
  /// Optionally, [isField] may be set to false to skip reading and checking
  /// the data type byte.
  int? readInteger({bool signed = false, bool isField = true}) {
    // Read the field data type and field byte(s).
    final field = _readFixIntField(DataType.integer, signed: signed, isField: isField);
    if (field == null) return null;
    // Decode the number and return it.
    if (signed) {
      return field.data!.getInt32(0);
    } else {
      return field.data!.getUint32(0);
    }
  }

  /// Reads an array of integer fields with [readInteger].
  /// This null-checks all the values as a default. See the documentation of
  /// [readArray] for details.
  List<int>? readIntegerArray({bool signed = false}) => readArray(DataType.integer, () => readInteger(signed: signed, isField: false)!);

  /// Reads a 2D array of integer fields with [readArray] and [readInteger].
  /// The integer values are null-checked but the arrays are not. See the
  /// documentation of [readArray] for details.
  /// This primarily serves as an example of how multi-dimensional arrays might
  /// be handled with the protocol.
  List<List<int>?>? readInteger2DArray() => readArray(
        DataType.array,
        () => readArray(DataType.integer, () => readInteger(isField: false)!),
      );

  /// Read a long (64-bit integer) field.
  ///
  /// Optionally, [isField] may be set to false to skip reading and checking
  /// the data type byte.
  int? readLong({bool signed = false, bool isField = true}) {
    // Read the field data type and field byte(s).
    final field = _readFixIntField(DataType.long, signed: signed, isField: isField);
    if (field == null) return null;
    // Decode the number and return it.
    if (signed) {
      return field.data!.getInt64(0);
    } else {
      return field.data!.getUint64(0);
    }
  }

  /// Reads an array of long fields with [readLong].
  /// This null-checks all the values as a default. See the documentation of
  /// [readArray] for details.
  List<int>? readLongArray({bool signed = false}) => readArray(DataType.long, () => readLong(signed: signed, isField: false)!);

  /// Read a single-precision IEEE 754 floating point number.
  ///
  /// Optionally, [isField] may be set to false to skip reading and checking
  /// the data type byte.
  double? readFloat({bool isField = true}) {
    // Read the field.
    final field = _readField(DataType.float, isField: isField);
    if (field == null) return null;
    // Decode the float and return it.
    return field.data!.getFloat32(0);
  }

  /// Reads an array of float fields with [readFloat].
  /// This null-checks all the values as a default. See the documentation of
  /// [readArray] for details.
  List<double>? readFloatArray() => readArray(DataType.float, () => readFloat(isField: false)!);

  /// Read a double-precision IEEE 754 floating point number.
  ///
  /// Optionally, [isField] may be set to false to skip reading and checking
  /// the data type byte.
  double? readDouble({bool isField = true}) {
    // Read the field.
    final field = _readField(DataType.double, isField: isField);
    if (field == null) return null;
    // Decode the float and return it.
    return field.data!.getFloat64(0);
  }

  /// Reads an array of double fields with [readDouble].
  /// This null-checks all the values as a default. See the documentation of
  /// [readArray] for details.
  List<double>? readDoubleArray() => readArray(DataType.double, () => readDouble(isField: false)!);

  /// Read a variable length signed integer (up to a 32-bit integer).
  /// Optionally, [isField] may be set to false to skip reading and checking
  /// the data type byte.
  ///
  /// Optionally, [isField] may be set to false to skip reading and checking
  /// the data type byte.
  int? readVarInt({bool isField = true}) {
    // Read the field.
    final field = _readField(DataType.varInt, isField: isField);
    if (field == null) return null;

    // Now read the VarInt byte-by-byte.
    return VarLengthNumbers.readVarInt(() => bytes[_readPos()]);
  }

  /// Reads an array of VarInt fields with [readVarInt].
  /// This null-checks all the values as a default. See the documentation of
  /// [readArray] for details.
  List<int>? readVarIntArray() => readArray(DataType.varInt, () => readVarInt(isField: false)!);

  /// Read a variable length long signed integer (up to a 64-bit integer).
  ///
  /// Optionally, [isField] may be set to false to skip reading and checking
  /// the data type byte.
  int? readVarLong({bool isField = true}) {
    // Read the field.
    final field = _readField(DataType.varLong, isField: isField);
    if (field == null) return null;

    // Now read the VarLong byte-by-byte.
    return VarLengthNumbers.readVarLong(() => bytes[_readPos()]);
  }

  /// Reads an array of VarLong fields with [readVarLong].
  /// This null-checks all the values as a default. See the documentation of
  /// [readArray] for details.
  List<int>? readVarLongArray() => readArray(DataType.varLong, () => readVarLong(isField: false)!);

  /// Read a UTF-8 encoded string based on its length as prefixed with a
  /// VarInt.
  ///
  /// Optionally, [isField] may be set to false to skip reading and checking
  /// the data type byte.
  String? readString({bool isField = true}) {
    // Read the field.
    final field = _readField(DataType.string, isField: isField);
    if (field == null) return null;

    // Now read the length as a VarInt.
    int stringLength = readVarInt(isField: false)!;
    if (stringLength < 1) return null;

    // Read that many bytes and return the value.
    final value = utf8.decode(bytes.sublist(__position, __position + stringLength));
    _readPos(stringLength);
    return value;
  }

  /// Reads an array of String fields with [readString].
  /// This does NOT null check the values because, per the protocol, Strings of
  /// length 0 are to be interpreted and represented as null fields.
  List<String?>? readStringArray() => readArray(DataType.string, () => readString(isField: false));

  /// Read a sequence of bytes based on its length as prefixed with a VarInt.
  ///
  /// Optionally, [isField] may be set to false to skip reading and checking
  /// the data type byte.
  Uint8List? readBytes({bool isField = true}) {
    // Read the field.
    final field = _readField(DataType.bytes, isField: isField);
    if (field == null) return null;

    // Now read the length as a VarInt.
    int bytesLength = readVarInt(isField: false)!;
    if (bytesLength < 1) return null;

    // Read that many bytes and return the value.
    final value = bytes.sublist(__position, __position + bytesLength);
    _readPos(bytesLength);
    return value;
  }

  /// Reads an array of Bytes fields with [readBytes].
  /// This does NOT null check the values because, per the protocol, Bytes
  /// fields of length 0 are to be interpreted and represented as null fields.
  List<Uint8List?>? readBytesArray() => readArray(DataType.bytes, () => readBytes(isField: false));
}

class _PacketBodyOutputSinkField {
  /// The buffer containing all of the data for the field.
  final Uint8List buffer;

  /// The sublist view into the buffer that data should be written into.
  /// This allows for translucently prepending header values.
  final ByteData data;

  _PacketBodyOutputSinkField({
    required this.buffer,
    int offset = 1,
  }) : data = ByteData.sublistView(buffer, offset, buffer.lengthInBytes);
}

/// Exposes a convenient API for writing structured binary data as packet data.
class PacketBodyOutputSink with _DataFieldWriter {
  @override
  final List<Uint8List> _byteFields;

  /// Creates a [PacketBodyOutputSink], optionally with an existing [body]
  /// that will be written in as an entire field of its own (with no data
  /// type ID) which essentially means that when the output packet is created,
  /// it will simply include the entirety of [body] before any fields later
  /// defined with this class.
  PacketBodyOutputSink(
    Uint8List? body,
  ) : _byteFields = [if (body != null) body];

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

  /// A 'sugar' to create a builder for an array field.
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
    if (value._byteFields.isEmpty) return writeNull();

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

  /// The type of each element. If specified, the array is interpreted as a
  /// typed array and this type is fixed for the entire array. Additionally,
  /// data type bytes for each element will *not* be written.
  /// Otherwise, the array is interpreted as an untyped array and each
  /// element's type is specified by writing a data type byte before each
  /// element.
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
    if (elementType != null && type != elementType) {
      throw ArgumentError.value(
        type,
        "type",
        "The specified field type, ${type.name}, does not match the type for this array, ${elementType!.name}.",
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
mixin _DataFieldWriter {
  List<Uint8List> get _byteFields;
  _PacketBodyOutputSinkField _createField(DataType type, {required int length});

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

  /// Writes a long (64-bit integer) field.
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
  void writeFloat(double value) {
    // Create the field.
    final field = _createField(DataType.float, length: 4);
    // Encode the float and add the field buffer to the list of fields.
    field.data.setFloat32(0, value);
    _byteFields.add(field.buffer);
  }

  /// Writes a double-precision IEEE 754 floating point number.
  void writeDouble(double value) {
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

    if (stringBytes.isEmpty) {
      return writeNull();
    }

    // Encode the length in bytes as a VarInt.
    final stringLength = stringBytes.length.toVarInt();

    // Create the field...
    final field = _createField(
      DataType.string,
      length: stringLength.lengthInBytes + stringBytes.lengthInBytes,
    );

    // ...add the length to the field...
    field.buffer.setRange(1, stringLength.lengthInBytes + 1, stringLength);

    // ...add the actual string data to the field...
    field.buffer.setRange(1 + stringLength.lengthInBytes, field.buffer.lengthInBytes, stringBytes);

    // ...and finally, add the field buffer to the list of fields.
    _byteFields.add(field.buffer);
  }

  /// Writes the byte list, prefixed with its size in bytes as a VarInt.
  void writeBytes(Uint8List bytes) {
    if (bytes.isEmpty) return writeNull();

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
