import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:slim_protocol/slim_protocol.dart';
import 'package:slim_protocol/src/core/packet.dart';
import 'package:slim_protocol/src/core/signal.dart';

void readInput({String prompt = '>', required SLIMClient client, required Function(String) onData}) {
  Completer<void> _waitForAck = Completer();
  bool _waitingForAck = false;

  client.signalStream.listen((IncomingSignal signal) {
    if (signal.type == SignalType.acknowledged) {
      Future.delayed(Duration(milliseconds: 1)).then((_) {
        _waitForAck.complete();
        _waitForAck = Completer();
      });
    }
  });

  stdout.write("$prompt ");
  stdin.transform(utf8.decoder).transform(const LineSplitter()).listen((String line) {
    if (_waitingForAck) return;
    _waitingForAck = true;

    onData(line);
    _waitForAck.future.whenComplete(() {
      stdout.write("$prompt ");
      _waitingForAck = false;
    });
  });
}

/// Client example for SLIM Protocol.
/// Refer to `server.dart` for an example server.
Future<void> main() async {
  var client = SLIMClient(server: NetworkEntity(port: 5895));
  await client.connect();

  client.listen((IncomingPacket packet) {
    print("");
    print("📦 -- Incoming Packet: #${packet.id}");
    print(packet.reader.readString());
    print("-- End of Packet");
    print("");
  });

  client.send(
    OutgoingPacket(id: 0x01)..writer.writeString("Hello, world!"),
  );

  client.send(
    OutgoingPacket(id: 0x02)..writer.writeString("Lorem ipsum dolor sit amet. " * 36),
  );

  client.send(
    OutgoingPacket(id: 0x03)
      ..writer.writeString("Hello, world!")
      ..writer.writeByte(0x42),
  );

  // Optionally: uncomment to manually provide data.
  // readInput(
  //   onData: (String line) {
  //     client.send(OutgoingPacket(id: 0x01)..writer.writeString(line));
  //   },
  //   client: client,
  // );
}
