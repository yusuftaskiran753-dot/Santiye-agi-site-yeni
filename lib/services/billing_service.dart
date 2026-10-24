import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:in_app_purchase_android/in_app_purchase_android.dart';

import '../config.dart';
import 'app_notice.dart';
import 'backend.dart';
import 'local_store.dart';
import 'purchase_verification_queue.dart';

enum PremiumPlan { monthly, yearly }

/// Google Play / App Store satın alımları: Premium abonelik ve kredi paketleri.
///
/// Uygulamanın tek gelir kanalı budur; para doğrudan mağaza hesabınıza
/// yatar. Taraflar arasındaki iş bedelleri uygulamadan geçmez.
///
/// Her satın alma, [verify] ile sunucuda (Supabase Edge Function) mağazaya
/// sorularak doğrulanır; Premium ve kredi ancak bundan sonra tanımlanır.
/// Doğrulama geçici olarak başarısız olursa (ör. internet yok) satın alma
/// cihazda saklanır; uygulama her açılışta ve bağlantı geri geldiğinde
/// yeniden dener. Kullanıcı ödediği hakkı kaybetmez.
///
/// Sonuçlar [notices] akışıyla bildirilir; uygulama bunları ekran kapansa da
/// gösterir (bkz. AppFeedback). Böylece ödeme ekranından çıktıktan sonra
/// tamamlanan bir doğrulamanın sonucu da kullanıcıya ulaşır.
class BillingService extends ChangeNotifier {
  BillingService(
    this._store, {
    required this.verify,
    required this.userId,
    this.allowDebugGrant = false,
  });

  final LocalStore _store;
  final Future<VerifyResult> Function(StoreClaim claim) verify;
  final String? Function() userId;

  /// Geliştirme sürümünde mağaza yokken satın almayı taklit et (yalnızca Demo modu).
  final bool allowDebugGrant;

  late final _queue = PurchaseVerificationQueue(_store);
  final Map<String, PurchaseDetails> _unfinished = {};
  String? _purchaseUser;

  bool storeAvailable = false;
  bool busy = false;

  /// Son başarılı satın alma (ekranların kendini kapatması için).
  String? lastSuccessProductId;

  final Map<String, ProductDetails> _products = {};
  StreamSubscription<List<PurchaseDetails>>? _sub;
  final StreamController<AppNotice> _notices =
      StreamController<AppNotice>.broadcast();

  /// Kullanıcı bir satın alma / geri yükleme başlattı; sonucu ona bildirilir.
  /// (Uygulama açılışındaki sessiz eşitlemelerde mesaj gösterilmez.)
  bool _userAction = false;
  int _inFlight = 0;
  bool _restoredSomething = false;
  Future<int>? _retrying;

  /// Kullanıcıya gösterilecek sonuçlar (başarı, bekleyen ödeme, hata).
  Stream<AppNotice> get notices => _notices.stream;

  static Set<String> get _allIds => {
    AppConfig.premiumMonthlyId,
    AppConfig.premiumYearlyId,
    ...AppConfig.creditPacks.keys,
  };

  static bool isSubscription(String productId) =>
      productId == AppConfig.premiumMonthlyId ||
      productId == AppConfig.premiumYearlyId;

