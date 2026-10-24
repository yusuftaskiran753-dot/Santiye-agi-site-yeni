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

  /// Yorum denetimi.
  ///
  /// [workedAnswered]: "Bu kişiyle çalıştınız mı?" sorusu yanıtlandı mı.
  /// [workedTogether]: yanıt Evet ise true. Hayır ise kanıt ([evidenceNote] veya
  /// [hasEvidencePhoto]) şarttır; yoksa yorum kaydedilmez.
  static CommentReview reviewComment({
    required String text,
    required bool negative,
    required bool workedTogether,
    required String evidenceNote,
    bool workedAnswered = true,
    bool hasEvidencePhoto = false,
  }) {
    if (text.trim().isEmpty) {
      return const CommentReview(
        verdict: CommentVerdict.filtered,
        status: ModerationStatus.rejected,
        message: 'Yorum boş olamaz.',
      );
    }
    if (ProfanityFilter.isOffensive(text) ||
        ProfanityFilter.isOffensive(evidenceNote)) {
      return const CommentReview(
        verdict: CommentVerdict.filtered,
        status: ModerationStatus.rejected,
        message: 'Küfürlü veya hakaret içeren yorum yayınlanmaz.',
      );
    }
    if (!workedAnswered) {
      return const CommentReview(
        verdict: CommentVerdict.evidenceRequired,
        status: ModerationStatus.rejected,
        message: '"Bu kişiyle çalıştınız mı?" sorusunu yanıtlayın.',
      );
    }
    final hasEvidence = evidenceNote.trim().isNotEmpty || hasEvidencePhoto;
    if (!workedTogether && !hasEvidence) {
      return const CommentReview(
        verdict: CommentVerdict.evidenceRequired,
        status: ModerationStatus.rejected,
        message:
            'Bu kişiyle çalışmadıysanız kanıt gerekir. Fotoğraf ekleyin veya '
            'nasıl bildiğinizi açıklayın.',
      );
    }
    if (negative && (!workedTogether || !hasEvidence)) {
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
    if (!tender.acceptsBids()) return false;
    if (tender.ownerId == myId) return false;
    return tender.allows(profession);
  }

  /// Teklif denetimi: tutar ve zorunlu açıklama. Sorun yoksa null döner.
  static String? reviewBid({required double amount, required String note}) {
    if (amount.isNaN || amount.isInfinite || amount <= 0) {
      return 'Teklif tutarını girin.';
    }
    final clean = note.trim();
    if (clean.isEmpty) {
      return 'Fiyat teklifi verirken açıklama yazmak zorunludur.';
    }
    if (clean.runes.length < minBidNoteLength) {
      return 'Açıklama en az $minBidNoteLength karakter olmalı '
          '(fiyata neyin dâhil olduğunu yazın).';
    }
    if (ProfanityFilter.isOffensive(clean)) {
      return 'Açıklamada küfür veya hakaret olamaz.';
    }
    return null;
  }

  /// Teklif açıklamasının en az uzunluğu.
  static const int minBidNoteLength = 15;

  /// Telefon numarası görünürlüğü.
  ///
  /// Teklif verilince numara görünmez; yalnızca ihaleyi açan, o teklif için
  /// iletişimi onaylarsa, ihalenin iki tarafı (açan + teklif sahibi) görebilir.
  static bool canRevealPhone({
    required Tender tender,
    required TenderBid bid,
    required String viewerId,
  }) {
    if (!bid.contactApproved) return false;
    return viewerId == tender.ownerId || viewerId == bid.bidderId;
  }

  /// Kararı (iletişim onayı, kazanan seçimi) yalnızca ihaleyi açan verebilir.
  static bool canDecide({required Tender tender, required String myId}) =>
      tender.ownerId == myId;

  /// "En iyi teklif": en düşük tutar; eşitlikte önce verilen.
  static TenderBid? bestBid(Iterable<TenderBid> bids) {
    TenderBid? best;
    for (final b in bids) {
      if (best == null ||
          b.amount < best.amount ||
          (b.amount == best.amount && b.createdAt.isBefore(best.createdAt))) {
        best = b;
      }
    }
    return best;
  }

  /// Engelleme denetimi: sebep ve kanıt fotoğrafı zorunlu.
  static String? reviewBlock({
    required String reason,
    required String evidencePhotoPath,
  }) {
    if (reason.trim().isEmpty) return 'Engellemek için bir sebep seçin.';
    if (evidencePhotoPath.trim().isEmpty) {
      return 'Engellemek için kanıt fotoğrafı eklemelisiniz.';
    }
    return null;
  }
}
