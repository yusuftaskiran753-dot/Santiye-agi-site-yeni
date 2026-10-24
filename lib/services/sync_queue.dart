import 'dart:math' as math;

import '../models/models.dart';
import 'backend.dart';
import 'local_store.dart';

/// Çevrimdışıyken biriktirilen yazma işleminin türü.
enum SyncOpType {
  saveListing('İlan kaydı'),
  setListingStatus('İlan durumu'),
  deleteListing('İlan silme'),
  setMachineAvailable('Makine müsaitliği'),
  saveProfile('Profil'),
  createRequest('Teklif / talep'),
  respondRequest('Teklif yanıtı'),
  withdrawRequest('Teklif geri çekme'),
  dealAction('Anlaşma işlemi'),
  rateDeal('Puan'),
  report('Şikâyet'),
  block('Engelleme'),
  unblock('Engel kaldırma'),
  markNotificationsRead('Bildirim okundu');

  const SyncOpType(this.label);

  /// Kullanıcıya gösterilen kısa ad.
  final String label;
}

/// Gönderilmeyi bekleyen tek bir yazma işlemi.
///
/// [id] aynı zamanda sunucudaki tekrar koruması anahtarıdır (p_op_id):
/// bağlantı yanıt gelmeden koparsa işlem aynı kimlikle yeniden gönderilir ve
/// sunucu onu ikinci kez uygulamaz.
class SyncOp {
  SyncOp({
    required this.id,
    required this.type,
    required this.userId,
    required this.payload,
    DateTime? createdAt,
    this.attempts = 0,
    this.lastError = '',
  }) : createdAt = createdAt ?? DateTime.now();

  final String id;
  final SyncOpType type;
  final String userId;
  final Map<String, dynamic> payload;
  final DateTime createdAt;

  /// Sunucuya kaç kez gönderilmeye çalışıldı (ilk çevrimiçi deneme dahil).
  int attempts;
  String lastError;

  /// İşlemin ilgili olduğu kayıt (ilan, anlaşma, kullanıcı…). Arayüz "gönderilmeyi
  /// bekliyor" etiketini buna göre gösterir.
  String get refId => asString(payload['id'] ?? payload['listing_id'] ?? payload['deal_id'] ?? payload['user_id']);

  /// Aynı anahtarlı eski işlem yenisiyle birleştirilir (yalnızca son hâli gönderilir).
  /// null: birleştirilmez (sırası önemli işlemler, ör. anlaşma adımları).
  String? get mergeKey => switch (type) {
        SyncOpType.saveListing ||
        SyncOpType.setListingStatus ||
        SyncOpType.setMachineAvailable =>
          '${type.name}:${payload['kind']}:${payload['id']}',
        SyncOpType.saveProfile => 'profile',
        SyncOpType.markNotificationsRead => 'notifications',
        SyncOpType.block || SyncOpType.unblock => 'block:${payload['user_id']}',
        SyncOpType.report => 'report:${payload['target_type']}:${payload['target_id']}',
        SyncOpType.rateDeal => 'rate:${payload['deal_id']}',
        SyncOpType.createRequest => 'request:${payload['listing_id']}',
        _ => null,
      };

  Map<String, dynamic> toJson() => {
        'id': id,
        'type': type.name,
        'user_id': userId,
        'payload': payload,
        'created_at': createdAt.toUtc().toIso8601String(),
        'attempts': attempts,
        'last_error': lastError,
      };

  static SyncOp? fromJson(Map<String, dynamic> j) {
    final type = SyncOpType.values.where((t) => t.name == j['type']).firstOrNull;
    final id = asString(j['id']);
    if (type == null || id.isEmpty) return null;
    return SyncOp(
      id: id,
      type: type,
      userId: asString(j['user_id']),
      payload: asMap(j['payload']),
      createdAt: asDateOrNull(j['created_at']),
      attempts: asInt(j['attempts']),
      lastError: asString(j['last_error']),
    );
  }
}

/// Sunucuya ulaşıp kalıcı olarak reddedilen işlem.
class SyncFailure {
  const SyncFailure(this.op, this.error);

  final SyncOp op;
  final BackendException error;
}

class SyncFlushResult {
  const SyncFlushResult({this.applied = const [], this.dropped = const [], this.stoppedBy});

  /// Sunucuda uygulanan işlemler.
  final List<SyncOp> applied;

  /// Sunucunun kalıcı olarak reddettiği (ve kuyruktan çıkarılan) işlemler.
  final List<SyncFailure> dropped;

  /// Gönderim bu hata yüzünden yarıda kaldı (bağlantı yok vb.); kalan işlemler sırada bekler.
  final BackendException? stoppedBy;

  bool get complete => stoppedBy == null;
  bool get changedAnything => applied.isNotEmpty || dropped.isNotEmpty;
}

typedef SyncExecutor = Future<void> Function(SyncOp op);

/// Çevrimdışı yazma kuyruğu (outbox).
///
/// * İşlemler cihazda kalıcı saklanır; uygulama kapansa da kaybolmaz.
/// * Sırayla (ilk giren ilk çıkar) gönderilir; bağlantı hatasında durur ve
///   sıradaki işlemler beklemeye devam eder (sıra bozulmaz).
/// * Sunucunun kalıcı olarak reddettiği işlem (ör. ilan sınırı, anlaşma
///   durumu değişmiş) kuyruktan çıkarılır ve kullanıcıya bildirilir.
/// * Her işlem kullanıcı kimliğiyle saklanır; başka hesapla açılan
///   oturumda gönderilmez.
class SyncQueue {
  SyncQueue(this._store, {this.storageKey = 'sync_queue_v1', this.maxUnknownAttempts = 5});

