import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'dart:convert';
import 'dart:typed_data';

import 'package:slim_protocol/slim_protocol.dart';
import 'package:slim_protocol/src/core/chunk.dart';
import 'package:slim_protocol/src/core/data.dart';
import 'package:slim_protocol/src/core/packet.dart';
import 'package:test/test.dart';
import 'package:uuid/uuid.dart';

void main() {
  // An empty outgoing packet that may be used for trivial tests.
  late final OutgoingPacket outgoingPacketEmpty;
  // The packed chunks for the above packet.
  late final List<Uint8List> outgoingPacketEmptyChunks;

  // A packet that encodes the value 'Howdy!'.
  late final OutgoingPacket outgoingPacketHowdy;
  // The packed chunks for the above packet.
  late final List<Uint8List> outgoingPacketHowdyChunks;

  // A packet whose length exceeds the maximum chunk body size to test support
  // for multiple chunks.
  late final OutgoingPacket outgoingPacketLong;
  // The packed chunks for the above packet.
  late final List<Uint8List> outgoingPacketLongChunks;

  const NetworkEntity dummySender = NetworkEntity(port: 1234);
  NetworkEntity dummyReceiver = NetworkEntity(host: InternetAddress.tryParse('123.12.12.45')!, port: 1234);

  setUpAll(() {
    final random = Random();

    outgoingPacketEmpty = Packet.create(id: 0x01);
    outgoingPacketEmptyChunks = outgoingPacketEmpty.toChunks();

    outgoingPacketHowdy = Packet.create(id: 0x02, body: Uint8List.fromList(utf8.encode("Howdy!")));
    outgoingPacketHowdyChunks = outgoingPacketHowdy.toChunks();

    Uint8List randomBytes = Uint8List((kMaxChunkBodySize * 1.5).ceil());
    for (int i = 0; i < randomBytes.length; i++) {
      randomBytes[i] = random.nextInt(255);
    }
    outgoingPacketLong = Packet.create(id: 0x03, body: Uint8List.fromList(randomBytes));
    outgoingPacketLongChunks = outgoingPacketLong.toChunks();
  });

  group('Ability to read incoming chunks', () {
    // TODO
  });

  group('Ability to write outgoing chunks', () {
    test('All packets produce the correct number of chunks', () {
      expect(outgoingPacketEmptyChunks.length, equals(1));
      expect(outgoingPacketHowdyChunks.length, equals(1));
      expect(outgoingPacketLongChunks.length, equals(2));
    });

    test('All chunks are at least kChunkHeaderSize long', () {
      // This is a 'cheap' way of testing that each chunk has a header.
      for (var chunkGroup in [
        outgoingPacketEmptyChunks,
        outgoingPacketHowdyChunks,
        outgoingPacketLongChunks,
      ]) {
        for (var chunk in chunkGroup) {
          // We check greater than instead of greater than or equal to because
          // no empty chunks should be sent.
          expect(chunk.lengthInBytes, greaterThan(kChunkHeaderSize));
        }
      }
    });

    test('All chunks start with magic value (with correct data type byte)', () {
      final magicBytes = ByteData(4)..setUint32(0, kChunkMagicValue);

      // Test that for each of the packet chunk groups, each chunk in the
      // group starts with the magic number.
      for (var chunkGroup in [
        outgoingPacketEmptyChunks,
        outgoingPacketHowdyChunks,
        outgoingPacketLongChunks,
      ]) {
        for (var chunk in chunkGroup) {
          // Check data type byte.
          // First byte of any chunk should be the magic data type.
          expect(chunk[0], equals(DataType.magic.value));
          // Check magic header. (Bytes 1, 2, 3 and 4, zero-indexed) should be
          // the magic bytes.
          expect(chunk.sublist(1, 5), equals([...magicBytes.buffer.asUint8List()]));
        }
      }
    });

    test('All chunks have correct length (with correct data type byte)', () {
      for (var chunkGroup in [
        outgoingPacketEmptyChunks,
        outgoingPacketHowdyChunks,
        outgoingPacketLongChunks,
      ]) {
        for (var chunk in chunkGroup) {
          // Bytes 5 to 7 denote the length of the chunk.
          // 5 is the data type and 6 and 7 constitute the length, as a short
          // integer.
          final lengthBytes = ByteData.sublistView(chunk, 5, 8);

          // Check data type (should be unsigned short).
          expect(lengthBytes.getUint8(0), equals(DataType.short.value));
          // Check the length of each chunk is equal to the length in bytes
          // of the chunk data minus the constant header size.
          expect(lengthBytes.getUint16(1), equals(chunk.lengthInBytes - kChunkHeaderSize));
        }
      }
    });

    test('All chunks in group have same snowflake (with correct data type byte)', () {
      for (var chunkGroup in [
        outgoingPacketEmptyChunks,
        outgoingPacketHowdyChunks,
        outgoingPacketLongChunks,
      ]) {
        Uint8List? snowflake;

        for (var chunk in chunkGroup) {
          // Expect byte 8 to be the data type byte value for FixedBytes (the
          // data type for the snowflake).
          expect(chunk[8], equals(DataType.fixedBytes.value));

          final snowflakeBytes = chunk.sublist(9, 25);

          // Set the snowflake for this chunkGroup if it has not been set.
          if (snowflake == null) {
            snowflake = snowflakeBytes;
          }
          // Otherwise, check it.
          else {
            expect(snowflakeBytes, equals(snowflake));
          }
        }
      }
    });

    test('Chunk group snowflake matches packet snowflake', () {
      // We need only check the first chunk for each packet, because we also
      // assert that all chunks in a chunk group have the same snowflake.
      expect(outgoingPacketEmptyChunks[0].sublist(9, 25), equals(outgoingPacketEmpty.snowflake));
      expect(outgoingPacketHowdyChunks[0].sublist(9, 25), equals(outgoingPacketHowdy.snowflake));
      expect(outgoingPacketLongChunks[0].sublist(9, 25), equals(outgoingPacketLong.snowflake));
    });

    // Like the previous test, except this one compares the snowflake by
    // rebuilding the packet from the chunks.
    test('Chunk group snowflake matches reconstituted packet snowflake', () async {
      final futures = <Future<bool>>[];

      for (var chunkGroup in [
        outgoingPacketEmptyChunks,
        outgoingPacketHowdyChunks,
        outgoingPacketLongChunks,
      ]) {
        final completer = Completer<bool>();
        futures.add(completer.future);

        final collector = ChunkCollector();
        collector.stream.listen((packet) {
          // Expect that the packet's snowflake matches the first chunk's
          // snowflake.
          // We needn't check all the chunks because we also assert all chunks
          // in a chunk group have the same snowflake.

          expect(Uuid.unparse(chunkGroup[0].sublist(9, 25)), equals(Uuid.unparse(packet.snowflake)));

          // Indicate that this packet was processed.
          completer.complete(true);
          collector.close();
        });

        chunkGroup.map((bytes) => IncomingChunk.parse(dummySender, bytes)).forEach(collector.addChunk);
      }

      // Assert that all packets were processed.
      expect(await Future.wait(futures), equals([true, true, true]));
    });

    test('Chunk group body cumulative length corresponds to packet length (also tested in ChunkCollector) (and check packet length has valid data type byte)',
        () async {
      final futures = <Future<bool>>[];

      for (var chunkGroup in [
        outgoingPacketEmptyChunks,
        outgoingPacketHowdyChunks,
        outgoingPacketLongChunks,
      ]) {
        final completer = Completer<bool>();
        futures.add(completer.future);

        // Concatenate the packet chunks.
        final builder = BytesBuilder(copy: false);
        chunkGroup.map((chunk) => IncomingChunk.parse(dummySender, chunk).body).forEach(builder.add);
        final packet = builder.takeBytes();

        // Then read the length value from the packet.
        int _pointer = 5;
        final bytesData = ByteData.sublistView(packet);
        expect(bytesData.getUint8(_pointer++), equals(DataType.varInt.value));

        final packetLength = VarLengthNumbers.readVarInt(() => bytesData.getUint8(_pointer++));
        // The length of the packetLength VarInt field (with data type byte).
        final packetLengthLength = _pointer - 5;

        final expectedLength =
            // Sum of all chunks, minus 4 magic bytes with 1 data type byte.
            // We also need to subtract the length of the length field, ironically.
            chunkGroup.fold(0, (int totalLength, chunk) => totalLength + (chunk.lengthInBytes - kChunkHeaderSize)) - 5 - packetLengthLength;

        expect(packetLength, equals(expectedLength));

        // Indicate that this packet was processed.
        completer.complete(true);
      }

      // Assert that all packets were processed.
      expect(await Future.wait(futures), equals([true, true, true]));
    });
  });
}
