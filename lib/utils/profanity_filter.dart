import 'content_filter.dart';

/// Küfür / hakaret süzgeci (sosyal yorum ve mesajlar).
///
/// Mevcut [ContentFilter] ile aynı sözlük; sosyal katman bu adı kullanır.
class ProfanityFilter {
  const ProfanityFilter._();

  static bool isOffensive(String text) => ContentFilter.isOffensive(text);

  static String? validate(String? text) => ContentFilter.validate(text);
}
