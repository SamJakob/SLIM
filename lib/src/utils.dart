library chungus_protocol;

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
    _uuid = new Uuid(options: {
      'grng': UuidUtil.cryptoRNG,
    });
  }
}
