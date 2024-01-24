import 'dart:io';

import 'package:test/test.dart';

import 'package:mysql_connector/src/compression.dart';

import 'packet.dart';

void main() {
  group("Compressor", () {
    group("should compress with uncompressed payload", () {
      test("sample #1 - 3 bytes packet", () {
        final compressor = PacketCompressor();

        final packets = [3, 0x00, 0x00, 0, 0x0a, 0x0b, 0x0c];

        expect(
          compressor.compress(packets, 0, 0xffffffff),
          orderedEquals([
            7, 0x00, 0x00, 0, 0, 0x00, 0x00, // compressed packet header
            3, 0x00, 0x00, 0, 0x0a, 0x0b, 0x0c // standard packet
          ]),
        );
      });

      test("sample #2 - 1 byte packet", () {
        final compressor = PacketCompressor();

        final packets = [1, 0x00, 0x00, 0, 0xff];

        expect(
          compressor.compress(packets, 0, 0xffffffff),
          orderedEquals([
            5, 0x00, 0x00, 0, 0, 0x00, 0x00, // compressed packet header
            1, 0x00, 0x00, 0, 0xff // standard packet
          ]),
        );
      });

      test("sample #3 - 0 bytes packet", () {
        final compressor = PacketCompressor();

        final packets = [0, 0x00, 0x00, 0];

        expect(
          compressor.compress(packets, 0, 0xffffffff),
          orderedEquals([
            4, 0x00, 0x00, 0, 0, 0x00, 0x00, // compressed packet header
            0, 0x00, 0x00, 0 // standard packet
          ]),
        );
      });

      test("sample #4 - includes multiple packets", () {
        final compressor = PacketCompressor();

        final packets = [
          3, 0x00, 0x00, 0, 0x0a, 0x0b, 0x0c, // standard packet #1
          0, 0x00, 0x00, 1, // standard packet #2
          1, 0x00, 0x00, 2, 0xff, // standard packet #3
        ];

        expect(
          compressor.compress(packets, 0, 0xffffffff),
          orderedEquals([
            16, 0x00, 0x00, 0, 0, 0x00, 0x00, // compressed packet header
            3, 0x00, 0x00, 0, 0x0a, 0x0b, 0x0c, // standard packet #1
            0, 0x00, 0x00, 1, // standard packet #2
            1, 0x00, 0x00, 2, 0xff, // standard packet #3
          ]),
        );
      });
    });

    group("should compress with compressed payload", () {
      test("sample #1 - 3 bytes packet", () {
        final compressor = PacketCompressor();

        final packets = [3, 0x00, 0x00, 0, 0x0a, 0x0b, 0x0c];

        final p1 = zlib.encode(packets);
        final l1 = p1.length;

        expect(
          compressor.compress(packets, 0, 0),
          orderedEquals([
            l1, 0x00, 0x00, 0, 7, 0x00, 0x00, // compressed packet header
            ...p1 //
          ]),
        );
      });

      test("sample #2 - 1 byte packet", () {
        final compressor = PacketCompressor();

        final packets = [1, 0x00, 0x00, 0, 0xff];

        final p1 = zlib.encode(packets);
        final l1 = p1.length;

        expect(
          compressor.compress(packets, 0, 0),
          orderedEquals([
            l1, 0x00, 0x00, 0, 5, 0x00, 0x00, // compressed packet header
            ...p1 //
          ]),
        );
      });

      test("sample #3 - 0 bytes packet", () {
        final compressor = PacketCompressor();

        final packets = [0, 0x00, 0x00, 0];

        final p1 = zlib.encode(packets);
        final l1 = p1.length;

        expect(
          compressor.compress(packets, 0, 0),
          orderedEquals([
            l1, 0x00, 0x00, 0, 4, 0x00, 0x00, // compressed packet header
            ...p1 //
          ]),
        );
      });

      test("sample #4 - includes multiple packets", () {
        final compressor = PacketCompressor();

        final packets = [
          3, 0x00, 0x00, 0, 0x0a, 0x0b, 0x0c, // standard packet #1
          0, 0x00, 0x00, 1, // standard packet #2
          1, 0x00, 0x00, 2, 0xff, // standard packet #3
        ];

        final p1 = zlib.encode(packets);
        final l1 = p1.length;

        expect(
          compressor.compress(packets, 0, 0),
          orderedEquals([
            l1, 0x00, 0x00, 0, 16, 0x00, 0x00, // compressed packet header
            ...p1, //
          ]),
        );
      });
    });

    test(
      "should split into new packet once remaining space is insufficient when compressing",
      () {
        final compressor = PacketCompressor();

        final packets = generatePackets([
          (length: 1, sequence: 0),
          (length: 1, sequence: 1),
          (length: 1, sequence: 2),
          (length: 1, sequence: 3),
        ]);

        expect(
          compressor.compress(packets, 0, 0xffffffff, maxPacketSize: 5),
          orderedEquals([
            5, 0x00, 0x00, 0, 0, 0x00, 0x00, // compressed packet #1
            1, 0x00, 0x00, 0, 0x00,
            5, 0x00, 0x00, 1, 0, 0x00, 0x00, // compressed packet #2
            1, 0x00, 0x00, 1, 0x00,
            5, 0x00, 0x00, 2, 0, 0x00, 0x00, // compressed packet #3
            1, 0x00, 0x00, 2, 0x00,
            5, 0x00, 0x00, 3, 0, 0x00, 0x00, // compressed packet #4
            1, 0x00, 0x00, 3, 0x00,
          ]),
        );
      },
    );

    group("should decompress with uncompressed payload", () {
      test("sample #1 - 3 bytes packet", () {
        final compressor = PacketCompressor();

        final packets = [
          7, 0x00, 0x00, 0, 0, 0x00, 0x00, // compressed packet header,
          3, 0x00, 0x00, 0, 0x0a, 0x0b, 0x0c // standard packet
        ];

        expect(
          compressor.decompress(packets),
          orderedEquals([
            3, 0x00, 0x00, 0, 0x0a, 0x0b, 0x0c // standard packet
          ]),
        );
      });

      test("sample #2 - 1 byte packet", () {
        final compressor = PacketCompressor();

        final packets = [
          5, 0x00, 0x00, 0, 0, 0x00, 0x00, // compressed packet header,
          1, 0x00, 0x00, 0, 0xff // standard packet
        ];

        expect(
          compressor.decompress(packets),
          orderedEquals([
            1, 0x00, 0x00, 0, 0xff // standard packet
          ]),
        );
      });

      test("sample #3 - 0 bytes packet", () {
        final compressor = PacketCompressor();

        final packets = [
          4, 0x00, 0x00, 0, 0, 0x00, 0x00, // compressed packet header,
          0, 0x00, 0x00, 0 // standard packet
        ];

        expect(
          compressor.decompress(packets),
          orderedEquals([
            0, 0x00, 0x00, 0 // standard packet
          ]),
        );
      });

      test("sample #4 - includes multiple packets", () {
        final compressor = PacketCompressor();

        final packets = [
          16, 0x00, 0x00, 0, 0, 0x00, 0x00, // compressed packet header,
          3, 0x00, 0x00, 0, 0x0a, 0x0b, 0x0c, // standard packet #1
          0, 0x00, 0x00, 1, // standard packet #2
          1, 0x00, 0x00, 2, 0xff, // standard packet #3
        ];

        expect(
          compressor.decompress(packets),
          orderedEquals([
            3, 0x00, 0x00, 0, 0x0a, 0x0b, 0x0c, // standard packet #1
            0, 0x00, 0x00, 1, // standard packet #2
            1, 0x00, 0x00, 2, 0xff, // standard packet #3
          ]),
        );
      });
    });

    group("should decompress with compressed payload", () {
      test("sample #1 - 3 bytes packet", () {
        final sp1 = [
          3, 0x00, 0x00, 0, 0x0a, 0x0b, 0x0c // standard packet
        ];
        final p1 = zlib.encode(sp1);
        final l1 = p1.length;

        final compressor = PacketCompressor();

        final packets = [
          l1, 0x00, 0x00, 0, 7, 0x00, 0x00, // compressed packet header,
          ...p1 //
        ];

        expect(
          compressor.decompress(packets),
          orderedEquals(sp1),
        );
      });

      test("sample #2 - 1 byte packet", () {
        final sp1 = [
          1, 0x00, 0x00, 0, 0xff // standard packet
        ];
        final p1 = zlib.encode(sp1);
        final l1 = p1.length;

        final compressor = PacketCompressor();

        final packets = [
          l1, 0x00, 0x00, 0, 5, 0x00, 0x00, // compressed packet header,
          ...p1 //
        ];

        expect(
          compressor.decompress(packets),
          orderedEquals(sp1),
        );
      });

      test("sample #3 - 0 bytes packet", () {
        final sp1 = [
          0, 0x00, 0x00, 0 // standard packet
        ];
        final p1 = zlib.encode(sp1);
        final l1 = p1.length;

        final compressor = PacketCompressor();

        final packets = [
          l1, 0x00, 0x00, 0, 4, 0x00, 0x00, // compressed packet header,
          ...p1 //
        ];

        expect(
          compressor.decompress(packets),
          orderedEquals(sp1),
        );
      });

      test("sample #4 - includes multiple packets", () {
        final sp1 = [
          3, 0x00, 0x00, 0, 0x0a, 0x0b, 0x0c, // standard packet #1
          0, 0x00, 0x00, 1, // standard packet #2
          1, 0x00, 0x00, 2, 0xff, // standard packet #3
        ];
        final p1 = zlib.encode(sp1);
        final l1 = p1.length;

        final compressor = PacketCompressor();

        final packets = [
          l1, 0x00, 0x00, 0, 16, 0x00, 0x00, // compressed packet header,
          ...p1 //
        ];

        expect(
          compressor.decompress(packets),
          orderedEquals(sp1),
        );
      });
    });
  });
}
