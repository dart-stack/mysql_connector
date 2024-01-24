import 'dart:async';

import 'package:test/test.dart';

import 'package:mysql_connector/src/lock.dart';

void main() {
  group("QueueLock", () {
    Future<void> waitAndEnqueue(
        QueueLock mutex, List<int> queue, int token) async {
      await mutex.acquire();
      queue.add(token);
      mutex.release();
    }

    test("should queue up waiters", () async {
      final mutex = QueueLock();

      final queue = <int>[];

      {
        await mutex.acquire();
        final op1 = waitAndEnqueue(mutex, queue, 2);
        queue.add(1);
        mutex.release();

        final op2 = waitAndEnqueue(mutex, queue, 3);

        await mutex.acquire();
        final op3 = waitAndEnqueue(mutex, queue, 5);
        queue.add(4);
        mutex.release();

        await Future.wait([op1, op2, op3]);
      }

      expect(queue, orderedEquals([1, 2, 3, 4, 5]));
    });
  });
}
