import 'dart:async';

import 'package:mysql_connector/src/packet.dart';
import 'package:test/test.dart';

void main() {
  group("PacketBuilder", () {
    group(".build()", () {
      test("should return empty packet when payload is empty", () {
        final builder = PacketBuilder();

        expect(builder.build(), orderedEquals([0x00, 0x00, 0x00, 0x00]));
      });

      test("should return built packet", () {
        final builder = PacketBuilder()
          ..addByte(0xff)
          ..terminate();

        expect(builder.build(), orderedEquals([0x01, 0x00, 0x00, 0x00, 0xff]));
      });

      test("should return two packets when it includes two packets", () {
        final builder = PacketBuilder()
          ..addByte(0x01)
          ..terminate()
          ..addByte(0x02)
          ..terminate();

        expect(
            builder.build(),
            orderedEquals([
              0x01, 0x00, 0x00, 0x00, 0x01, // packet #1
              0x01, 0x00, 0x00, 0x01, 0x02, // packet #2
            ]));
      });
    });
  });

  group("PacketStreamReader", () {
    test(".next()", () async {
      final controller = StreamController<List<int>>();
      final reader = PacketStreamReader(controller.stream);

      controller.add([
        3, 0x00, 0x00, 0, 1, 2, 3 //
      ]);
      controller.add([
        3, 0x00, 0x00, 0, 3, 2, 1 //
      ]);

      expect(
        await reader.next(),
        equals([
          3, 0x00, 0x00, 0, 1, 2, 3 //
        ]),
      );
      expect(
        await reader.next(),
        equals([
          3, 0x00, 0x00, 0, 3, 2, 1 //
        ]),
      );

      reader.index -= 1;
      expect(
        await reader.next(),
        equals([
          3, 0x00, 0x00, 0, 3, 2, 1 //
        ]),
      );
    });
  });
}
