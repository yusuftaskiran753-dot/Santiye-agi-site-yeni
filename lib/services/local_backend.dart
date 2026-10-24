import 'dart:async';
import 'dart:math' as math;

import '../config.dart';
import '../data/demo_data.dart';
import '../logic/deal_rules.dart';
import '../models/models.dart';
import 'backend.dart';
import 'local_store.dart';

/// Demo modu: sunucu olmadan, her şey bu cihazda.
///
/// Kurallar sunucudaki (supabase/schema.sql) fonksiyonlarla aynıdır; böylece
/// uygulama iki modda da aynı davranır. [simulate] açıksa örnek firmalar
/// teklif ve taleplere birkaç saniye içinde yanıt verir, kullanıcının yeni
/// ilanlarına örnek teklif gelir. Böylece akışın tamamı denenebilir.
class LocalBackend implements Backend {
  LocalBackend(this._store, {this.simulate = true});

  final LocalStore _store;
  final bool simulate;

  static const String me = 'me';

  static const String _p = 'v2_';
  static const String _kProfile = '${_p}profile';
  static const String _kPhone = '${_p}phone';
  static const String _kListings = '${_p}listings_';
  static const String _kRequests = '${_p}requests';
  static const String _kDeals = '${_p}deals';
  static const String _kRatings = '${_p}ratings';
  static const String _kUnlocks = '${_p}unlocks';
  static const String _kBlocks = '${_p}blocks';
  static const String _kReports = '${_p}reports';
  static const String _kNotifications = '${_p}notifications';
  static const String _kWallet = '${_p}wallet';
  static const String _kPremium = '${_p}premium';
  static const String _kPurchases = '${_p}purchases';
  static const String _kSimulated = '${_p}simulated';

  final StreamController<BackendEvent> _events = StreamController<BackendEvent>.broadcast();
  final List<Timer> _timers = [];
  final math.Random _random = math.Random();

  @override
  bool get isLive => false;

  @override
  String? get userId => me;

  @override
  bool get hasSession => true;

  @override
  Stream<BackendEvent> get events => _events.stream;

  @override
  Future<void> init() async {}

  @override
  void dispose() {
    for (final t in _timers) {
      t.cancel();
    }
    _timers.clear();
    if (!_events.isClosed) _events.close();
  }

  // ───────────── Yardımcılar ─────────────

  String _now() => DateTime.now().toUtc().toIso8601String();

  List<Map<String, dynamic>> _read(String key) => _store.readMaps(key);

  Future<void> _write(String key, List<Map<String, dynamic>> items) => _store.writeMaps(key, items);

  PublicProfile get _myProfile {
    final m = _store.readMap(_kProfile);
    if (m == null) return const PublicProfile(id: me, name: 'Ben');
    return PublicProfile.fromJson({...m, 'id': me, 'premium_until': isoOrNull(_premiumUntil)});
  }

  PublicProfile _profileOf(String? id) {
    if (id == null || id.isEmpty) return PublicProfile.unknown;
    if (id == me) return _myProfile;
    return DemoData.profile(id);
  }

  String _nameOf(String? id) => _profileOf(id).displayName;

  DateTime? get _premiumUntil => asDateOrNull(_store.prefs.getString(_kPremium));

  bool get _isPremium {
    final until = _premiumUntil;
    return until != null && until.isAfter(DateTime.now());
  }

  int get _credits => _store.prefs.getInt(_kWallet) ?? 0;

  Future<void> _setCredits(int value) => _store.prefs.setInt(_kWallet, math.max(0, value));

  void _emit(String type, [String message = '']) {
    if (!_events.isClosed) _events.add(BackendEvent(type, message));
  }

  /// Simülasyon: [delay] sonra [action] çalışır ve uygulamaya haber verilir.
  void _later(Duration delay, Future<void> Function() action) {
    if (!simulate) return;
    late final Timer timer;
    timer = Timer(delay, () async {
      _timers.remove(timer);
      try {
        await action();
      } catch (_) {
        // Simülasyon hataları kullanıcıyı etkilemez.
      }
    });
    _timers.add(timer);
  }

  Future<void> _notify(String type, String title, String body, String refType, String? refId) async {
    final list = _read(_kNotifications);
    list.insert(0, {
      'id': newLocalId(),
      'type': type,
      'title': title,
      'body': body,
      'ref_type': refType,
      'ref_id': refId,
      'read_at': null,
      'created_at': _now(),
    });
    if (list.length > 200) list.removeRange(200, list.length);
    await _write(_kNotifications, list);
    // Uygulama verileri yeniler ve kısa bir bilgi mesajı gösterir.
    _emit('notification', title);
  }

  bool _isBlockedWith(String? other) => other != null && _store.readStrings(_kBlocks).contains(other);

  // ───────────── Oturum ─────────────

  @override
  Future<void> signInAnonymously() async {}

