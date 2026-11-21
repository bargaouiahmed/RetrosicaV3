import 'dart:async';

class DownloadCancellation {
  bool _isCancelled = false;
  Future<void> Function()? _abort;

  bool get isCancelled => _isCancelled;

  void cancel() {
    if (_isCancelled) return;
    _isCancelled = true;
    final abort = _abort;
    if (abort != null) _runAbort(abort);
  }

  void attach(Future<void> Function() abort) {
    _abort = abort;
    if (_isCancelled) _runAbort(abort);
  }

  void detach() => _abort = null;

  void _runAbort(Future<void> Function() abort) {
    unawaited(abort().catchError((Object _) {}));
  }

  void throwIfCancelled() {
    if (_isCancelled) throw const DownloadCancelledException();
  }
}

class DownloadCancelledException implements Exception {
  const DownloadCancelledException();

  @override
  String toString() => 'Download cancelled.';
}
