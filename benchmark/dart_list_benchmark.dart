import 'package:benchmark/benchmark.dart';

import 'testdata.dart';

void main(List<String> args) {
  group("List", () {
    benchmark(".addAll() (16KB)", () {
      final buffer = <int>[];
      buffer.addAll(testData16KBytes);
    }, iterations: 10000);

    benchmark(".addAll() (32KB)", () {
      final buffer = <int>[];
      buffer.addAll(testData32KBytes);
    }, iterations: 10000);

    benchmark(".addAll() (64KB)", () {
      final buffer = <int>[];
      buffer.addAll(testData64KBytes);
    }, iterations: 10000);
  });
}