  @override
  Future<void> sendPhoneCode(String phoneE164) async {}

  /// Demo modunda doğrulama kodu her zaman 123456'dır.
  @override
  Future<void> verifyPhoneCode(String phoneE164, String code) async {
    if (code.trim() != '123456') throw const BackendException('BAD_INPUT', 'Kod hatalı');
    await _store.prefs.setString(_kPhone, phoneE164);
    final m = _store.readMap(_kProfile);
    if (m != null) await _store.writeMap(_kProfile, {...m, 'phone_verified': true});
  }

  @override
  Future<void> signOut() async {}

  @override
  Future<void> deleteAccount() async {
    await resetLocalData();
    await _store.remove(_kProfile);
    await _store.remove(_kPhone);
    await _store.remove(_kWallet);
    await _store.remove(_kPremium);
    await _store.remove(_kSimulated);
  }

  // ───────────── Profil ─────────────

  @override
  Future<PublicProfile?> fetchMyProfile() async => _store.has(_kProfile) ? _myProfile : null;

  @override
  Future<String> fetchMyPhone() async => _store.prefs.getString(_kPhone) ?? '';

  @override
  Future<PublicProfile> saveMyProfile({
    required String name,
    required String company,
    required UserRole role,
    required String city,
    required String phone,
  }) async {
    final existing = _store.has(_kProfile) ? _myProfile : null;
    final profile = PublicProfile(
      id: me,
      name: name,
      company: company,
      role: role,
      city: city,
      ratingAvg: existing?.ratingAvg ?? 0,
      ratingCount: existing?.ratingCount ?? 0,
      dealsCompleted: existing?.dealsCompleted ?? 0,
      phoneVerified: existing?.phoneVerified ?? false,
      createdAt: existing?.createdAt ?? DateTime.now(),
    );
    await _store.writeMap(_kProfile, profile.toJson());
    await _store.prefs.setString(_kPhone, phone);
    return _myProfile;
  }

  @override
  Future<PublicProfile?> fetchProfile(String userId) async => _profileOf(userId);

  @override
  Future<List<PublicProfile>> fetchProfiles(List<String> ids) async => [for (final id in ids) _profileOf(id)];

  @override
  Future<List<Rating>> fetchRatingsFor(String userId) async {
    final stored = [for (final r in _read(_kRatings)) Rating.fromJson(r)].where((r) => r.toId == userId).toList();
    return [...stored, ...DemoData.ratingsFor(userId)]..sort((a, b) => b.createdAt.compareTo(a.createdAt));
  }

  @override
  Future<Set<String>> fetchMyRatedDealIds() async => {
        for (final r in _read(_kRatings))
          if (r['from_id'] == me) asString(r['deal_id']),
      };

  Future<void> _recomputeMyRating() async {
    final mine = [for (final r in _read(_kRatings)) Rating.fromJson(r)].where((r) => r.toId == me).toList();
    final m = _store.readMap(_kProfile);
    if (m == null) return;
    final avg = mine.isEmpty ? 0.0 : mine.fold<int>(0, (a, r) => a + r.stars) / mine.length;
    await _store.writeMap(_kProfile, {
      ...m,
      'rating_avg': double.parse(avg.toStringAsFixed(2)),
      'rating_count': mine.length,
    });
  }

  Future<void> _incrementDealsCompleted() async {
    final m = _store.readMap(_kProfile);
    if (m == null) return;
    await _store.writeMap(_kProfile, {...m, 'deals_completed': asInt(m['deals_completed']) + 1});
  }

  int get _freeUsedThisMonth {
    final now = DateTime.now();
    return _read(_kUnlocks).where((u) {
      if (u['method'] != 'free') return false;
      final at = asDate(u['created_at']);
      return at.year == now.year && at.month == now.month;
    }).length;
  }

  int _activeListingCount() {
    var count = 0;
    for (final kind in ListingKind.values) {
      if (kind == ListingKind.sicil) continue;
      for (final m in _read('$_kListings${kind.name}')) {
        if (Listing.fromJson(kind, m).isOpen) count++;
      }
    }
    return count;
  }

  @override
  Future<UsageInfo> fetchUsage() async => UsageInfo(
        freeUsed: _freeUsedThisMonth,
        freeLimit: AppConfig.freeMonthlyUnlocks,
        credits: _credits,
        premiumUntil: _premiumUntil,
        freeListingLimit: AppConfig.freeActiveListings,
        activeListings: _activeListingCount(),
        boostDayCost: AppConfig.boostDayCost,
        boostWeekCost: AppConfig.boostWeekCost,
      );

  // ───────────── İlanlar ─────────────

  String _listingKey(ListingKind kind) => '$_kListings${kind.name}';

  List<Listing> _myListings(ListingKind kind) {
    final owner = _myProfile;
    return [
      for (final m in _read(_listingKey(kind))) Listing.fromJson(kind, {...m, 'owner': owner.toJson(), 'owner_id': me}),
    ];
  }

