import 'package:benchmark/benchmark.dart';
import 'package:typed_data/typed_data.dart';

import 'testdata.dart';

void main(List<String> args) {
  group("Uint8Buffer", () {
    late Uint8Buffer buffer1mb;
    setUpAll(() {
      buffer1mb = Uint8Buffer(1024 * 1024 * 1);
    });

    benchmark("Uint8Buffer() (1MB)", () {
      final buffer = Uint8Buffer(1024 * 1024 * 1);
      buffer.length;
    },iterations: 10000);

    benchmark(".length (1MB)", () {
      final buffer = Uint8Buffer();
      buffer.length = 1024 * 1024 * 1;
    }, iterations: 10000);

    benchmark(".addAll() (16KB)", () {
      final buffer = Uint8Buffer();
      buffer.addAll(testData16KBytes);
    }, iterations: 10000);

    benchmark(".addAll() (32KB)", () {
      final buffer = Uint8Buffer();
      buffer.addAll(testData32KBytes);
    }, iterations: 10000);

    benchmark(".addAll() (64KB)", () {
      final buffer = Uint8Buffer();
      buffer.addAll(testData64KBytes);
    }, iterations: 10000);

    benchmark(".sublist() (1KB of 1MB)", () {
      buffer1mb.sublist(0, 1024);
    }, iterations: 10000);

    benchmark(".getRange().toList() (1KB of 1MB)", () {
      buffer1mb.getRange(0, 1024).toList();
    }, iterations: 10000);
  });
}
