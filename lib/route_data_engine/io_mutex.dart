part of 'engine.dart';

/// Serialized write queue that collapses high-frequency save requests into a
/// single disk operation. Uses a [Future] chain as a mutex to guarantee that
/// at most one I/O operation is in flight at any time, and an atomic
/// write-to-tmp + rename strategy to prevent file corruption on power loss.
///
/// Designed to be used as a private field of [RouteDataEngine]. Accepts raw
/// [Uint8List] snapshots — has no knowledge of the engine's internals.
class _IoMutex {
  Future<void> _chain = Future.value();
  Uint8List? _pendingSnapshot;
  String? _pendingPath;
  bool _scheduled = false;

  /// Schedules a write of [snapshot] to [path]. If a write is already in
  /// progress, the snapshot is buffered and will be flushed once the current
  /// operation completes — intermediate snapshots are silently discarded.
  @pragma('vm:prefer-inline')
  void enqueue(Uint8List snapshot, String path) {
    _pendingPath = path;
    _pendingSnapshot = snapshot;

    if (!_scheduled) {
      _scheduled = true;
      _chain = _chain.then((_) => _process());
    }
  }

  /// Returns a [Future] that completes when all enqueued writes have been
  /// flushed to disk. Call before moving or deleting the target file.
  @pragma('vm:prefer-inline')
  Future<void> flush() => _chain;

  Future<void> _process() async {
    while (_pendingSnapshot != null) {
      final bytes = _pendingSnapshot!;
      final path = _pendingPath!;
      _pendingSnapshot = null;

      try {
        final tmp = File('$path.tmp');
        await tmp.writeAsBytes(bytes, flush: true);
        await tmp.rename(path);
      } on FileSystemException catch (e) {
        print('[_IoMutex] write failed for $path: $e');
      }
    }

    _scheduled = false;
  }
}