  Listing? _findListing(ListingKind kind, String id) {
    for (final l in _myListings(kind)) {
      if (l.id == id) return l;
    }
    for (final l in DemoData.listings(kind)) {
      if (l.id == id) return l;
    }
    return null;
  }

  /// Sunucudaki listing_info ile aynı başlık.
  static String listingTitle(Listing l) => switch (l) {
        Load x => '${x.fromCity} → ${x.toCity} · ${x.cargo}',
        Machine x => '${x.model} · ${x.city}',
        MaterialListing x => '${x.product} · ${x.plantName}',
        JobPost x => x.title,
        WorkerCard x => '${x.owner.name} · sicil kartı',
        _ => l.title,
      };

  @override
  Future<List<Listing>> fetchListings(ListingKind kind) async {
    final mine = _myListings(kind);
    final demo = DemoData.listings(kind).where((l) => !_isBlockedWith(l.ownerId));
    return [...mine, ...demo];
  }

  void _checkListingLimit() {
    if (!_isPremium && _activeListingCount() >= AppConfig.freeActiveListings) {
      throw const BackendException('LISTING_LIMIT');
    }
  }

  @override
  Future<Listing> saveListing(Listing listing, {required bool isNew}) async {
    final kind = listing.kind;
    final key = _listingKey(kind);
    final list = _read(key);
    final owner = _myProfile;
    Map<String, dynamic> row;
    final sameId = listing.id.isEmpty ? -1 : list.indexWhere((m) => m['id'] == listing.id);
    if (isNew && sameId >= 0) {
      // Aynı kimlikle tekrar gönderilen yeni ilan: ikinci kez eklenmez, güncellenir.
      row = {...list[sameId], ...listing.toRow(), 'updated_at': _now()};
      list[sameId] = row;
    } else if (isNew) {
      if (kind != ListingKind.sicil && listing.status == ListingStatus.active) _checkListingLimit();
      if (kind == ListingKind.sicil && list.isNotEmpty) {
        // Kişi başı tek sicil kartı: mevcut kart güncellenir.
        final old = list.first;
        row = {...old, ...listing.toRow(), 'updated_at': _now()};
        list[0] = row;
      } else {
        row = {
          ...listing.toRow(),
          'id': listing.id.isNotEmpty ? listing.id : newLocalId(),
          'owner_id': me,
          'boosted_until': null,
          'hidden': false,
          'demo': false,
          'created_at': _now(),
        };
        list.insert(0, row);
        _scheduleIncomingRequest(Listing.fromJson(kind, {...row, 'owner': owner.toJson()}));
      }
    } else {
      final i = list.indexWhere((m) => m['id'] == listing.id);
      if (i < 0) throw const BackendException('NOT_FOUND');
      final old = list[i];
      final wasActive = old['status'] == 'active';
      if (kind != ListingKind.sicil && !wasActive && listing.status == ListingStatus.active) _checkListingLimit();
      row = {...old, ...listing.toRow(), 'updated_at': _now()};
      list[i] = row;
    }
    await _write(key, list);
    return Listing.fromJson(kind, {...row, 'owner': owner.toJson()});
  }

  @override
  Future<void> setListingStatus(ListingKind kind, String id, ListingStatus status) async {
    final key = _listingKey(kind);
    final list = _read(key);
    final i = list.indexWhere((m) => m['id'] == id);
    if (i < 0) throw const BackendException('NOT_FOUND');
    if (kind != ListingKind.sicil && list[i]['status'] != 'active' && status == ListingStatus.active) {
      _checkListingLimit();
    }
    list[i] = {...list[i], 'status': status.name, 'updated_at': _now()};
    await _write(key, list);
  }

  @override
  Future<void> deleteListing(ListingKind kind, String id) async {
    final key = _listingKey(kind);
    final list = _read(key)..removeWhere((m) => m['id'] == id);
    await _write(key, list);
    final requests = _read(_kRequests);
    var changed = false;
    for (var i = 0; i < requests.length; i++) {
      if (requests[i]['listing_id'] == id && requests[i]['status'] == 'pending') {
        requests[i] = {...requests[i], 'status': 'rejected', 'updated_at': _now()};
        changed = true;
      }
    }
    if (changed) await _write(_kRequests, requests);
  }

  @override
  Future<void> setMachineAvailable(String id, bool available) async {
    final key = _listingKey(ListingKind.makine);
    final list = _read(key);
    final i = list.indexWhere((m) => m['id'] == id);
    if (i < 0) throw const BackendException('NOT_FOUND');
    list[i] = {...list[i], 'available': available, 'updated_at': _now()};
    await _write(key, list);
  }

