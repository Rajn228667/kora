import 'dart:async';

/// Trailing-edge debouncer for search inputs.
class Debouncer {
  Debouncer(this.delay);

  final Duration delay;
  Timer? _timer;

  void run(void Function() action) {
    _timer?.cancel();
    _timer = Timer(delay, action);
  }

  void cancel() => _timer?.cancel();

  void dispose() => _timer?.cancel();
}

/// Throttles a repeating action (e.g. courier GPS posting) to at most
/// one call per [interval].
class Throttler {
  Throttler(this.interval);

  final Duration interval;
  DateTime? _last;

  bool get ready =>
      _last == null || DateTime.now().difference(_last!) >= interval;

  void mark() => _last = DateTime.now();
}
