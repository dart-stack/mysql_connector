import 'dart:typed_data';

import 'package:benchmark/benchmark.dart';

void main(List<String> args) {
  final testData16KBytes = Uint8List.fromList(List.filled(1024 * 16, 0));
  final testData32KBytes = Uint8List.fromList(List.filled(1024 * 32, 0));
  final testData64KBytes = Uint8List.fromList(List.filled(1024 * 64, 0));

  group("List", () {
    benchmark("store & load (16kb)", () {});
  });

  group("BytesBuilder (16k bytes, no copy)", () {
    benchmark("add", () {
      final buffer = BytesBuilder(copy: false);
      buffer.add(testData16KBytes);
    }, iterations: 10000);

    benchmark("add & toBytes", () {
      final buffer = BytesBuilder(copy: false);
      buffer.add(testData16KBytes);
      buffer.toBytes();
    }, iterations: 10000);
  });

  group("BytesBuilder (16k bytes, copy)", () {
    benchmark("add", () {
      final buffer = BytesBuilder(copy: true);
      buffer.add(testData16KBytes);
    }, iterations: 10000);

    benchmark("add & toBytes", () {
      final buffer = BytesBuilder(copy: true);
      buffer.add(testData16KBytes);
      buffer.toBytes();
    }, iterations: 10000);
  });

  group("BytesBuilder (32k bytes, no copy)", () {
    benchmark("add", () {
      final buffer = BytesBuilder(copy: false);
      buffer.add(testData32KBytes);
    }, iterations: 10000);

    benchmark("add & toBytes", () {
      final buffer = BytesBuilder(copy: false);
      buffer.add(testData32KBytes);
      buffer.toBytes();
    }, iterations: 10000);
  });

  group("BytesBuilder (32k bytes, copy)", () {
    benchmark("add", () {
      final buffer = BytesBuilder(copy: true);
      buffer.add(testData32KBytes);
    }, iterations: 10000);

    benchmark("add & toBytes", () {
      final buffer = BytesBuilder(copy: true);
      buffer.add(testData32KBytes);
      buffer.toBytes();
    }, iterations: 10000);
  });

  group("BytesBuilder (64k bytes, no copy)", () {
    benchmark("add", () {
      final buffer = BytesBuilder(copy: false);
      buffer.add(testData64KBytes);
    }, iterations: 10000);

    benchmark("add & toBytes", () {
      final buffer = BytesBuilder(copy: false);
      buffer.add(testData64KBytes);
      buffer.toBytes();
    }, iterations: 10000);
  });

  group("BytesBuilder (64k bytes, copy)", () {
    benchmark("add", () {
      final buffer = BytesBuilder(copy: true);
      buffer.add(testData64KBytes);
    }, iterations: 10000);

    benchmark("add & toBytes", () {
      final buffer = BytesBuilder(copy: true);
      buffer.add(testData64KBytes);
      buffer.toBytes();
    }, iterations: 10000);
  });

  group("List (16k bytes)", () {
    benchmark("addAll", () {
      final buffer = <int>[];
      buffer.addAll(testData16KBytes);
    }, iterations: 10000);
  });

  group("List (32k bytes)", () {
    benchmark("addAll", () {
      final buffer = <int>[];
      buffer.addAll(testData32KBytes);
    }, iterations: 10000);
  });

  group("List (64k bytes)", () {
    benchmark("addAll", () {
      final buffer = <int>[];
      buffer.addAll(testData64KBytes);
    }, iterations: 10000);
  });
}
