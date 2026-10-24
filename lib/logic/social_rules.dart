import '../models/social.dart';
import '../models/trade.dart';
import '../utils/profanity_filter.dart';

class CommentReview {
  const CommentReview({required this.verdict, required this.status, this.message = ''});

  final CommentVerdict verdict;
  final ModerationStatus status;
  final String message;
}

class SocialRules {
  const SocialRules._();

  static bool inFeed({
    required List<WorkSector> mySectors,
    required Set<String> following,
    required String authorId,
    required List<WorkSector> postSectors,
    required String myId,
  }) {
    if (authorId == myId) return true;
    if (following.contains(authorId)) return true;
    return TradeCatalog.sectorsMeet(mySectors, postSectors);
  }

  static CommentReview reviewComment({
    required String text,
    required bool negative,
    required bool workedTogether,
    required String evidenceNote,
  }) {
    if (ProfanityFilter.isOffensive(text)) {
      return const CommentReview(
        verdict: CommentVerdict.filtered,
        status: ModerationStatus.rejected,
        message: 'Küfürlü veya hakaret içeren yorum yayınlanmaz.',
      );
    }
    if (negative && (!workedTogether || evidenceNote.trim().isEmpty)) {
      return const CommentReview(
        verdict: CommentVerdict.pendingModeration,
        status: ModerationStatus.pending,
        message:
            'Kanıtsız olumsuz yorum yayına çıkmaz. Birlikte çalıştığınıza dair not (fotoğraf / sözleşme açıklaması) ekleyin; kayıt incelemeye alınır.',
      );
    }
    return const CommentReview(
      verdict: CommentVerdict.published,
      status: ModerationStatus.published,
    );
  }

  static String? reviewMessage(String text) {
    if (ProfanityFilter.isOffensive(text)) {
      return 'Küfürlü mesaj gönderilemez.';
    }
    return null;
  }

  static bool canBid({
    required Tender tender,
    required TradeProfession profession,
    required String myId,
  }) {
    if (tender.status != TenderStatus.open) return false;
    if (tender.ownerId == myId) return false;
    return tender.allows(profession);
  }
}
