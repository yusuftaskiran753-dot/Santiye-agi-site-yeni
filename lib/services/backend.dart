import 'dart:async';

import '../models/models.dart';

/// Sunucu veya cihaz hatası. [code] sunucudaki hata kodlarıyla aynıdır.
class BackendException implements Exception {
  const BackendException(this.code, [this.detail = '']);

  final String code;
  final String detail;

  static const List<String> knownCodes = [
    'AUTH_REQUIRED',
    'PHONE_REQUIRED',
    'NOT_FOUND',
    'OWN_LISTING',
    'NOT_AVAILABLE',
    'BLOCKED',
    'LOCKED',
    'RATE_LIMIT',
    'LISTING_LIMIT',
    'NOT_PENDING',
    'BAD_INPUT',
    'BAD_STATE',
    'WAITING_OTHER',
    'FORBIDDEN',
    'ALREADY_RATED',
    'NO_CREDITS',
    'QUOTA',
    'DEMO_ITEM',
    'NETWORK',
    'SERVER',
    'DUPLICATE',
    'SYNC_PENDING',
    'STORE',
    'CONFIG',
    'SMS_UNAVAILABLE',
    'LOCATION_NOT_SHARING',
  ];

  /// Kullanıcıya gösterilecek Türkçe açıklama.
  String get message => switch (code) {
    'AUTH_REQUIRED' => 'Oturumunuz sona ermiş. Uygulamayı yeniden açın.',
    'PHONE_REQUIRED' => 'Devam etmek için telefon numaranızı doğrulayın.',
    'NOT_FOUND' => 'Kayıt bulunamadı. Silinmiş veya yayından kalkmış olabilir.',
    'OWN_LISTING' => 'Kendi ilanınıza teklif veremezsiniz.',
    'NOT_AVAILABLE' => 'Bu ilan artık yayında değil.',
    'BLOCKED' => 'Bu kullanıcıyla işlem yapılamıyor (engelleme var).',
    'LOCKED' => 'Önce iletişim hakkını açmanız gerekiyor.',
    'RATE_LIMIT' =>
      'Kısa sürede çok fazla işlem yaptınız. Biraz sonra tekrar deneyin.',
    'LISTING_LIMIT' =>
      'Ücretsiz üyelikte aynı anda yayında tutabileceğiniz ilan sınırına ulaştınız.',
    'NOT_PENDING' => 'Bu talep zaten yanıtlanmış.',
    'BAD_INPUT' =>
      detail.isNotEmpty ? detail : 'Bilgileri kontrol edip tekrar deneyin.',
    'BAD_STATE' => 'Bu işlem anlaşmanın şu anki durumunda yapılamaz.',
    'LOCATION_NOT_SHARING' => 'Konum paylaşımı bitti. Yeniden başlatmak için süre seçin.',
    'WAITING_OTHER' => 'Karşı tarafın onayı bekleniyor.',
    'FORBIDDEN' => 'Bu işlem için yetkiniz yok.',
    'ALREADY_RATED' => 'Bu anlaşma için zaten puan verdiniz.',
    'NO_CREDITS' => 'Yeterli krediniz yok.',
    'QUOTA' => 'Bu ayki ücretsiz iletişim haklarınız bitti.',
    'DEMO_ITEM' =>
      'Bu bir örnek ilandır; gerçek bir firma değildir. Gerçek ilanlarla devam edin.',
    'NETWORK' =>
      'İnternet bağlantısı yok veya zayıf. Bağlantınızı kontrol edip tekrar deneyin.',
    'SERVER' => 'Sunucu şu an yanıt vermiyor. Birazdan tekrar deneyin.',
    'DUPLICATE' => 'Bu kayıt zaten var.',
    'SYNC_PENDING' =>
      'Bu kayıt henüz sunucuya gönderilmedi. Bağlantı gelince tekrar deneyin.',
    'STORE' => 'Mağaza işlemi tamamlanamadı.',
    'CONFIG' =>
      detail.isNotEmpty
          ? detail
          : 'Bu hizmet henüz etkinleştirilmedi. Lütfen daha sonra tekrar deneyin.',
    'SMS_UNAVAILABLE' =>
      'Doğrulama kodu gönderilemedi. Lütfen biraz sonra yeniden deneyin.',
    _ => 'Bir sorun oluştu. Lütfen tekrar deneyin.',
  };

  /// Bağlantı veya sunucu kaynaklı, sonra tekrar denenince düzelebilecek hata.
  bool get isTransient => code == 'NETWORK' || code == 'SERVER';

