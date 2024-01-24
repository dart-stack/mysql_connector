import 'dart:async';

class QueueLock {
  Completer<void>? _semaphore;

  final List<Completer<void>> _waitQueue = [];

  QueueLock();

  FutureOr<void> get semaphore => _semaphore?.future;

  bool get locked => _semaphore != null;

  Future<void> _queueUpAndWait() async {
    final token = Completer.sync();

    _waitQueue.add(token);
    await token.future;
  }

  Future<void> acquire() async {
    if (_semaphore != null || _waitQueue.isNotEmpty) {
      await _queueUpAndWait();
    }

    assert(_semaphore == null);
    _semaphore = Completer.sync();
  }

  void _releaseSema() {
    if (_semaphore != null) {
      _semaphore!.complete();
      _semaphore = null;
    }
  }

  void _awakeNext() {
    if (_waitQueue.isNotEmpty) {
      _waitQueue.removeAt(0).complete();
    }
  }

  void release() {
    assert(_semaphore != null);

    _releaseSema();
    _awakeNext();
  }

  void _dismissWaitQueue(Object error) {
    for (; _waitQueue.isNotEmpty;) {
      final token = _waitQueue.removeAt(0);
      token.completeError(error);
    }
  }

  void reset([Object? error]) {
    _releaseSema();
    _dismissWaitQueue(error ?? LockResetException());
  }

  @override
  String toString() {
    return "${locked ? "locked" : "unlocked"}, ${_waitQueue.isEmpty ? "no waits" : "${_waitQueue.length} waits"}";    
  }
}

class LockResetException implements Exception {}
