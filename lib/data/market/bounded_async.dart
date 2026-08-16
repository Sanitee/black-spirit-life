import 'dart:math' as math;

Future<List<R>> mapWithBoundedConcurrency<T, R>(
  List<T> items,
  int maximumConcurrency,
  Future<R> Function(T item) operation,
) async {
  if (items.isEmpty) {
    return <R>[];
  }
  if (maximumConcurrency <= 0) {
    throw ArgumentError.value(
      maximumConcurrency,
      'maximumConcurrency',
      'must be positive',
    );
  }

  final results = List<R?>.filled(items.length, null);
  var nextIndex = 0;

  Future<void> worker() async {
    while (nextIndex < items.length) {
      final index = nextIndex;
      nextIndex++;
      results[index] = await operation(items[index]);
    }
  }

  await Future.wait<void>(
    List<Future<void>>.generate(
      math.min(maximumConcurrency, items.length),
      (_) => worker(),
      growable: false,
    ),
  );
  return results.cast<R>();
}
