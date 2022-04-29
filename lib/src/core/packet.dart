import 'dart:typed_data';

import 'package:chungus_protocol/src/core/data.dart';
import 'package:chungus_protocol/src/core/network.dart';
import 'package:chungus_protocol/src/core/packet_stream.dart';
import 'package:chungus_protocol/src/utils.dart';

/// The 'magic' constant that is found at the start of each packet.
const kPacketMagicValue = 0x4d555354;

abstract class Packet {
  /// The directionality of the packet.
  /// [NetworkDirectionality.incoming] means the packet will be sent from the
  /// current entity to another. [NetworkDirectionality.outgoing] means the
  /// packet has been received from another entity.
  NetworkDirectionality get directionality;

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

  /// Alias to create a new [OutgoingPacket] with the specified [id].
  /// See [OutgoingPacket.new].
  static OutgoingPacket create({
    required int id,
    Uint8List? snowflake,
    Uint8List? body,
  }) =>
      OutgoingPacket(id: id, snowflake: snowflake, body: body);

  /// Parse and construct an [IncomingPacket] from the specified Uint8List.
  /// This assumes the packet length and magic value fields have been read and
  /// stripped out of or skipped from the packet data already.
  factory Packet.parse({
    required NetworkEntity sender,
    required Uint8List bytes,
  }) {
    final bytesData = ByteData.sublistView(bytes);

    // The pointer into the bytes data that we've currently read.
    int _pointer = 0;

    // Snowflake
    if (!DataType.fixedBytes.hasId(bytesData.getUint8(_pointer++))) throw AssertionError("Invalid packet.");
    Uint8List snowflake = bytes.sublist(_pointer, _pointer + 16);
    _pointer += 16;

    // Packet ID
    if (!DataType.varInt.hasId(bytesData.getUint8(_pointer++))) throw AssertionError("Invalid packet.");
    int id = VarLengthNumbers.readVarInt(() => bytesData.getUint8(_pointer++));

    // Body
    Uint8List body = bytes.sublist(_pointer, bytes.lengthInBytes);

    return IncomingPacket(id: id, snowflake: snowflake, body: body, sender: sender);
  }

  /// Construct an [IncomingPacket] from the specified fields.
  factory Packet.from({
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
  NetworkDirectionality get directionality => NetworkDirectionality.incoming;

  /// The [NetworkEntity] that sent the packet.
  final NetworkEntity sender;

  /// The incoming packet's body.
  /// Making this a final variable will automatically implement the getter for
  /// us.
  @override
  final Uint8List? body;

  /// A utility to easily read packet data.
  late final PacketBodyInputSource reader;

  /// Initializes an [IncomingPacket] with the specified parameters. This is
  /// considered a 'lower level' form of the API exposed by [Packet], as this
  /// class would normally be constructed internally and exposed by some
  /// event stream.
  IncomingPacket({
    required int id,
    required Uint8List snowflake,
    required this.body,
    required this.sender,
  }) : super._construct(
          id: id,
          snowflake: snowflake,
        ) {
    reader = PacketBodyInputSource(packet: this);
  }
}

/// Represents an outgoing packet.
/// This additionally includes a [writer] to facilitate writing packet data
/// to the packet body, as well as a [pack] method that collects all of the
/// packet header and body values and prepends the prologue.
class OutgoingPacket extends Packet {
  @override
  NetworkDirectionality get directionality => NetworkDirectionality.outgoing;

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

  /// Initializes an [OutgoingPacket] with the specified parameters. This can
  /// be used directly as an API helper to generate outgoing packet data, but
  /// is also used under-the-hood by other convenience methods, such as the
  /// factory methods on the [Packet] class.
  ///
  /// Optionally, [snowflake] may be specified to use an explicit value. If it
  /// is not specified, a random one will be generated with a CSPRNG.
  ///
  /// Additionally, a [body] may be optionally specified. If it is, the value
  /// will be prepended to the final body of this packet. (This behavior
  /// is defined by the [PacketBodyOutputSink] constructor.
  OutgoingPacket({
    required int id,
    Uint8List? snowflake,
    Uint8List? body,
  }) : super._construct(
          id: id,
          snowflake: snowflake ?? ProtocolUtils.uuid.v4obj().toBytes(),
        ) {
    writer = PacketBodyOutputSink(body);
  }

  /// Creates an [OutgoingPacket] from the specified [IncomingPacket], such
  /// that it could be echoed back to the sender.
  ///
  /// Additionally, if [keepSnowflake] is set to `true`, the same snowflake
  /// will be used in the [OutgoingPacket] as was defined in the
  /// [IncomingPacket]. (Otherwise a new one will be generated as usual).
  OutgoingPacket.echo(IncomingPacket packet, {bool keepSnowflake = false})
      : this(
          id: packet.id,
          snowflake: keepSnowflake ? packet.snowflake : null,
          body: packet.body,
        );

  /// Collect all of the packet data, build the header, attach the prologue
  /// and the body and return the resulting entire packet as a [Uint8List].
  Uint8List pack() {
    final packetId = id.toVarInt();
    final length = 2 + snowflake.length + packetId.length + (hasBody ? body!.length : 0);

    final builder = BytesBuilder(copy: false);

    // Packet Magic Value
    builder.addByte(DataType.magic.value);
    builder.add(toBytes(4, (data) => data.setUint32(0, kPacketMagicValue)));

    // Packet Length
    builder.addByte(DataType.varInt.value);
    builder.add(length.toVarInt());

    // Packet Snowflake
    builder.addByte(DataType.fixedBytes.value);
    builder.add(snowflake);

    // Packet ID
    builder.addByte(DataType.varInt.value);
    builder.add(packetId);

    // Packet Body
    if (hasBody) builder.add(body!);
    return builder.takeBytes();
  }
}