  @override
  Future<DateTime> boostListing(ListingKind kind, String id, BoostOption option) async {
    final key = _listingKey(kind);
    final list = _read(key);
    final i = list.indexWhere((m) => m['id'] == id);
    if (i < 0) throw const BackendException('NOT_FOUND');
    final listing = Listing.fromJson(kind, list[i]);
    if (!listing.isOpen) throw const BackendException('NOT_AVAILABLE');
    final cost = option == BoostOption.day ? AppConfig.boostDayCost : AppConfig.boostWeekCost;
    if (_credits < cost) throw const BackendException('NO_CREDITS');
    await _setCredits(_credits - cost);
    final now = DateTime.now();
    final current = listing.boostedUntil;
    final base = current != null && current.isAfter(now) ? current : now;
    final until = base.add(option == BoostOption.day ? const Duration(days: 1) : const Duration(days: 7));
    list[i] = {...list[i], 'boosted_until': until.toUtc().toIso8601String()};
    await _write(key, list);
    return until;
  }

  // ───────────── İletişim hakkı ─────────────

  @override
  Future<Set<String>> fetchUnlockedKeys() async => {
        for (final u in _read(_kUnlocks)) '${u['ref_type']}:${u['ref_id']}',
      };

  bool _isUnlocked(ListingKind kind, String id) =>
      _read(_kUnlocks).any((u) => u['ref_type'] == kind.name && u['ref_id'] == id);

  @override
  Future<UnlockResult> unlock(ListingKind kind, String id, {bool useCredit = false}) async {
    final listing = _findListing(kind, id);
    if (listing == null) throw const BackendException('NOT_FOUND');
    if (listing.ownerId == me) return const UnlockResult(ok: true, method: 'own');
    if (_isUnlocked(kind, id)) return const UnlockResult(ok: true, method: 'already');
    if (_isBlockedWith(listing.ownerId)) throw const BackendException('BLOCKED');
    if (!listing.isOpen) throw const BackendException('NOT_AVAILABLE');

    final String method;
    if (_isPremium) {
      method = 'premium';
    } else if (_freeUsedThisMonth < AppConfig.freeMonthlyUnlocks) {
      method = 'free';
    } else {
      if (!useCredit || _credits < 1) {
        return UnlockResult(ok: false, reason: 'QUOTA', credits: _credits);
      }
      await _setCredits(_credits - 1);
      method = 'credit';
    }
    final list = _read(_kUnlocks)
      ..add({'ref_type': kind.name, 'ref_id': id, 'method': method, 'created_at': _now()});
    await _write(_kUnlocks, list);
    return UnlockResult(ok: true, method: method);
  }

  ContactInfo _contactOf(String? userId, {String fallbackName = ''}) {
    if (userId == null || userId.isEmpty) {
      return ContactInfo(userId: '', name: fallbackName, phone: '');
    }
    final profile = _profileOf(userId);
    final raw = userId == me ? (_store.prefs.getString(_kPhone) ?? '') : DemoData.phoneOf(userId);
    final phone = profile.phoneVerified ? raw : '';
    return ContactInfo(userId: userId, name: profile.displayName, phone: phone, phoneVerified: profile.phoneVerified);
  }

  @override
  Future<ContactInfo> contactFor(String refType, String refId) async {
    final kind = ListingKind.values.where((k) => k.name == refType).firstOrNull;
    if (kind != null) {
      final listing = _findListing(kind, refId);
      if (listing == null) throw const BackendException('NOT_FOUND');
      if (listing.ownerId != me && !_isUnlocked(kind, refId)) throw const BackendException('LOCKED');
      if (_isBlockedWith(listing.ownerId)) throw const BackendException('BLOCKED');
      return _contactOf(listing.ownerId);
    }
    if (refType == 'request') {
      final r = _read(_kRequests).where((m) => m['id'] == refId).firstOrNull;
      if (r == null) throw const BackendException('NOT_FOUND');
      final other = r['owner_id'] == me ? asString(r['requester_id']) : asString(r['owner_id']);
      return _contactOf(other);
    }
    if (refType == 'deal') {
      final d = _read(_kDeals).where((m) => m['id'] == refId).firstOrNull;
      if (d == null) throw const BackendException('NOT_FOUND');
      final deal = Deal.fromJson(d);
      return _contactOf(deal.counterpartyId(me), fallbackName: deal.counterpartyName(me));
    }
    throw const BackendException('BAD_INPUT');
  }

  // ───────────── Teklif / talep ─────────────

  TradeRequest _parseRequest(Map<String, dynamic> m) => TradeRequest.fromJson({
        ...m,
        'owner': _profileOf(asString(m['owner_id'])).toJson(),
        'requester': _profileOf(asString(m['requester_id'])).toJson(),
      });