  final LocalStore _store;
  final String storageKey;

  /// Tanınmayan (UNKNOWN) hata kaç denemeden sonra kalıcı sayılır.
  final int maxUnknownAttempts;

  List<SyncOp>? _cache;
  Future<SyncFlushResult>? _flushing;

  List<SyncOp> get _ops => _cache ??= [
        for (final m in _store.readMaps(storageKey)) ?SyncOp.fromJson(m),
      ];

  Future<void> _persist() => _store.writeMaps(storageKey, [for (final op in _ops) op.toJson()]);

  bool get isFlushing => _flushing != null;

  List<SyncOp> pendingFor(String? userId) =>
      userId == null ? const [] : List.unmodifiable(_ops.where((op) => op.userId == userId));

  int countFor(String? userId) => userId == null ? 0 : _ops.where((op) => op.userId == userId).length;

  /// [refId] kaydı için bekleyen işlem var mı?
  bool hasPendingFor(String? userId, String refId) =>
      userId != null && refId.isNotEmpty && _ops.any((op) => op.userId == userId && op.refId == refId);

  /// İşlemi sıraya ekler. Aynı kaydın son hâlini taşıyan eski işlem varsa
  /// çıkarılır ve yenisi sona eklenir (sunucuya yalnızca son hâl gider).
  Future<void> enqueue(SyncOp op) async {
    final key = op.mergeKey;
    if (key != null) {
      final old = _ops.where((o) => o.userId == op.userId && o.mergeKey == key).toList();
      for (final o in old) {
        _ops.remove(o);
        // Yeni ilan henüz sunucuya ulaşmadıysa, güncellemesi de "yeni ilan" olarak gider.
        if (op.type == SyncOpType.saveListing && o.payload['is_new'] == true) op.payload['is_new'] = true;
        // Eski işlem bir kez gönderilmeye çalışıldıysa sunucuya ulaşmış olabilir.
        op.attempts = math.max(op.attempts, o.attempts);
      }
    }
    _ops.add(op);
    await _persist();
  }

  /// [test] koşulunu sağlayan bekleyen işlemleri sıradan çıkarır (ör. silinen
  /// ilanın bekleyen güncellemeleri). Çıkarılanları döner.
  Future<List<SyncOp>> removeWhere(String? userId, bool Function(SyncOp op) test) async {
    final removed = _ops.where((op) => op.userId == userId && test(op)).toList();
    if (removed.isEmpty) return removed;
    _ops.removeWhere(removed.contains);
    await _persist();
    return removed;
  }

  Future<void> clearFor(String? userId) async {
    _ops.removeWhere((op) => op.userId == userId);
    await _persist();
  }

  /// Bu hata sonra tekrar denenince düzelebilir mi? (İşlem sırada kalır.)
  bool isRetryable(BackendException e, SyncOp op) {
    if (e.isTransient || e.code == 'RATE_LIMIT' || e.code == 'AUTH_REQUIRED') return true;
    if (e.code == 'UNKNOWN') return op.attempts < maxUnknownAttempts;
    return false;
  }

  /// Daha önce yanıtı alınamamış bir gönderim sunucuya ulaşmışsa bu hatalar
  /// "zaten yapılmış" anlamına gelir.
  static bool alreadyApplied(SyncOp op, BackendException e) {
    final retried = op.attempts > 1;
    return switch (op.type) {
      SyncOpType.deleteListing => e.code == 'NOT_FOUND',
      SyncOpType.rateDeal => e.code == 'ALREADY_RATED',
      SyncOpType.report || SyncOpType.block || SyncOpType.unblock => e.code == 'DUPLICATE',
      SyncOpType.withdrawRequest || SyncOpType.respondRequest => retried && e.code == 'NOT_PENDING',
      SyncOpType.saveListing => retried && e.code == 'DUPLICATE',
      _ => false,
    };
  }

  /// [userId] kullanıcısının bekleyen işlemlerini sırayla gönderir. Aynı anda
  /// yalnızca bir gönderim çalışır; ikinci çağrı ilkinin sonucunu bekler.
  Future<SyncFlushResult> flush(String? userId, SyncExecutor execute) {
    final running = _flushing;
    if (running != null) return running;
    final future = _flush(userId, execute);
    _flushing = future;
    return future.whenComplete(() => _flushing = null);
  }

  Future<SyncFlushResult> _flush(String? userId, SyncExecutor execute) async {
    final applied = <SyncOp>[];
    final dropped = <SyncFailure>[];
    if (userId == null) return const SyncFlushResult();
    while (true) {
      final op = _ops.where((o) => o.userId == userId).firstOrNull;
      if (op == null) break;
      op.attempts++;
      try {
        await execute(op);
        _ops.remove(op);
        applied.add(op);
        await _persist();
      } catch (error) {
        final e = BackendException.from(error);
        if (alreadyApplied(op, e)) {
          _ops.remove(op);
          applied.add(op);
          await _persist();
          continue;
        }
        op.lastError = e.code;
        if (isRetryable(e, op)) {
          await _persist();
          return SyncFlushResult(applied: applied, dropped: dropped, stoppedBy: e);
        }
        _ops.remove(op);
        dropped.add(SyncFailure(op, e));
        await _persist();
      }
    }
    return SyncFlushResult(applied: applied, dropped: dropped);
  }

  /// Ardışık başarısız denemeden sonra bekleme süresi: 5 sn, 10 sn, 20 sn … en çok 5 dk.
  static Duration backoff(int failures) {
    final seconds = 5 * math.pow(2, math.max(0, math.min(failures, 6)));
    return Duration(seconds: math.min(300, seconds.toInt()));
  }
}
