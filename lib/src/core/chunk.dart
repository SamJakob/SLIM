import 'dart:math';
import 'dart:typed_data';

import 'package:chungus_protocol/src/core/packet.dart';
import 'package:xxh3/xxh3.dart';

class Chunk {
  /// The size of a chunk header.
  /// This is fixed as the chunk header uses fixed length field types.
  static const kChunkHeaderSize = 30;

  /// The maximum size of a chunk, in bytes.
  /// This includes all header fields.
  static const kMaxChunkSize = 1024;

  /// The maximum size of a chunk body.
  /// This is equal to the maxChunkSize less the chunk header size.
  /// e.g., with a chunkHeaderSize of 38 and a maxChunkSize of 1024,
  /// this will be 986.
  static const kMaxChunkBodySize = kMaxChunkSize - kChunkHeaderSize;

  /// 'Chunkify' an outgoing packet.
  /// Splits the packet into chunks and adds the header for the transport
  /// layer.
  static List<Uint8List> chunkify(OutgoingPacket packet) {
    final packetBytes = packet.pack();

    // Divide the packet byte-by-byte into chunks based on kMaxChunkBodySize.
    final chunks = <Uint8List>[];
    for (int start = 0, counter = 0; start < packetBytes.lengthInBytes; start += kMaxChunkBodySize, counter++) {
      final end = max(start + kMaxChunkBodySize, packetBytes.lengthInBytes);
      final length = end - start;

      // Assemble a chunk from the packet data fragment and a chunk header.
      final header = Uint8List(kChunkHeaderSize);
      final headerData = ByteData.sublistView(header);

      headerData.setUint16(0, length); // Chunk Length
      header.setRange(3, 19, packet.snowflake); // Chunk Snowflake (matches Packet snowflake)
      headerData.setUint64(19, xxh3(packetBytes)); // Chunk Hash (XXH3 hash of chunk index and body)
      headerData.setUint32(27, counter); // Chunk Index
      chunks.add(packetBytes.sublist(start, end));
    }

    return chunks;
  }
}