  @override
  Future<List<TradeRequest>> fetchRequests() async =>
      [for (final m in _read(_kRequests)) _parseRequest(m)]..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));

  @override
  Future<TradeRequest> createRequest(RequestDraft draft, {String? opId}) async {
    final listing = _findListing(draft.kind, draft.listingId);
    if (listing == null) throw const BackendException('NOT_FOUND');
    if (listing.ownerId == me) throw const BackendException('OWN_LISTING');
    if (!listing.isOpen) throw const BackendException('NOT_AVAILABLE');
    if (_isBlockedWith(listing.ownerId)) throw const BackendException('BLOCKED');
    if (!_isUnlocked(draft.kind, draft.listingId)) throw const BackendException('LOCKED');
    if (draft.amount < 0 || draft.amount > 100000000 || draft.quantity < 0) {
      throw const BackendException('BAD_INPUT');
    }
    final list = _read(_kRequests);
    final fields = {
      'amount': draft.amount,
      'quantity': draft.quantity,
      'unit': draft.unit,
      'start_date': draft.startDate == null ? null : dateOnly(draft.startDate!),
      'address': draft.address,
      'note': draft.note,
      'updated_at': _now(),
    };
    final i = list.indexWhere(
        (m) => m['listing_id'] == draft.listingId && m['requester_id'] == me && m['status'] == 'pending');
    Map<String, dynamic> row;
    if (i >= 0) {
      row = {...list[i], ...fields};
      list[i] = row;
    } else {
      row = {
        ...fields,
        'id': newLocalId(),
        'kind': draft.kind.name,
        'listing_id': draft.listingId,
        'listing_title': listingTitle(listing),
        'owner_id': listing.ownerId,
        'requester_id': me,
        'status': 'pending',
        'deal_id': null,
        'created_at': _now(),
      };
      list.insert(0, row);
      if (DemoData.isDemoId(listing.ownerId)) {
        final requestId = asString(row['id']);
        _later(const Duration(milliseconds: 2500), () => _demoAccept(requestId));
      }
    }
    await _write(_kRequests, list);
    return _parseRequest(row);
  }

  /// Örnek firma talebi kabul eder.
  Future<void> _demoAccept(String requestId) async {
    final list = _read(_kRequests);
    final i = list.indexWhere((m) => m['id'] == requestId && m['status'] == 'pending');
    if (i < 0) return;
    final r = TradeRequest.fromJson(list[i]);
    final dealId = await _createDealFromRequest(r, acceptedBy: r.ownerId);
    list[i] = {...list[i], 'status': 'accepted', 'deal_id': dealId, 'updated_at': _now()};
    await _write(_kRequests, list);
    await _notify('request_accepted', 'Talebiniz kabul edildi',
        '${_nameOf(r.ownerId)} · ${r.listingTitle} · anlaşma kaydı oluştu (örnek firma)', 'deal', dealId);
  }

  Future<String> _createDealFromRequest(TradeRequest r, {required String acceptedBy}) async {
    final customer = r.kind.requesterIsProvider ? r.ownerId : r.requesterId;
    final provider = r.kind.requesterIsProvider ? r.requesterId : r.ownerId;
    final details = <String>[
      if (r.quantity > 0) 'Miktar: ${DealRules.trimNumber(r.quantity)} ${r.unit}',
      if (r.startDate != null)
        'Tarih: ${r.startDate!.day.toString().padLeft(2, '0')}.${r.startDate!.month.toString().padLeft(2, '0')}.${r.startDate!.year}',
      if (r.address.isNotEmpty) 'Adres: ${r.address}',
      if (r.note.isNotEmpty) 'Not: ${r.note}',
    ].join('\n');
    final id = newLocalId();
    final deals = _read(_kDeals)
      ..insert(0, {
        'id': id,
        'code': _newCode(),
        'kind': r.kind.name,
        'request_id': r.id,
        'title': r.listingTitle,
        'details': details,
        'customer_id': customer,
        'provider_id': provider,
        'customer_name': _nameOf(customer),
        'provider_name': _nameOf(provider),
        'created_by': acceptedBy,
        'amount': r.amount,
        'payment_method': 'havale',
        'payment_terms': '',
        'start_date': r.startDate == null ? null : dateOnly(r.startDate!),
        'status': 'active',
        'prev_status': null,
        'milestones': [
          if (r.amount > 0) {'title': 'Toplam bedel', 'amount': r.amount, 'paid_at': null, 'received_at': null},
        ],
        'log': [
          {'at': _now(), 'by': _nameOf(acceptedBy), 'text': 'Talep kabul edildi, anlaşma kaydı oluşturuldu'},
        ],
        'created_at': _now(),
        'updated_at': _now(),
      });
    await _write(_kDeals, deals);
    return id;
  }

  String _newCode() {
    const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    return List.generate(8, (_) => chars[_random.nextInt(chars.length)]).join();
  }

  @override
  Future<String?> respondRequest(String id, {required bool accept, String? opId}) async {
    final list = _read(_kRequests);
    final i = list.indexWhere((m) => m['id'] == id);
    if (i < 0) throw const BackendException('NOT_FOUND');
    final r = TradeRequest.fromJson(list[i]);
    if (r.ownerId != me) throw const BackendException('FORBIDDEN');
    if (!r.isPending) throw const BackendException('NOT_PENDING');
    if (!accept) {
      list[i] = {...list[i], 'status': 'rejected', 'updated_at': _now()};
      await _write(_kRequests, list);
      return null;
    }
    final dealId = await _createDealFromRequest(r, acceptedBy: me);
    list[i] = {...list[i], 'status': 'accepted', 'deal_id': dealId, 'updated_at': _now()};
    if (r.kind == ListingKind.yuk) {
      for (var k = 0; k < list.length; k++) {
        if (k != i && list[k]['listing_id'] == r.listingId && list[k]['status'] == 'pending') {
          list[k] = {...list[k], 'status': 'rejected', 'updated_at': _now()};
        }
      }
      await _write(_kRequests, list);
      await setListingStatus(ListingKind.yuk, r.listingId, ListingStatus.closed);
    } else {
      await _write(_kRequests, list);
    }
    return dealId;
  }

  @override
  Future<void> withdrawRequest(String id) async {
    final list = _read(_kRequests);
    final i = list.indexWhere((m) => m['id'] == id && m['requester_id'] == me && m['status'] == 'pending');
    if (i < 0) throw const BackendException('NOT_PENDING');
    list[i] = {...list[i], 'status': 'withdrawn', 'updated_at': _now()};
    await _write(_kRequests, list);
  }

  /// Demo modunda kullanıcının yeni ilanına örnek bir teklif/talep gelir.
  void _scheduleIncomingRequest(Listing listing) {
    final done = _store.readStrings(_kSimulated);
    if (done.contains(listing.id) || done.length > 30) return;
    _later(const Duration(seconds: 5), () async {
      final now = _store.readStrings(_kSimulated);
      if (now.contains(listing.id)) return;
      await _store.writeStrings(_kSimulated, [...now, listing.id]);
      final tomorrow = DateTime.now().add(const Duration(days: 1));
      final (PublicProfile from, Map<String, dynamic> fields, String title) = switch (listing) {
        Load l => (
            DemoData.sampleCarrier,
            {
              'amount': l.price > 0 ? (l.price * 0.95).roundToDouble() : 25000.0,
              'quantity': l.tons,
              'unit': 'ton',
              'start_date': dateOnly(l.date),
              'note': 'Aracım hazır, belirtilen gün yükleyebilirim. (Örnek teklif)',
            },
            'Yeni nakliye teklifi',
          ),
        Machine m => (
            DemoData.sampleCustomer,
            {
              'amount': m.daily * 3,
              'quantity': 3.0,
              'unit': 'gün',
              'start_date': dateOnly(tomorrow),
              'address': 'Bornova şantiyesi',
              'note': 'Operatörlü, 3 günlük iş. (Örnek talep)',
            },
            'Yeni kiralama talebi',
          ),
        MaterialListing x => (
            DemoData.sampleCustomer,
            {
              'amount': (x.minQty > 0 ? x.minQty : 20) * x.price,
              'quantity': x.minQty > 0 ? x.minQty : 20.0,
              'unit': x.unit,
              'start_date': dateOnly(tomorrow),
              'address': 'Bornova şantiyesi',
              'note': 'Sabah 07.00 teslim. (Örnek sipariş)',
            },
            'Yeni sipariş talebi',
          ),
        JobPost _ => (
            DemoData.sampleWorker,
            {'note': '8 yıl deneyimliyim, MYK belgem var. (Örnek başvuru)'},
            'Yeni iş başvurusu',
          ),
        _ => (
            DemoData.sampleEmployer,
            {
              'amount': 3000.0,
              'quantity': 1.0,
              'unit': 'gün',
              'start_date': dateOnly(tomorrow),
              'note': 'Asfalt ekibine 1 günlük iş. (Örnek iş teklifi)',
            },
            'Yeni iş teklifi',
          ),
      };
      final id = newLocalId();
      final list = _read(_kRequests)
        ..insert(0, {
          'id': id,
          'kind': listing.kind.name,
          'listing_id': listing.id,
          'listing_title': listingTitle(listing),
          'owner_id': me,
          'requester_id': from.id,
          'amount': 0.0,
          'quantity': 0.0,
          'unit': '',
          'start_date': null,
          'address': '',
          'note': '',
          ...fields,
          'status': 'pending',
          'deal_id': null,
          'created_at': _now(),
          'updated_at': _now(),
        });
      await _write(_kRequests, list);
      await _notify('request', title, '${from.displayName} · ${listingTitle(listing)} (örnek)', 'request', id);
    });
  }

  // ───────────── Anlaşmalar ─────────────

  @override
  Future<List<Deal>> fetchDeals() async =>
      [for (final m in _read(_kDeals)) Deal.fromJson(m)]..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));

  @override
  Future<Deal> createDeal(DealDraft draft) async {
    if (draft.title.trim().length < 2) throw const BackendException('BAD_INPUT');
    final name = _nameOf(me);
    final row = <String, dynamic>{
      'id': newLocalId(),
      'code': _newCode(),
      'kind': 'diger',
      'request_id': null,
      'title': draft.title.trim(),
      'details': draft.details,
      'customer_id': draft.iAmCustomer ? me : null,
      'provider_id': draft.iAmCustomer ? null : me,
      'customer_name': draft.iAmCustomer ? name : draft.counterpartyName,
      'provider_name': draft.iAmCustomer ? draft.counterpartyName : name,
      'created_by': me,
      'amount': draft.amount,
      'payment_method': draft.paymentMethod.name,
      'payment_terms': draft.paymentTerms,
      'start_date': draft.startDate == null ? null : dateOnly(draft.startDate!),
      'status': 'pending',
      'prev_status': null,
      'milestones': [
        for (final m in draft.milestones) {'title': m.title, 'amount': m.amount, 'paid_at': null, 'received_at': null},
      ],
      'log': [
        {'at': _now(), 'by': name, 'text': 'Anlaşma kaydı oluşturuldu'},
      ],
      'created_at': _now(),
      'updated_at': _now(),
    };
    final list = _read(_kDeals)..insert(0, row);
    await _write(_kDeals, list);
    return Deal.fromJson(row);
  }

  @override
  Future<Deal> joinDeal(String code) async {
    final wanted = code.trim().toUpperCase();
    final m = _read(_kDeals).where((d) => d['code'] == wanted).firstOrNull;
    if (m == null) throw const BackendException('NOT_FOUND');
    return Deal.fromJson(m);
  }

  @override
  Future<Deal> dealAction(String id, DealAction action, {int? index, String? note, String? opId}) async {
    final list = _read(_kDeals);
    final i = list.indexWhere((m) => m['id'] == id);
    if (i < 0) throw const BackendException('NOT_FOUND');
    final updated = _applyDealAction(list[i], me, action, index: index, note: note);
    list[i] = updated;
    await _write(_kDeals, list);
    final deal = Deal.fromJson(updated);
    if (action == DealAction.complete && deal.customerId != null && deal.providerId != null) {
      await _incrementDealsCompleted();
    }
    _scheduleDemoDealReaction(deal, action, index: index);
    return deal;
  }

  /// Sunucudaki deal_action fonksiyonunun cihazdaki karşılığı (bkz. [DealRules]).
  Map<String, dynamic> _applyDealAction(
    Map<String, dynamic> row,
    String actor,
    DealAction action, {
    int? index,
    String? note,
  }) =>
      DealRules.apply(
        row,
        actor: actor,
        actorName: _nameOf(actor),
        action: action,
        index: index,
        note: note,
        now: DateTime.now(),
      );

  /// Karşı taraf örnek firmaysa, kullanıcının işlemine gerçekçi bir yanıt verir.
  void _scheduleDemoDealReaction(Deal deal, DealAction action, {int? index}) {
    final other = deal.counterpartyId(me);
    if (other == null || !DemoData.isDemoId(other)) return;

    Future<void> act(DealAction a, {int? index}) async {
      final list = _read(_kDeals);
      final i = list.indexWhere((m) => m['id'] == deal.id);
      if (i < 0) return;
      list[i] = _applyDealAction(list[i], other, a, index: index);
      await _write(_kDeals, list);
    }

    if (action == DealAction.deliver) {
      _later(const Duration(seconds: 3), () async {
        await act(DealAction.complete);
        await _incrementDealsCompleted();
        await _addRating(deal.id, other, me, 5, 'Zamanında ve eksiksiz teslim. Teşekkürler!');
        await _notify('deal', deal.title, '${_nameOf(other)} teslim aldı ve anlaşmayı tamamladı (örnek)', 'deal', deal.id);
      });
    } else if (action == DealAction.markPaid) {
      // Kullanıcının "ödedim" dediği satır onaylanır (ilk ödenmiş satır değil).
      final paidIndex = index ?? deal.milestones.indexWhere((m) => m.paid && !m.received);
      if (paidIndex < 0 || paidIndex >= deal.milestones.length) return;
      _later(const Duration(seconds: 3), () async {
        await act(DealAction.markReceived, index: paidIndex);
        await _notify('deal', deal.title, '${_nameOf(other)} ödemeyi tahsil ettiğini onayladı (örnek)', 'deal', deal.id);
      });
    } else if (action == DealAction.complete) {
      _later(const Duration(seconds: 2), () async {
        await _addRating(deal.id, other, me, 5, 'Sorunsuz iş birliği, tekrar çalışırız.');
        await _notify('rating', 'Yeni değerlendirme', '${_nameOf(other)} size 5 yıldız verdi (örnek)', 'deal', deal.id);
      });
    }
  }

  Future<void> _addRating(String dealId, String from, String to, int stars, String comment) async {
    final list = _read(_kRatings);
    if (list.any((r) => r['deal_id'] == dealId && r['from_id'] == from)) return;
    list.insert(0, {
      'id': newLocalId(),
      'deal_id': dealId,
      'from_id': from,
      'to_id': to,
      'from_name': _nameOf(from),
      'stars': stars,
      'comment': comment,
      'created_at': _now(),
    });
    await _write(_kRatings, list);
    if (to == me) await _recomputeMyRating();
  }

  @override
  Future<void> rateDeal(String dealId, int stars, String comment, {String? opId}) async {
    if (stars < 1 || stars > 5) throw const BackendException('BAD_INPUT');
    final m = _read(_kDeals).where((d) => d['id'] == dealId).firstOrNull;
    if (m == null) throw const BackendException('NOT_FOUND');
    final deal = Deal.fromJson(m);
    if (deal.status != DealStatus.completed) throw const BackendException('BAD_STATE');
    if (!deal.isCustomer(me) && !deal.isProvider(me)) throw const BackendException('FORBIDDEN');
    final other = deal.counterpartyId(me);
    if (other == null) throw const BackendException('NOT_AVAILABLE');
    if (_read(_kRatings).any((r) => r['deal_id'] == dealId && r['from_id'] == me)) {
      throw const BackendException('ALREADY_RATED');
    }
    final trimmed = comment.trim();
    await _addRating(dealId, me, other, stars, trimmed.length > 300 ? trimmed.substring(0, 300) : trimmed);
  }

  // ───────────── Güvenlik ─────────────

  @override
  Future<void> report(String targetType, String targetId, String reason, String note) async {
    final list = _read(_kReports);
    if (list.any((r) => r['target_type'] == targetType && r['target_id'] == targetId)) return;
    list.add({'target_type': targetType, 'target_id': targetId, 'reason': reason, 'note': note, 'created_at': _now()});
    await _write(_kReports, list);
  }

  @override
  Future<Set<String>> fetchBlockedIds() async => _store.readStrings(_kBlocks).toSet();

  @override
  Future<void> block(String userId) async {
    if (userId == me) return;
    final set = _store.readStrings(_kBlocks).toSet()..add(userId);
    await _store.writeStrings(_kBlocks, set);
  }

  @override
  Future<void> unblock(String userId) async {
    final set = _store.readStrings(_kBlocks).toSet()..remove(userId);
    await _store.writeStrings(_kBlocks, set);
  }

  // ───────────── Bildirimler ─────────────

  @override
  Future<List<AppNotification>> fetchNotifications() async => [
        for (final n in _read(_kNotifications)) AppNotification.fromJson(n),
      ];

  @override
  Future<void> markNotificationsRead() async {
    final list = [
      for (final n in _read(_kNotifications)) n['read_at'] == null ? {...n, 'read_at': _now()} : n,
    ];
    await _write(_kNotifications, list);
  }

  // ───────────── Mağaza ─────────────

  /// Demo modunda mağaza satın alımı cihazda işlenir (sunucu doğrulaması yok).
  @override
  Future<VerifyResult> verifyPurchase(StoreClaim claim) async {
    final processed = _store.readStrings(_kPurchases);
    final key = '${claim.platform}:${claim.token}';
    final isNew = !processed.contains(key);
    if (claim.productId == AppConfig.premiumMonthlyId || claim.productId == AppConfig.premiumYearlyId) {
      final current = _premiumUntil;
      // Aynı satın alma (ör. "geri yükle") süreyi ikinci kez uzatmaz.
      if (!isNew && current != null) return VerifyResult(ok: true, premiumUntil: current);
      final days = claim.productId == AppConfig.premiumYearlyId ? 366 : 31;
      final candidate = DateTime.now().add(Duration(days: days));
      final until = current != null && current.isAfter(candidate) ? current : candidate;
      await _store.prefs.setString(_kPremium, until.toUtc().toIso8601String());
      if (isNew) await _store.writeStrings(_kPurchases, [...processed, key]);
      return VerifyResult(ok: true, premiumUntil: until);
    }
    final credits = AppConfig.creditPacks[claim.productId];
    if (credits == null) return const VerifyResult(ok: false, error: 'UNKNOWN_PRODUCT');
    if (isNew) {
      await _setCredits(_credits + credits);
      await _store.writeStrings(_kPurchases, [...processed, key]);
    }
    return VerifyResult(ok: true, credits: _credits);
  }

  @override
  Future<void> resetLocalData() async {
    await _store.clearPrefix(_p, keep: {_kProfile, _kPhone, _kWallet, _kPremium, _kPurchases});
  }
}
