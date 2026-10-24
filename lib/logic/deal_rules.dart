import '../models/models.dart';
import '../config.dart';
import '../services/backend.dart';

/// Anlaşma durum makinesi: sunucudaki deal_action fonksiyonunun cihazdaki
/// birebir karşılığı.
///
/// İki yerde kullanılır:
/// * Demo modunda (LocalBackend) asıl kural olarak,
/// * Canlı modda internet yokken, işlemi gönderim sırasına almadan önce
///   kuralı cihazda denetlemek ve ekranda hemen göstermek (iyimser güncelleme) için.
///   Sunucu aynı kuralı yeniden uygular; sonuç farklıysa sunucununki geçerlidir.
abstract final class DealRules {
  /// [row] anlaşmanın JSON kaydı. İşlem kurala uymuyorsa [BackendException]
  /// fırlatır (BAD_STATE, BAD_INPUT, FORBIDDEN, WAITING_OTHER).
  static Map<String, dynamic> apply(
    Map<String, dynamic> row, {
    required String actor,
    required String actorName,
    required DealAction action,
    required DateTime now,
    int? index,
    String? note,
  }) {
    final d = Deal.fromJson(row);
    final at = now.toUtc().toIso8601String();
    final isC = d.customerId == actor;
    final isP = d.providerId == actor;
    if (!(isC || isP || d.createdBy == actor)) throw const BackendException('FORBIDDEN');
    final solo = d.createdBy == actor && (d.customerId == null || d.providerId == null);
    final canC = isC || (solo && d.customerId == null);
    final canP = isP || (solo && d.providerId == null);
    final cleanNote = (note ?? '').trim();
    final shortNote = cleanNote.length > 300 ? cleanNote.substring(0, 300) : cleanNote;
    final milestones = asMapList(row['milestones']);
    var status = d.status;
    DealStatus? prev = d.prevStatus;
    var text = '';

    void requireState(bool ok) {
      if (!ok) throw const BackendException('BAD_STATE');
    }

    bool validIndex() => index != null && index >= 0 && index < milestones.length;

    switch (action) {
      case DealAction.confirm:
        requireState(d.status == DealStatus.pending);
        if (d.createdBy == actor && !solo) throw const BackendException('WAITING_OTHER');
        status = DealStatus.active;
        text = 'Anlaşma onaylandı';
      case DealAction.reject:
        requireState(d.status == DealStatus.pending && d.createdBy != actor);
        status = DealStatus.cancelled;
        text = 'Anlaşma reddedildi';
      case DealAction.cancel:
        requireState(const [DealStatus.pending, DealStatus.active, DealStatus.disputed].contains(d.status));
        if (AppConfig.usesDotNet && !solo && d.status != DealStatus.pending) {
          if (d.cancelRequestedBy == actor) throw const BackendException('WAITING_OTHER');
          if (d.cancelRequestedBy == null) {
            row = {...row, 'cancel_requested_by': actor};
            text = 'İptal talebi gönderildi; karşı tarafın onayı bekleniyor';
          } else {
            row = {...row, 'cancel_requested_by': null};
            status = DealStatus.cancelled;
            text = 'Karşılıklı onayla iptal edildi';
          }
        } else {
          status = DealStatus.cancelled;
          text = 'Anlaşma iptal edildi${shortNote.isEmpty ? '' : ': $shortNote'}';
        }
      case DealAction.deliver:
        requireState(canP && d.status == DealStatus.active);
        status = DealStatus.delivered;
        text = 'İş tamamlandı / teslim edildi olarak bildirildi';
      case DealAction.complete:
        requireState(canC && (d.status == DealStatus.active || d.status == DealStatus.delivered));
        status = DealStatus.completed;
        text = 'Teslim alındı, anlaşma tamamlandı';
      case DealAction.dispute:
        requireState((isC || isP || solo) && (d.status == DealStatus.active || d.status == DealStatus.delivered));
        prev = d.status;
        status = DealStatus.disputed;
        if (AppConfig.usesDotNet) row = {...row, 'disputed_by': actor};
        text = 'Sorun bildirildi${shortNote.isEmpty ? '' : ': $shortNote'}';
      case DealAction.resolve:
        requireState(d.status == DealStatus.disputed);
        if (AppConfig.usesDotNet && !solo && d.disputedBy != actor) throw const BackendException('FORBIDDEN');
        status = prev ?? DealStatus.active;
        prev = null;
        if (AppConfig.usesDotNet) row = {...row, 'disputed_by': null};
        text = 'Sorun çözüldü olarak işaretlendi';
      case DealAction.markPaid:
        if (!canC || !validIndex()) throw const BackendException('BAD_INPUT');
        requireState(d.status != DealStatus.pending && d.status != DealStatus.cancelled);
        milestones[index!] = {...milestones[index], 'paid_at': at};
        text = '${milestones[index]['title']} ödendi olarak işaretlendi (₺${trimNumber(asDouble(milestones[index]['amount']))})';
      case DealAction.markReceived:
        if (!canP || !validIndex()) throw const BackendException('BAD_INPUT');
        requireState(d.status != DealStatus.pending && d.status != DealStatus.cancelled);
        milestones[index!] = {
          ...milestones[index],
          'paid_at': milestones[index]['paid_at'] ?? at,
          'received_at': at,
        };
        text = '${milestones[index]['title']} tahsil edildi (₺${trimNumber(asDouble(milestones[index]['amount']))})';
      case DealAction.note:
        if (shortNote.isEmpty) throw const BackendException('BAD_INPUT');
        text = 'Not: $shortNote';
    }

    return {
      ...row,
      'status': status.name,
      'prev_status': prev?.name,
      'milestones': milestones,
      'log': [
        ...asMapList(row['log']),
        {'at': at, 'by': actorName, 'text': text},
      ],
      'updated_at': at,
    };
  }

  /// 28000 → "28000", 2.5 → "2,5"
  static String trimNumber(double v) =>
      v == v.roundToDouble() ? v.toInt().toString() : v.toString().replaceAll('.', ',');
}
