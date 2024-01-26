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
          ..terminated();

        expect(builder.build(), orderedEquals([0x01, 0x00, 0x00, 0x00, 0xff]));
      });

      test("should return two packets when it includes two packets", () {
        final builder = PacketBuilder()
          ..addByte(0x01)
          ..terminated()
          ..addByte(0x02)
          ..terminated();

        expect(
            builder.build(),
            orderedEquals([
              0x01, 0x00, 0x00, 0x00, 0x01, // packet #1
              0x01, 0x00, 0x00, 0x01, 0x02, // packet #2
            ]));
      });
    });
  });
}