  /// Herhangi bir hatayı [BackendException]'a çevirir.
  static BackendException from(Object error) {
    if (error is BackendException) return error;
    if (error is TimeoutException) return const BackendException('NETWORK');
    final text = error.toString();
    for (final code in knownCodes) {
      if (text.contains(code)) return BackendException(code);
    }
    final lower = text.toLowerCase();
    if (lower.contains('socketexception') ||
        lower.contains('failed host lookup') ||
        lower.contains('clientexception') ||
        lower.contains('handshakeexception') ||
        lower.contains('connection closed') ||
        lower.contains('connection refused') ||
        lower.contains('connection reset') ||
        lower.contains('network is unreachable') ||
        lower.contains('timed out') ||
        lower.contains('timeoutexception') ||
        lower.contains('network')) {
      return const BackendException('NETWORK');
    }
    return BackendException('UNKNOWN', _debugDetail(text));
  }

  /// Sunucu (PostgreSQL / PostgREST) hata kodunu uygulama koduna çevirir.
  /// [message] sunucu fonksiyonlarının fırlattığı kodu (ör. LISTING_LIMIT) içerebilir.
  static BackendException fromServer(String? sqlState, String message) {
    for (final code in knownCodes) {
      if (message.contains(code)) return BackendException(code);
    }
    final state = sqlState ?? '';
    switch (state) {
      case '23505':
        return const BackendException('DUPLICATE');
      case '23502' ||
          '23514' ||
          '22P02' ||
          '22001' ||
          '22003' ||
          '22007' ||
          '22008':
        return const BackendException('BAD_INPUT');
      case '42501':
        return const BackendException('FORBIDDEN');
      case 'PGRST301' || 'PGRST302' || 'PGRST303':
        return const BackendException('AUTH_REQUIRED');
      case 'PGRST116':
        return const BackendException('NOT_FOUND');
      case '57014' ||
          '53300' ||
          '40001' ||
          '40P01' ||
          '08006' ||
          '08001' ||
          'PGRST000' ||
          'PGRST001' ||
          'PGRST002':
        return const BackendException('SERVER');
    }
    if (RegExp(r'^5\d\d$').hasMatch(state)) {
      return const BackendException('SERVER');
    }
    final fallback = from(message);
    return fallback.code == 'UNKNOWN'
        ? BackendException('UNKNOWN', _debugDetail('$state $message'))
        : fallback;
  }

  /// Bilinmeyen hatanın kısa teknik özeti (yalnızca geliştirme kaydı içindir; kullanıcıya gösterilmez).
  static String _debugDetail(String text) =>
      text.length > 200 ? text.substring(0, 200) : text;

  @override
  String toString() =>
      'BackendException($code${detail.isEmpty ? '' : ': $detail'})';
}

/// Arka planda olan bir değişiklik (yeni bildirim, karşı tarafın işlemi).
class BackendEvent {
  const BackendEvent(this.type, [this.message = '']);

  /// notification · refresh
  final String type;
  final String message;
}

/// Mağazadan gelen ve sunucuda doğrulanacak satın alma.
class StoreClaim {
  const StoreClaim({
    required this.platform,
    required this.productId,
    required this.token,
    this.isSubscription = false,
  });

  /// android · ios
  final String platform;
  final String productId;

  /// Android: purchaseToken · iOS: transactionId
  final String token;
  final bool isSubscription;

  Map<String, dynamic> toJson() => {
    'platform': platform,
    'productId': productId,
    'token': token,
    'isSubscription': isSubscription,
  };

  factory StoreClaim.fromJson(Map<String, dynamic> j) => StoreClaim(
    platform: asString(j['platform']),
    productId: asString(j['productId']),
    token: asString(j['token']),
    isSubscription: asBool(j['isSubscription']),
  );
}

class VerifyResult {
  const VerifyResult({
    required this.ok,
    this.error = '',
    this.premiumUntil,
    this.credits,
  });

  final bool ok;
  final String error;
  final DateTime? premiumUntil;
  final int? credits;

  /// Kalıcı ret (tekrar denemenin anlamı yok).
  bool get permanent =>
      !ok &&
      const [
        'INVALID',
        'EXPIRED',
        'REVOKED',
        'UNKNOWN_PRODUCT',
        'ACCOUNT_MISMATCH',
        'ALREADY_USED',
        'BAD_INPUT',
      ].contains(error);
}

/// Uygulamanın konuştuğu veri katmanı:
/// * [LocalBackend]: Demo modu, her şey cihazda.
/// * [SupabaseBackend]: Canlı mod, gerçek kullanıcılar arası pazar yeri.
/// * DotNetBackend: .NET 10 API üzerinden PostgreSQL veri katmanı.
///
/// [opId] alan yazma işlemleri tekrar gönderime dayanıklıdır: aynı [opId] ile
/// ikinci çağrı sunucuda yeniden uygulanmaz (çevrimdışı kuyruk bunu kullanır).
/// Yeni ilanın kimliği ([Listing.id], UUID) cihazda üretilebilir; aynı
/// kimlikle tekrar gönderilen ilan ikinci kez oluşmaz.
/// Yalnız yerel geliştirme testinde gösterilen doğrulama kodu.
abstract interface class DevelopmentPhoneCode {
  String? get developmentPhoneCode;
}

