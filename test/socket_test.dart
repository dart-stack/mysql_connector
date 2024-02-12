import 'dart:async';

import 'package:mockito/mockito.dart';
import 'package:mysql_connector/src/compression.dart';
import 'package:mysql_connector/src/sequence.dart';
import 'package:mysql_connector/src/socket.dart';
import 'package:test/test.dart';

import 'metrics.dart';
import 'session.dart';

typedef InboundPacketStreamTransformerAndDeps = (
  InboundPacketStreamTransformer,
  MockNegotiationState,
  MockMetricsCollector,
);

void main() {
  group("InboundPacketProcessor", () {
    InboundPacketStreamTransformerAndDeps createTransformerAndDeps({
      bool enableMetrics = false,
    }) {
      final negotiationState = MockNegotiationState();
      final metricsCollector = MockMetricsCollector();
      final transformer = InboundPacketStreamTransformer(
        negotiationState,
        PacketSequenceManager(),
        enableMetrics,
        metricsCollector,
        0xffffffff,
      );

      return (transformer, negotiationState, metricsCollector);
    }

    test("receiving 1 standard packet", () async {
      final deps = createTransformerAndDeps();
      final controller = StreamController<List<int>>();
      final packets = controller.stream.transform(deps.$1);

      when(deps.$2.compressionEnabled).thenReturn(false);

      controller.add([
        1, 0x00, 0x00, 0, 0xff, //
      ]);

      expect(
        await packets.take(1).toList(),
        equals([
          [1, 0x00, 0x00, 0, 0xff], //
        ]),
      );
    });

    test("receiving 2 standard packets", () async {
      final deps = createTransformerAndDeps();
      final controller = StreamController<List<int>>();
      final packets = controller.stream.transform(deps.$1);

      when(deps.$2.compressionEnabled).thenReturn(false);

      controller.add([
        1, 0x00, 0x00, 0, 0x01, //
      ]);
      controller.add([
        2, 0x00, 0x00, 1, 0x01, 0x02, //
      ]);

      expect(
        await packets.take(2).toList(),
        equals([
          [1, 0x00, 0x00, 0, 0x01], //
          [2, 0x00, 0x00, 1, 0x01, 0x02], //
        ]),
      );
    });

    test("receiving 1 compressed packet that includes 1 standard packet",
        () async {
      final deps = createTransformerAndDeps();
      final controller = StreamController<List<int>>();
      final packets = controller.stream.transform(deps.$1);

      when(deps.$2.compressionEnabled).thenReturn(true);

      controller.add([
        7, 0x00, 0x00, 0, 0, 0x00, 0x00, //
        3, 0x00, 0x00, 0, 0x01, 0x02, 0x03
      ]);

      expect(
        await packets.take(1).toList(),
        equals([
          [3, 0x00, 0x00, 0, 0x01, 0x02, 0x03], //
        ]),
      );
    });

    test("receiving 2 compressed packets that each one includes 1 standard packet",
        () async {
      final deps = createTransformerAndDeps();
      final controller = StreamController<List<int>>();
      final packets = controller.stream.transform(deps.$1);

      when(deps.$2.compressionEnabled).thenReturn(true);

      controller.add([
        7, 0x00, 0x00, 0, 0, 0x00, 0x00, //
        3, 0x00, 0x00, 0, 0x01, 0x02, 0x03
      ]);
      controller.add([
        7, 0x00, 0x00, 1, 0, 0x00, 0x00, //
        3, 0x00, 0x00, 1, 0x03, 0x02, 0x01
      ]);

      expect(
        await packets.take(2).toList(),
        equals([
          [3, 0x00, 0x00, 0, 0x01, 0x02, 0x03], //
          [3, 0x00, 0x00, 1, 0x03, 0x02, 0x01], //
        ]),
      );
    });

    test("receiving 2 compressed packets that each one includes 2 standard packets",
        () async {
      final deps = createTransformerAndDeps();
      final controller = StreamController<List<int>>();
      final packets = controller.stream.transform(deps.$1);

      when(deps.$2.compressionEnabled).thenReturn(true);

      controller.add([
        14, 0x00, 0x00, 0, 0, 0x00, 0x00, //
        3, 0x00, 0x00, 0, 0x01, 0x02, 0x03, //
        3, 0x00, 0x00, 1, 0x03, 0x02, 0x01, //
      ]);
      controller.add([
        14, 0x00, 0x00, 1, 0, 0x00, 0x00, //
        3, 0x00, 0x00, 2, 0xfa, 0xfb, 0xfc, //
        3, 0x00, 0x00, 3, 0xfc, 0xfb, 0xfa, //
      ]);

      expect(
        await packets.take(4).toList(),
        equals([
          [3, 0x00, 0x00, 0, 0x01, 0x02, 0x03], //
          [3, 0x00, 0x00, 1, 0x03, 0x02, 0x01], //
          [3, 0x00, 0x00, 2, 0xfa, 0xfb, 0xfc], //
          [3, 0x00, 0x00, 3, 0xfc, 0xfb, 0xfa], //
        ]),
      );
    });

    test(
        "receiving 2 compressed packets that include 1 truncated standard packet",
        () async {
      final deps = createTransformerAndDeps();
      final controller = StreamController<List<int>>();
      final packets = controller.stream.transform(deps.$1);

      when(deps.$2.compressionEnabled).thenReturn(true);

      controller.add([
        7, 0x00, 0x00, 0, 0, 0x00, 0x00, //
        6, 0x00, 0x00, 0, 0x01, 0x02, 0x03, //
      ]);
      controller.add([
        3, 0x00, 0x00, 1, 0, 0x00, 0x00, //
        0x04, 0x05, 0x06, //
      ]);

      expect(
        await packets.take(1).toList(),
        equals([
          [6, 0x00, 0x00, 0, 0x01, 0x02, 0x03, 0x04, 0x05, 0x06], //
        ]),
      );
    });

    test("receiving 1 compressed packet that includes truncated payload",
        () async {
      final deps = createTransformerAndDeps();
      final controller = StreamController<List<int>>();
      final packets = controller.stream.transform(deps.$1);

      when(deps.$2.compressionEnabled).thenReturn(true);

      controller.add([
        7, 0x00, 0x00, 0, 0, 0x00, 0x00, //
        3, 0x00, 0x00, //
      ]);
      controller.add([
        0, 0x01, 0x02, 0x03, //
      ]);

      expect(
        await packets.take(1).toList(),
        equals([
          [3, 0x00, 0x00, 0, 0x01, 0x02, 0x03], //
        ]),
      );
    });
  });
}
