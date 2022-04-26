library chungus_protocol;

import 'dart:typed_data';

import 'package:uuid/uuid.dart';
import 'package:uuid/uuid_util.dart';

class ProtocolUtils {
  static Uuid? _uuid;

  /// Get a global UUID generator instance.
  /// This is initialized if it is not already available.
  static Uuid get uuid {
    if (_uuid == null) initialize();
    return _uuid!;
  }

  /// Initializes protocol utilities that need to be initialized such as UUID
  /// generation.
  static void initialize() {
    _uuid = Uuid(options: {
      'grng': UuidUtil.cryptoRNG,
    });
  }
}

typedef ToBytesFunction = void Function(ByteData data);

Uint8List toBytes(int length, ToBytesFunction toBytesFunction) {
  final byteData = ByteData(length);
  toBytesFunction(byteData);
  return byteData.buffer.asUint8List();
}