abstract interface class RuntimeAuthPolicy {
  bool get requiresPhoneVerification;
  Future<void> refreshAuthPolicy();
}

abstract interface class PasswordLoginBackend {
  bool get passwordLoginEnabled;
  Future<void> signInWithPassword(String username, String password);
}

/// Hesaba ait hafriyat sahalarının kalıcı sunucu kaydı.
abstract interface class HaulBackend {
  Future<List<HaulPoint>> fetchHaulPoints();
  Future<HaulPoint> saveHaulPoint(HaulPoint point);
  Future<void> deleteHaulPoint(String id);
}

abstract class Backend {
  bool get isLive;

  /// Oturum açmış kullanıcının kimliği.
  String? get userId;
  bool get hasSession;

  /// Arka plan değişiklikleri (bildirim, demo simülasyonu).
  Stream<BackendEvent> get events;

  Future<void> init();
  void dispose();

  // ───────────── Oturum ─────────────
  Future<void> signInAnonymously();
  Future<void> sendPhoneCode(String phoneE164);
  Future<void> verifyPhoneCode(String phoneE164, String code);
  Future<void> signOut();
  Future<void> deleteAccount();

  // ───────────── Profil ─────────────
  Future<PublicProfile?> fetchMyProfile();
  Future<String> fetchMyPhone();
  Future<PublicProfile> saveMyProfile({
    required String name,
    required String company,
    required UserRole role,
    required String city,
    required String phone,
  });
  Future<PublicProfile?> fetchProfile(String userId);
  Future<List<PublicProfile>> fetchProfiles(List<String> ids);
  Future<List<Rating>> fetchRatingsFor(String userId);
  Future<Set<String>> fetchMyRatedDealIds();
  Future<UsageInfo> fetchUsage();

  // ───────────── İlanlar ─────────────
  /// Pazardaki ilanlar + kullanıcının kendi ilanları (her durumda).
  Future<List<Listing>> fetchListings(ListingKind kind);
  Future<Listing> saveListing(Listing listing, {required bool isNew});
  Future<void> setListingStatus(
    ListingKind kind,
    String id,
    ListingStatus status,
  );
  Future<void> deleteListing(ListingKind kind, String id);
  Future<void> setMachineAvailable(String id, bool available);
  Future<DateTime> boostListing(
    ListingKind kind,
    String id,
    BoostOption option,
  );

  // ───────────── İletişim hakkı ─────────────
  /// "tür:kimlik" biçiminde açılmış ilanlar.
  Future<Set<String>> fetchUnlockedKeys();
  Future<UnlockResult> unlock(
    ListingKind kind,
    String id, {
    bool useCredit = false,
  });

  /// [refType]: ilan türü adı · request · deal
  Future<ContactInfo> contactFor(String refType, String refId);

  // ───────────── Teklif / talep ─────────────
  Future<List<TradeRequest>> fetchRequests();
  Future<TradeRequest> createRequest(RequestDraft draft, {String? opId});

  /// Kabulde oluşan anlaşmanın kimliğini döner.
  Future<String?> respondRequest(
    String id, {
    required bool accept,
    String? opId,
  });
  Future<void> withdrawRequest(String id);

  // ───────────── Anlaşmalar ─────────────
  Future<List<Deal>> fetchDeals();
  Future<Deal> createDeal(DealDraft draft);
  Future<Deal> joinDeal(String code);
  Future<Deal> dealAction(
    String id,
    DealAction action, {
    int? index,
    String? note,
    String? opId,
  });
  Future<void> rateDeal(
    String dealId,
    int stars,
    String comment, {
    String? opId,
  });

  // ───────────── Güvenlik ─────────────
  Future<void> report(
    String targetType,
    String targetId,
    String reason,
    String note,
  );
  Future<Set<String>> fetchBlockedIds();
  Future<void> block(String userId);
  Future<void> unblock(String userId);

  // ───────────── Bildirimler ─────────────
  Future<List<AppNotification>> fetchNotifications();
  Future<void> markNotificationsRead();

  // ───────────── Mağaza ─────────────
  Future<VerifyResult> verifyPurchase(StoreClaim claim);

  /// Demo modunda verileri sıfırlar (canlı modda bir şey yapmaz).
  Future<void> resetLocalData();
}
