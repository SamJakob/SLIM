import 'dart:async';
import 'dart:math';
import 'dart:typed_data';

import 'package:slim_protocol/src/core/data.dart';
import 'package:slim_protocol/src/core/network.dart';
import 'package:slim_protocol/src/core/packet.dart';
import 'package:slim_protocol/src/utils.dart';
import 'package:uuid/uuid.dart';
import 'package:xxh3/xxh3.dart';

/// The size of a chunk header.
/// This is fixed as the chunk header uses fixed length field types.
const kChunkHeaderSize = 44;

/// The maximum size of a chunk, in bytes.
/// This includes all header fields.
const kMaxChunkSize = 1024;

/// The maximum size of a chunk body.
/// This is equal to the maxChunkSize less the chunk header size.
/// e.g., with a chunkHeaderSize of 38 and a maxChunkSize of 1024,
/// this will be 986.
const kMaxChunkBodySize = kMaxChunkSize - kChunkHeaderSize;

/// The 'magic' constant that is found at the start of each chunk.
const kChunkMagicValue = 0x47525252;

/// Extension that facilitates dividing an [OutgoingPacket] into chunks.
extension Chunkify on OutgoingPacket {
  /// 'Chunkify' an outgoing packet.
  /// Splits the packet into chunks and adds the header for the transport
  /// layer.
  List<Uint8List> toChunks() {
    final packetBytes = pack();

    // Divide the packet byte-by-byte into chunks based on kMaxChunkBodySize.
    final chunks = <Uint8List>[];
    final totalChunkCount = (packetBytes.lengthInBytes / kMaxChunkBodySize).ceil();

    for (int start = 0, counter = 0; start < packetBytes.lengthInBytes; start += kMaxChunkBodySize, counter++) {
      final end = min(start + kMaxChunkBodySize, packetBytes.lengthInBytes);
      final length = end - start;

      // Assemble a chunk from the packet data fragment and a chunk header.
      final builder = BytesBuilder(copy: false);

      final chunkBody = packetBytes.sublist(start, end);

      // Chunk Magic Value
      builder.addByte(DataType.magic.value);
      builder.add(toBytes(4, (data) => data.setUint32(0, kChunkMagicValue)));

      // Chunk Length
      builder.addByte(DataType.short.value);
      builder.add(toBytes(2, (data) => data.setUint16(0, length)));

      // Chunk Snowflake (matches Packet snowflake)
      builder.addByte(DataType.fixedBytes.value);
      builder.add(snowflake);

      // Chunk Hash (XXH3 hash of chunk index and body)
      builder.addByte(DataType.fixedBytes.value);
      builder.add(toBytes(8, (data) => data.setUint64(0, xxh3(chunkBody))));

      // Chunk Index
      builder.addByte(DataType.integer.value);
      builder.add(toBytes(4, (data) => data.setUint32(0, counter)));

      // Chunk Count
      builder.addByte(DataType.integer.value);
      builder.add(toBytes(4, (data) => data.setUint32(0, totalChunkCount)));

      // Chunk Body
      builder.add(chunkBody);

      // Add the assembled chunk to the list of chunks.
      chunks.add(builder.takeBytes());
    }

    return chunks;
  }
}

/// Represents a received chunk.
class IncomingChunk {
  /// The [NetworkEntity] that sent the chunk.
  final NetworkEntity sender;

  /// The length of the chunk [body].
  final int length;

  /// The snowflake of the packet this chunk belongs to.
  final Uint8List snowflake;

  /// An XXH3 hash of the chunk body. Compared to ensure integrity of the chunk
  /// body.
  final int hash;

  /// The sequential index of this chunk relative to the current [snowflake].
  /// Allows for re-assembling packets that required multiple chunks to be
  /// sent.
  final int index;

  /// The total number of chunks that will be received for this [snowflake].
  final int count;

  /// The body of the chunk.
  final Uint8List body;

  IncomingChunk({
    required this.sender,
    required this.length,
    required this.snowflake,
    required this.hash,
    required this.index,
    required this.count,
    required this.body,
  });

  /// Parses raw bytes (such as those directly from datagrams) which may be
  /// interpreted as chunks and performs validation, returning a chunk object
  /// with the fields extracted.
  factory IncomingChunk.parse(NetworkEntity sender, Uint8List bytes) {
    final bytesData = ByteData.sublistView(bytes);

    // The pointer into the bytes data that we've currently read.
    int _pointer = 0;

    // Assert that the bytes start with the chunk's magic header.
    if (!DataType.magic.hasId(bytesData.getUint8(_pointer++)) || bytesData.getUint32(_pointer) != kChunkMagicValue) {
      throw AssertionError("Invalid chunk.");
    }
    _pointer += 4;

    // Attempt to read each of the header fields.

    // Length
    if (!DataType.short.hasId(bytesData.getUint8(_pointer++))) throw AssertionError("Invalid chunk.");
    int length = bytesData.getUint16(_pointer);
    if (length > kMaxChunkBodySize) throw AssertionError("Invalid chunk.");
    _pointer += 2;

    // Snowflake
    if (!DataType.fixedBytes.hasId(bytesData.getUint8(_pointer++))) throw AssertionError("Invalid chunk.");
    Uint8List snowflake = bytes.sublist(_pointer, _pointer + 16);
    _pointer += 16;

    // Hash
    if (!DataType.fixedBytes.hasId(bytesData.getUint8(_pointer++))) throw AssertionError("Invalid chunk.");
    int hash = bytesData.getUint64(_pointer);
    _pointer += 8;

    // Index
    if (!DataType.integer.hasId(bytesData.getUint8(_pointer++))) throw AssertionError("Invalid chunk.");
    int index = bytesData.getUint32(_pointer);
    _pointer += 4;

    // Count
    if (!DataType.integer.hasId(bytesData.getUint8(_pointer++))) throw AssertionError("Invalid chunk.");
    int count = bytesData.getUint32(_pointer);
    _pointer += 4;

    // Body
    Uint8List body = bytes.sublist(_pointer, bytes.lengthInBytes);
    if (body.lengthInBytes != length) throw AssertionError("Chunk length field mismatch.");

    // Hash body for integrity check.
    if (xxh3(body) != hash) throw AssertionError("Chunk failed integrity check.");

    return IncomingChunk(
      sender: sender,
      length: length,
      snowflake: snowflake,
      hash: hash,
      index: index,
      count: count,
      body: body,
    );
  }
}

