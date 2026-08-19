sealed class AppFailure implements Exception {
  const AppFailure(this.message);

  final String message;
}

final class ValidationFailure extends AppFailure {
  const ValidationFailure(super.message);
}

final class StorageFailure extends AppFailure {
  const StorageFailure(super.message);
}