  bool get _supportsIap =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);

  String get _platform =>
      defaultTargetPlatform == TargetPlatform.iOS ? 'ios' : 'android';

  /// Mağazaya hesap kimliği olarak gönderilir (yalnızca UUID; iOS bunu şart koşar).
  String? get _applicationUser {
    final id = userId();
    if (id == null) return null;
    return RegExp(r'^[0-9a-fA-F-]{36}$').hasMatch(id) ? id : null;
  }

  void _tell(AppNotice notice) {
    if (!_notices.isClosed) _notices.add(notice);
  }

  /// Yalnızca kullanıcı bir işlem başlattıysa bildirir.
  void _tellUser(AppNotice notice) {
    if (_userAction) _tell(notice);
  }

  // ───────────── Hata mesajları ─────────────

  /// Sunucu doğrulama hatasının kullanıcıya açıklaması.
  @visibleForTesting
  static String verifyErrorMessage(String code) => switch (code) {
    'NETWORK' =>
      'Ödemeniz alındı. Onay için internet bağlantısı gerekiyor; bağlantı gelince otomatik tamamlanacak.',
    'SERVER' || 'CONFIG' =>
      'Ödemeniz alındı. Mağaza onayı şu an alınamıyor; uygulama kısa süre içinde otomatik olarak tekrar deneyecek.',
    'AUTH' =>
      'Ödemeniz alındı. Oturum doğrulanamadı; uygulamayı yeniden açtığınızda otomatik tamamlanacak.',
    'EXPIRED' =>
      'Bu aboneliğin süresi dolmuş. Yenilemek için Premium planını tekrar seçebilirsiniz.',
    'REVOKED' =>
      'Bu satın alma mağaza tarafından iade edilmiş veya iptal edilmiş.',
    'ACCOUNT_MISMATCH' =>
      'Bu satın alma başka bir uygulama hesabına ait; bu hesaba tanımlanamaz.',
    'ALREADY_USED' => 'Bu satın alma daha önce başka bir hesapta kullanılmış.',
    'UNKNOWN_PRODUCT' =>
      'Bu ürün tanınmadı. Uygulamayı güncelleyip tekrar deneyin.',
    _ =>
      'Satın alma doğrulanamadı. Ücret alındıysa mağaza üzerinden iade isteyebilirsiniz.',
  };

  /// Mağaza (Google Play / App Store) hatasının kullanıcıya açıklaması.
  @visibleForTesting
  static String storeErrorMessage(IAPError? error) {
    final text = '${error?.code ?? ''} ${error?.message ?? ''}'
        .toLowerCase()
        .replaceAll(RegExp(r'[\s_.-]'), '');
    if (text.contains('alreadyowned')) {
      return 'Bu ürüne zaten sahipsiniz. "Satın alımları geri yükle" ile hesabınıza tanımlayabilirsiniz.';
    }
    if (text.contains('network') ||
        text.contains('serviceunavailable') ||
        text.contains('servicedisconnected')) {
      return 'Mağazaya bağlanılamadı. İnternet bağlantınızı kontrol edip tekrar deneyin.';
    }
    if (text.contains('billingunavailable') ||
        text.contains('notallowed') ||
        text.contains('paymentsnotallowed')) {
      return 'Bu cihazda veya hesapta uygulama içi satın alma kapalı. Mağaza ayarlarını kontrol edin.';
    }
    if (text.contains('itemunavailable') ||
        text.contains('productnotavailable')) {
      return 'Bu ürün şu an satın alınamıyor. Daha sonra tekrar deneyin.';
    }
    if (text.contains('cancel')) return 'Satın alma iptal edildi.';
    return 'Ödeme tamamlanamadı. Kartınızdan çekim yapılmadıysa tekrar deneyebilirsiniz.';
  }

  // ───────────── Fiyatlar ─────────────

  ProductDetails? product(String id) => _products[id];

  String priceOf(String id) =>
      _products[id]?.price ??
      switch (id) {
        AppConfig.premiumMonthlyId => AppConfig.fallbackMonthlyPrice,
        AppConfig.premiumYearlyId => AppConfig.fallbackYearlyPrice,
        _ => AppConfig.fallbackCreditPrices[id] ?? '',
      };

  String planPrice(PremiumPlan plan) => priceOf(
    plan == PremiumPlan.monthly
        ? AppConfig.premiumMonthlyId
        : AppConfig.premiumYearlyId,
  );

  /// Yıllık planın aylık karşılığı (mağaza fiyatından).
  String yearlyPerMonth() {
    final y = _products[AppConfig.premiumYearlyId];
    if (y == null) return '';
    final perMonth = y.rawPrice / 12;
    final symbol = y.currencySymbol.isNotEmpty ? y.currencySymbol : '₺';
    return '$symbol${perMonth.toStringAsFixed(2).replaceAll('.', ',')}';
  }

  /// Yıllık planın 12 aylık ödemeye göre tasarruf yüzdesi.
  int get yearlySavingPercent {
    final m = _products[AppConfig.premiumMonthlyId];
    final y = _products[AppConfig.premiumYearlyId];
    if (m == null || y == null || m.rawPrice <= 0) return 0;
    final percent = ((1 - y.rawPrice / (m.rawPrice * 12)) * 100).round();
    return percent.clamp(0, 99).toInt();
  }

  /// Google Play bir aboneliğin her teklifini (deneme, indirim, temel plan)
  /// ayrı ürün olarak döndürür. Temel planın tam fiyatı en yüksek olduğundan
  /// aynı kimlikte en pahalısı tutulur; ekranda indirimli fiyat görünmez.
  static ProductDetails preferBasePlan(
    ProductDetails? current,
    ProductDetails candidate,
  ) {
    if (current == null) return candidate;
    return candidate.rawPrice > current.rawPrice ? candidate : current;
  }

  // ───────────── Başlatma ─────────────

  Future<void> init() async {
    if (!_supportsIap) return;
    try {
      final iap = InAppPurchase.instance;
      storeAvailable = await iap.isAvailable();
      if (!storeAvailable) {
        notifyListeners();
        return;
      }
      _sub = iap.purchaseStream.listen(
        (purchases) => unawaited(_onPurchases(purchases)),
        onError: (Object e) {
          debugPrint('Mağaza akışı hatası: $e');
          busy = false;
          _tellUser(
            const AppNotice.error(
              'Satın alma sırasında bir hata oluştu. Lütfen tekrar deneyin.',
            ),
          );
          _userAction = false;
          notifyListeners();
        },
      );
      // Yalnız katalog metadatası: hesap, makbuz, token ve hata details yok.
      final requestedIds = _allIds;
      debugPrint(
        'Store catalog requested: ${(requestedIds.toList()..sort()).join(', ')}',
      );
      final response = await iap.queryProductDetails(requestedIds);
      debugPrint(
        'Store catalog returned: '
        '${(response.productDetails.map((p) => p.id).toList()..sort()).join(', ')}',
      );
      debugPrint(
        'Store catalog notFoundIDs: '
        '${(response.notFoundIDs.toList()..sort()).join(', ')}',
      );
      debugPrint(
        'Store catalog error: ${response.error == null ? 'none' : 'source=${response.error!.source}, code=${response.error!.code}'}',
      );
      for (final pd in response.productDetails) {
        _products[pd.id] = preferBasePlan(_products[pd.id], pd);
      }
      if (response.notFoundIDs.isNotEmpty) {
        debugPrint(
          'Mağazada bulunamayan ürünler: ${response.notFoundIDs.join(', ')}',
        );
      }
      notifyListeners();
      await retryPending();
      // Android'de abonelik durumunu sessizce eşitle (iOS şifre sorabileceği
      // için orada yalnızca kullanıcı isteyince yapılır).
      if (defaultTargetPlatform == TargetPlatform.android) {
        await iap.restorePurchases(applicationUserName: _applicationUser);
      }
    } catch (e) {
      storeAvailable = false;
      debugPrint('Mağaza bağlantısı kurulamadı: $e');
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _sub?.cancel();
    _notices.close();
    super.dispose();
  }

  // ───────────── Satın alma ─────────────

  Future<void> buyPremium(PremiumPlan plan) => _buy(
    plan == PremiumPlan.monthly
        ? AppConfig.premiumMonthlyId
        : AppConfig.premiumYearlyId,
    consumable: false,
  );

  Future<void> buyCredits(String productId) =>
      _buy(productId, consumable: true);

  Future<void> _buy(String productId, {required bool consumable}) async {
    // Çift dokunuşla iki ödeme penceresi açılmasın.
    if (busy) return;
    if (userId() == null) {
      _tell(
        const AppNotice.warning('Satın alma için önce hesabınıza giriş yapın.'),
      );
      return;
    }
    _purchaseUser = userId();
    lastSuccessProductId = null;
    _userAction = true;
    final pd = _products[productId];
    if (pd == null) {
      if (allowDebugGrant && kDebugMode) {
        busy = true;
        notifyListeners();
        try {
          final result = await verify(
            StoreClaim(
              platform: 'debug',
              productId: productId,
              token: 'debug-${DateTime.now().microsecondsSinceEpoch}',
              isSubscription: !consumable,
            ),
          );
          if (result.ok) {
            lastSuccessProductId = productId;
            _tell(
              const AppNotice.success(
                'Demo: satın alma etkinleştirildi (yalnızca geliştirme sürümünde).',
              ),
            );
          } else {
            _tell(
              AppNotice.error(
                'Demo satın alma başarısız: ${verifyErrorMessage(result.error)}',
              ),
            );
          }
        } catch (e) {
          _tell(
            AppNotice.error(
              'Demo satın alma başarısız: ${BackendException.from(e).message}',
            ),
          );
        } finally {
          busy = false;
          _userAction = false;
          notifyListeners();
        }
        return;
      }
      _tell(
        AppNotice.warning(
          storeAvailable
              ? 'Bu ürünün mağaza bilgileri şu an alınamıyor. Daha sonra tekrar deneyin.'
              : 'Mağazaya şu an ulaşılamıyor. İnternet bağlantınızı kontrol edip tekrar deneyin.',
        ),
      );
      _userAction = false;
      notifyListeners();
      return;
    }
    busy = true;
    notifyListeners();
    try {
      final param = PurchaseParam(
        productDetails: pd,
        applicationUserName: _applicationUser,
      );
      final started = consumable
          ? await InAppPurchase.instance.buyConsumable(
              purchaseParam: param,
              autoConsume: false,
            )
          : await InAppPurchase.instance.buyNonConsumable(purchaseParam: param);
      if (!started) {
        busy = false;
        _tell(
          const AppNotice.error(
            'Satın alma başlatılamadı. Lütfen tekrar deneyin.',
          ),
        );
        _userAction = false;
        notifyListeners();
      }
    } catch (e) {
      debugPrint('Satın alma başlatılamadı: $e');
      busy = false;
      _tell(AppNotice.error(_startErrorMessage(e)));
      _userAction = false;
      notifyListeners();
    }
  }

  static String _startErrorMessage(Object e) {
    final text = e.toString().toLowerCase();
    if (text.contains('alreadyowned') || text.contains('already owned')) {
      return 'Bu ürüne zaten sahipsiniz. "Satın alımları geri yükle" ile hesabınıza tanımlayabilirsiniz.';
    }
    if (text.contains('pending')) {
      return 'Önceki satın alma henüz tamamlanmadı. Biraz sonra tekrar deneyin.';
    }
    return 'Satın alma başlatılamadı. Lütfen tekrar deneyin.';
  }

  /// Kullanıcının isteğiyle önceki satın alımları geri yükler.
  Future<void> restore() async {
    if (busy) return;
    if (!storeAvailable) {
      _tell(
        const AppNotice.warning(
          'Mağazaya ulaşılamadı. Lütfen daha sonra tekrar deneyin.',
        ),
      );
      return;
    }
    _userAction = true;
    _restoredSomething = false;
    busy = true;
    notifyListeners();
    try {
      await InAppPurchase.instance.restorePurchases(
        applicationUserName: _applicationUser,
      );
      // Geri yüklenen satın alımlar akıştan birer birer gelir; doğrulamalar
      // bitene kadar (en çok ~20 sn) bekle, sonra sonucu tek mesajla bildir.
      for (var waited = 0; waited < 40; waited++) {
        await Future<void>.delayed(const Duration(milliseconds: 500));
        if (waited >= 8 && _inFlight == 0) break;
      }
      if (!_restoredSomething) {
        _tell(
          const AppNotice.info('Geri yüklenecek aktif abonelik bulunamadı.'),
        );
      }
    } catch (e) {
      debugPrint('Geri yükleme hatası: $e');
      _tell(
        const AppNotice.error(
          'Geri yükleme başarısız. İnternet bağlantınızı kontrol edip tekrar deneyin.',
        ),
      );
    } finally {
      busy = false;
      _userAction = false;
      notifyListeners();
    }
  }

  Future<void> _onPurchases(List<PurchaseDetails> purchases) async {
    for (final p in purchases) {
      try {
        switch (p.status) {
          case PurchaseStatus.pending:
            // Onay günler sürebilir (ör. havale/nakit ödeme): ekran kilitli kalmasın;
            // satın alma onaylanınca mağaza akışından tekrar gelir ve işlenir.
            busy = false;
            _tellUser(
              const AppNotice.info(
                'Ödeme onay bekliyor. Onaylanınca hakkınız otomatik tanımlanır.',
              ),
            );
            _userAction = false;
          case PurchaseStatus.purchased:
          case PurchaseStatus.restored:
            await _handleSuccess(p);
          case PurchaseStatus.error:
            busy = false;
            _tellUser(AppNotice.error(storeErrorMessage(p.error)));
            _userAction = false;
          case PurchaseStatus.canceled:
            busy = false;
            _tellUser(const AppNotice.info('Satın alma iptal edildi.'));
            _userAction = false;
        }
      } catch (e) {
        // Doğrulama sırasında beklenmeyen hata: satın alma kaybolmasın, sonra tekrar denensin.
        debugPrint('Satın alma işlenemedi: $e');
        busy = false;
        _tellUser(
          const AppNotice.warning(
            'Ödemeniz alındı ancak hesabınıza tanımlanırken sorun oluştu. Uygulama otomatik olarak tekrar deneyecek.',
          ),
        );
      }
    }
    notifyListeners();
  }

  Future<void> _handleSuccess(PurchaseDetails p) async {
    final id = p.productID;
    final sub = isSubscription(id);
    if (!sub && !AppConfig.creditPacks.containsKey(id)) {
      busy = false;
      return;
    }
    final token = _platform == 'android'
        ? p.verificationData.serverVerificationData
        : (p.purchaseID ?? '');
    if (token.isEmpty) {
      busy = false;
      _tellUser(
        const AppNotice.warning(
          'Satın alma bilgisi okunamadı. "Satın alımları geri yükle" ile tekrar deneyin.',
        ),
      );
      return;
    }
    final claim = StoreClaim(
      platform: _platform,
      productId: id,
      token: token,
      isSubscription: sub,
    );
    final owner = p.status == PurchaseStatus.restored
        ? userId()
        : (_purchaseUser ?? userId());
    if (owner == null) return;
    // Önce cihaza yaz: doğrulama sırasında uygulama kapanırsa hak kaybolmaz.
    await _queue.save(owner, claim);
    _unfinished[token] = p;
    if (owner != userId()) {
      busy = false;
      return;
    }
    _inFlight++;
    VerifyResult result;
    try {
      result = await verify(claim);
    } catch (e) {
      result = VerifyResult(
        ok: false,
        error: BackendException.from(e).isTransient ? 'NETWORK' : 'SERVER',
      );
    } finally {
      _inFlight--;
    }
    busy = false;
    if (result.ok) {
      await _queue.remove(owner, claim);
      await _completeVerified(claim);
      if (owner != userId()) return;
      lastSuccessProductId = id;
      if (p.status == PurchaseStatus.restored) _restoredSomething = true;
      final notice = AppNotice.success(
        sub
            ? (p.status == PurchaseStatus.restored
                  ? 'Aboneliğiniz geri yüklendi.'
                  : 'Teşekkürler! Premium üyeliğiniz aktif.')
            : 'Satın alma doğrulandı. Güncel kredi bakiyeniz yenilendi.',
      );
      // Yeni tamamlanan satın alma (ör. sonradan onaylanan bekleyen ödeme) her zaman bildirilir;
      // açılıştaki sessiz eşitlemede gelen "geri yüklendi" olayları bildirilmez.
      if (p.status == PurchaseStatus.purchased) {
        _tell(notice);
      } else {
        _tellUser(notice);
      }
      if (p.status != PurchaseStatus.restored) _userAction = false;
    } else if (result.permanent) {
      await _queue.remove(owner, claim);
      // Geri yüklemede süresi dolmuş eski abonelikler için uyarı gösterilmez.
      final quietExpired =
          sub &&
          result.error == 'EXPIRED' &&
          p.status == PurchaseStatus.restored;
      if (!quietExpired) {
        _tellUser(AppNotice.error(verifyErrorMessage(result.error)));
      }
    } else {
      // Geçici sorun: kayıt cihazda kalır, bağlantı gelince otomatik denenir.
      _tellUser(AppNotice.warning(verifyErrorMessage(result.error)));
    }
  }

  // ───────────── Bekleyen doğrulamalar ─────────────

  List<StoreClaim> get _pending => _queue.forUser(userId());

  /// Doğrulanmayı bekleyen satın alma sayısı.
  int get pendingCount => _pending.length;

  Future<void> _completeVerified(StoreClaim claim) async {
    final purchase = _unfinished[claim.token];
    if (purchase == null || !purchase.pendingCompletePurchase) return;
    try {
      if (!AppConfig.usesDotNet &&
          _platform == 'android' &&
          !isSubscription(claim.productId)) {
        await InAppPurchase.instance
            .getPlatformAddition<InAppPurchaseAndroidPlatformAddition>()
            .consumePurchase(purchase);
      }
      // .NET doğrulamayı ve Android consume/ack işlemini kalıcı kayıttan sonra yapar.
      await InAppPurchase.instance.completePurchase(purchase);
      _unfinished.remove(claim.token);
    } catch (_) {
      // Mağaza olayı tekrar gelirse sunucudaki idempotent doğrulama yeniden çalışır.
      debugPrint('Mağaza işlem kapatma yeniden denenecek.');
    }
  }

  /// Daha önce doğrulanamamış satın alımları yeniden dener (açılışta ve
  /// bağlantı geri gelince). Tamamlanan sayısını döner. Aynı anda tek deneme çalışır.
  Future<int> retryPending() {
    final running = _retrying;
    if (running != null) return running;
    final future = _retryPending();
    _retrying = future;
    return future.whenComplete(() => _retrying = null);
  }

  Future<int> _retryPending() async {
    var done = 0;
    final owner = userId();
    if (owner == null) return 0;
    for (final claim in _pending) {
      if (userId() != owner) break;
      try {
        final result = await verify(claim);
        if (result.ok) {
          done++;
          await _queue.remove(owner, claim);
          await _completeVerified(claim);
          if (userId() == owner) lastSuccessProductId = claim.productId;
        } else if (result.permanent) {
          await _queue.remove(owner, claim);
          if (userId() == owner) {
            _tell(AppNotice.error(verifyErrorMessage(result.error)));
          }
        }
      } catch (_) {
        // Bir sonraki denemede tekrar.
      }
    }
    if (done > 0 && userId() == owner) {
      _tell(
        AppNotice.success(
          done == 1
              ? 'Bekleyen satın almanız onaylandı ve hesabınıza tanımlandı.'
              : 'Bekleyen $done satın almanız onaylandı ve hesabınıza tanımlandı.',
        ),
      );
      notifyListeners();
    }
    return done;
  }

  void clearMessage() {
    lastSuccessProductId = null;
  }
}
