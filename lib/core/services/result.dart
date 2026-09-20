/// Minimal `Result<T, E>` — a discriminated union of success and failure.
///
/// Preferred over throwing exceptions in sync paths so that callers
/// MUST acknowledge the failure branch. Used by `SyncService` and
/// `SyncQueue` throughout.
///
/// Reference: docs/superpowers/specs/2026-04-17-sync-reliability.md Pillar A.
library;

sealed class Result<T, E> {
  const Result();

  /// Creates a success.
  factory Result.ok(T value) = Ok<T, E>;

  /// Creates a failure.
  factory Result.err(E error) = Err<T, E>;

  bool get isOk => this is Ok<T, E>;
  bool get isErr => this is Err<T, E>;

  /// Returns the success value, or null if this is a failure.
  T? get valueOrNull => switch (this) {
        Ok<T, E>(value: final v) => v,
        Err<T, E>() => null,
      };

  /// Returns the error, or null if this is a success.
  E? get errorOrNull => switch (this) {
        Ok<T, E>() => null,
        Err<T, E>(error: final e) => e,
      };

  /// Apply `onOk` if success, `onErr` if failure.
  R when<R>({
    required R Function(T value) ok,
    required R Function(E error) err,
  }) =>
      switch (this) {
        Ok<T, E>(value: final v) => ok(v),
        Err<T, E>(error: final e) => err(e),
      };
}

final class Ok<T, E> extends Result<T, E> {
  final T value;
  const Ok(this.value);

  @override
  String toString() => 'Ok($value)';
}

final class Err<T, E> extends Result<T, E> {
  final E error;
  const Err(this.error);

  @override
  String toString() => 'Err($error)';
}