class _ChunkCollectorChunk {
  final NetworkEntity sender;
  final List<Uint8List?> chunks;

  _ChunkCollectorChunk({required this.sender, required this.chunks});
}

/// A 'middleware' that accepts arrays of raw bytes (such as those directly
/// from datagrams) which may be interpreted as chunks and then re-assembles
/// packets from those.
///
/// Chunks are collected and mapped. Once all the constituent chunks for a
/// packet have been collected, the packet is re-assembled and emitted.
///
/// Once a [ChunkCollector] has [close]d, it may not be re-opened. You must
/// instead initialize a new ChunkCollector.
class ChunkCollector {
  /// The map of collected chunks, used to re-assemble the entire packets.
  final Map<String, _ChunkCollectorChunk> _chunks;

  /// The stream controller that consumers may listen to to receive packet
  /// events.
  final StreamController<IncomingPacket> _controller;

  /// Returns the stream of [IncomingPacket]s from the received re-built
  /// chunks.
  Stream<IncomingPacket> get stream => _controller.stream;

  /// Whether the [ChunkCollector] (via the underlying [StreamController])
  /// has been paused.
  bool get isPaused => _controller.isPaused;

  /// Whether the [ChunkCollector] (via the underlying [StreamController])
  /// has been closed. If it has been closed, it has been cleaned up and
  /// will need to be recreated for further use.
  bool get isClosed => _controller.isClosed;

  ChunkCollector()
      : _chunks = {},
        _controller = StreamController();

  /// Add a chunk to the collector.
  void addChunk(IncomingChunk chunk) {
    // Initialize this snowflake in the chunks map if it does not already
    // exist.
    String snowflake = Uuid.unparse(chunk.snowflake);

    if (!_chunks.containsKey(snowflake)) {
      _chunks[snowflake] = _ChunkCollectorChunk(
        sender: chunk.sender,
        chunks: List.filled(chunk.count, null, growable: false),
      );
    }

    // TODO: add timeout to ensure incomplete chunks are not left indefinitely.

    // Assert that this chunk's sender matches the sender of the group this
    // chunk would belong to.
    if (_chunks[snowflake]!.sender != chunk.sender) {
      throw AssertionError("Security error. Chunk sender mismatch.");
    }

    // Assert that this chunk's count matches the length of the chunk group.
    if (_chunks[snowflake]!.chunks.length != chunk.count) {
      throw AssertionError("Chunk integrity error. Chunk count mismatch.");
    }

    // Now, add this chunk's body to the chunk's map.
    _chunks[snowflake]!.chunks[chunk.index] = chunk.body;

    // Check if there are no null bytes left in the chunk's map.
    final entirePacket = !_chunks[snowflake]!.chunks.any((element) => element == null);

    // If an entire packet has been received, remove it from the map and emit
    // the packet.
    if (entirePacket) {
      // We can cast the list to a null-checked [Uint8List] because we check
      // that there are no null bytes.
      _emit(
        _chunks[snowflake]!.sender,
        _chunks[snowflake]!.chunks.cast<Uint8List>(),
      );
      // ...and remove the chunk from the map as it's now completed.
      _chunks.remove(snowflake);
    }
  }

  /// Emits a packet to the stream [_controller].
  /// If the stream controller is paused, the packet is added to the backlog,
  /// until the stream is resumed.
  void _emit(NetworkEntity sender, List<Uint8List> packetChunks) {
    // Concatenate the packet chunks.
    final builder = BytesBuilder(copy: false);
    packetChunks.forEach(builder.add);
    final packet = builder.takeBytes();

    final bytesData = ByteData.sublistView(packet);

    // -- Read the magic and length value from the packet and strip them out.

    // The pointer into the bytes data that we've currently read.
    int _pointer = 0;

    // Assert that the bytes start with the packet's magic header.
    if (!DataType.magic.hasId(bytesData.getUint8(_pointer++)) || bytesData.getUint32(_pointer) != kPacketMagicValue) {
      throw AssertionError("Invalid packet.");
    }
    _pointer += 4;

    // Assert that the packet length equals the chunk length.
    if (!DataType.varInt.hasId(bytesData.getUint8(_pointer++))) throw AssertionError("Invalid packet.");
    int length = VarLengthNumbers.readVarInt(() => bytesData.getUint8(_pointer++));
    if (length != (bytesData.lengthInBytes - _pointer)) {
      throw AssertionError("Packet length mismatch (expected: $length, got ${(bytesData.lengthInBytes - _pointer)}).");
    }

    IncomingPacket incomingPacket = Packet.parse(
      sender: sender,
      bytes: packet.sublist(_pointer, packet.lengthInBytes),
    ) as IncomingPacket;
    _controller.sink.add(incomingPacket);
  }

  Future<void> close() async {
    await _controller.close();
  }
}
