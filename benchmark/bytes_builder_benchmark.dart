import 'dart:typed_data';

import 'package:benchmark/benchmark.dart';

import 'testdata.dart';

void main(List<String> args) {
  group("BytesBuilder (no copy)", () {
    benchmark(".add() (16KB)", () {
      final buffer = BytesBuilder(copy: false);
      buffer.add(testData16KBytes);
    }, iterations: 10000);

    benchmark(".add() & .toBytes() (16KB)", () {
      final buffer = BytesBuilder(copy: false);
      buffer.add(testData16KBytes);
      buffer.toBytes();
    }, iterations: 10000);

    benchmark(".add() (32KB)", () {
      final buffer = BytesBuilder(copy: false);
      buffer.add(testData32KBytes);
    }, iterations: 10000);

    benchmark(".add() & .toBytes() (32KB)", () {
      final buffer = BytesBuilder(copy: false);
      buffer.add(testData32KBytes);
      buffer.toBytes();
    }, iterations: 10000);

    benchmark(".add() (64KB)", () {
      final buffer = BytesBuilder(copy: false);
      buffer.add(testData64KBytes);
    }, iterations: 10000);

    benchmark(".add() & .toBytes() (64KB)", () {
      final buffer = BytesBuilder(copy: false);
      buffer.add(testData64KBytes);
      buffer.toBytes();
    }, iterations: 10000);
  });

  group("BytesBuilder (copy)", () {
    benchmark(".add() (16KB)", () {
      final buffer = BytesBuilder(copy: true);
      buffer.add(testData16KBytes);
    }, iterations: 10000);

    benchmark(".add() & .toBytes() (16KB)", () {
      final buffer = BytesBuilder(copy: true);
      buffer.add(testData16KBytes);
      buffer.toBytes();
    }, iterations: 10000);

    benchmark(".add() (32KB)", () {
      final buffer = BytesBuilder(copy: true);
      buffer.add(testData32KBytes);
    }, iterations: 10000);

    benchmark(".add() & .toBytes() (32KB)", () {
      final buffer = BytesBuilder(copy: true);
      buffer.add(testData32KBytes);
      buffer.toBytes();
    }, iterations: 10000);

    benchmark(".add() (64KB)", () {
      final buffer = BytesBuilder(copy: true);
      buffer.add(testData64KBytes);
    }, iterations: 10000);

    benchmark(".add() & .toBytes() (64KB)", () {
      final buffer = BytesBuilder(copy: true);
      buffer.add(testData64KBytes);
      buffer.toBytes();
    }, iterations: 10000);
  });
}
