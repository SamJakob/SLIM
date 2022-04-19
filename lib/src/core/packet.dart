library chungus_protocol;

import 'dart:io';
import 'dart:typed_data';

import 'package:chungus_protocol/src/core/data.dart';
import 'package:chungus_protocol/src/core/packet_stream.dart';
import 'package:chungus_protocol/src/utils.dart';

/// Represents an entity (socket).
/// One such use is for the return address of a received packet.
class NetworkEntity {
  /// The Internet Address of the host corresponding to the entity.
  final InternetAddress address;

  /// The software port of the entity.
  final int port;

  NetworkEntity({
    required this.address,
    required this.port,
  });

  @override
  int get hashCode => Object.hash(address.hashCode, port.hashCode);

  @override
  bool operator ==(Object other) {
    return other is NetworkEntity && address == other.address && port == other.port;
  }
}

enum PacketDirectionality { incoming, outgoing }

abstract class Packet {
  /// The directionality of the packet.
  /// [PacketDirectionality.incoming] means the packet will be sent from the
  /// current entity to another. [PacketDirectionality.outgoing] means the
  /// packet has been received from another entity.
  PacketDirectionality get directionality;

  /// The packet ID.
  final int id;

  /// The UUIDv4 snowflake that denotes this specific packet.
  final Uint8List snowflake;

  /// Convenience getter for all the bytes in the packet body.
  Uint8List? get body => throw UnimplementedError("This packet type does not implement the body getter.");

  /// Checks whether the body exists and has more than 0 bytes.
  bool get hasBody => body != null && body!.lengthInBytes > 0;

  Packet._construct({
    required this.id,
    required this.snowflake,
  });

  /// Creates a new packet. This is intended for outgoing packets where they
  /// would be created by this instance.
  factory Packet.new({
    required int id,
    required Uint8List body,
  }) =>
      OutgoingPacket(id: id, body: body);

  /// Parse and construct an [IncomingPacket] from the specified Uint8List.
  /// This assumes the packet length has been read and stripped out of or
  /// skipped from the packet data already.
  factory Packet.from({
    required Uint8List data,
    required NetworkEntity sender,
  }) {
    final snowflake = data.sublist(0, 16);

    int currentByteCounter = 0;
    final buffer = ByteData.sublistView(data, 16);

    return IncomingPacket(
      id: VarLengthNumbers.readVarInt(() => buffer.getUint8(currentByteCounter++)),
      snowflake: snowflake,
      body: data.sublist(
        // Start index is after the snowflake (16 bytes) and packet ID
        16 + currentByteCounter,
        // End index is length - 1.
        data.lengthInBytes - 1,
      ),
      sender: sender,
    );
  }

  /// Construct an [IncomingPacket] from the specified fields.
  factory Packet.fromFields({
    required int id,
    required Uint8List snowflake,
    required Uint8List body,
    required NetworkEntity sender,
  }) =>
      IncomingPacket(
        id: id,
        snowflake: snowflake,
        body: body,
        sender: sender,
      );
}

/// Represents an incoming packet.
/// This additionally includes the [sender] property to facilitate responses to
/// the packet, as well as a [reader] to facilitate reading packet data from
/// the body.
class IncomingPacket extends Packet {
  @override
  PacketDirectionality get directionality => PacketDirectionality.incoming;

  /// The [NetworkEntity] that sent the packet.
  final NetworkEntity sender;

  /// The incoming packet's body.
  /// Making this a final variable will automatically implement the getter for
  /// us.
  @override
  final Uint8List? body;

  /// A utility to easily read packet data.
  late final PacketBodyInputStream reader;

  IncomingPacket({
    required int id,
    required Uint8List snowflake,
    required this.body,
    required this.sender,
  }) : super._construct(
          id: id,
          snowflake: snowflake,
        ) {
    reader = PacketBodyInputStream(packet: this);
  }
}

/// Represents an outgoing packet.
/// This additionally includes a [writer] to facilitate writing packet data
/// to the packet body, as well as a [pack] method that collects all of the
/// packet header and body values and prepends the prologue.
class OutgoingPacket extends Packet {
  @override
  PacketDirectionality get directionality => PacketDirectionality.outgoing;

  /// A utility to easily write packet data.
  late final PacketBodyOutputSink writer;

  @override
  Uint8List? get body {
    if (writer.hasBytes) {
      var bytes = writer.bytes;
      if (bytes.lengthInBytes > 0) return bytes;
    }

    return null;
  }

  OutgoingPacket({
    required int id,
    required Uint8List body,
  }) : super._construct(
          id: id,
          snowflake: ProtocolUtils.uuid.v4obj().toBytes(),
        ) {
    writer = PacketBodyOutputSink();
  }

  /// Collect all of the packet data, build the header, attach the prologue
  /// and the body and return the resulting entire packet as a [Uint8List].
  Uint8List pack() {
    final packetId = id.toVarInt();
    final length = snowflake.length + packetId.length + (hasBody ? body!.length : 0);

    final builder = BytesBuilder(copy: false);
    builder.add(length.toVarInt());
    builder.add(snowflake);
    builder.add(packetId);
    if (hasBody) builder.add(body!);
    return builder.takeBytes();
  }
}
