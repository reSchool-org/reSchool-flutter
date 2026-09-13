/// меняем пространство ключей при изменении смысла или формата школьного кеша
abstract final class SchoolCachePolicy {
  static const version = 3;
  static const namespace = 'v3';
  static const lifetime = Duration(days: 2);

  static bool isFresh(DateTime savedAt, DateTime now) {
    final age = now.difference(savedAt);
    return !age.isNegative && age < lifetime;
  }
}
