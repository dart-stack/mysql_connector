import 'package:test/test.dart';

import 'package:mysql_connector/src/utils.dart';

import 'packet.dart';

void main() {
  group("countStandardPackets()", () {
    test("no packets included in buffer", () {
      final packets = generatePackets(
        List.generate(0, (index) => (length: 1, sequence: index)),
      );

      expect(countStandardPackets(packets), equals(0));
    });

    test("1 packet included in buffer", () {
      final packets = generatePackets(
        List.generate(1, (index) => (length: 1, sequence: index)),
      );

      expect(countStandardPackets(packets), equals(1));
    });

    test("2 packets included in buffer", () {
      final packets = generatePackets(
        List.generate(2, (index) => (length: 1, sequence: index)),
      );

      expect(countStandardPackets(packets), equals(2));
    });

    test("3 packets included in buffer", () {
      final packets = generatePackets(
        List.generate(3, (index) => (length: 1, sequence: index)),
      );

      expect(countStandardPackets(packets), equals(3));
    });

    test("4 packets included in buffer", () {
      final packets = generatePackets(
        List.generate(4, (index) => (length: 1, sequence: index)),
      );

      expect(countStandardPackets(packets), equals(4));
    });

    test("5 packets included in buffer", () {
      final packets = generatePackets(
        List.generate(5, (index) => (length: 1, sequence: index)),
      );

      expect(countStandardPackets(packets), equals(5));
    });
  });

  group("countCompressedPackets()", () {
    test("no packets included in buffer", () {
      final packets = generatePackets(
        List.generate(0, (index) => (length: 1, sequence: index)),
        compressed: true,
      );

      expect(countCompressedPackets(packets), equals(0));
    });

    test("1 packet included in buffer", () {
      final packets = generatePackets(
        List.generate(1, (index) => (length: 1, sequence: index)),
        compressed: true,
      );

      expect(countCompressedPackets(packets), equals(1));
    });

    test("2 packets included in buffer", () {
      final packets = generatePackets(
        List.generate(2, (index) => (length: 1, sequence: index)),
        compressed: true,
      );

      expect(countCompressedPackets(packets), equals(2));
    });

    test("3 packets included in buffer", () {
      final packets = generatePackets(
        List.generate(3, (index) => (length: 1, sequence: index)),
        compressed: true,
      );

      expect(countCompressedPackets(packets), equals(3));
    });

    test("4 packets included in buffer", () {
      final packets = generatePackets(
        List.generate(4, (index) => (length: 1, sequence: index)),
        compressed: true,
      );

      expect(countCompressedPackets(packets), equals(4));
    });

    test("5 packets included in buffer", () {
      final packets = generatePackets(
        List.generate(5, (index) => (length: 1, sequence: index)),
        compressed: true,
      );

      expect(countCompressedPackets(packets), equals(5));
    });
  });

  group("Bitmap", () {
    test(".build()", () {
      final bitmap = Bitmap.build([
        true, false, false, true, false, false, false, true, //
        true, false, false, false, false, false, false, false, //
        true, false, false, false, false, false, false, false, //
      ]);

      expect(bitmap.at(0), isTrue);
      expect(bitmap.at(3), isTrue);
      expect(bitmap.at(7), isTrue);
      expect(bitmap.at(8), isTrue);
      expect(bitmap.at(16), isTrue);
    });

    test(".at()", () {
      final bitmap = Bitmap.from([0x89, 0x01, 0x01]);

      expect(bitmap.at(0), isTrue);
      expect(bitmap.at(3), isTrue);
      expect(bitmap.at(7), isTrue);
      expect(bitmap.at(8), isTrue);
      expect(bitmap.at(16), isTrue);
    });
  });
}
