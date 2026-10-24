import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../config.dart';
import '../models/models.dart';
import 'backend.dart';

/// Canlı mod: Supabase üzerinde gerçek, çok kullanıcılı pazar yeri.
///
/// Bütün kurallar (kota, kredi, ilan sınırı, anlaşma akışı, şikâyet) sunucuda
/// supabase/schema.sql içindeki fonksiyonlarla uygulanır; uygulama yalnızca
/// bu fonksiyonları çağırır. Böylece kimse uygulamayı değiştirerek kuralları
/// aşamaz.
class SupabaseBackend implements Backend {
  SupabaseClient get _db => Supabase.instance.client;

  /// Zayıf çekimde isteğin sonsuza kadar asılı kalmaması için üst süre.
  /// Süre dolunca işlem "bağlantı yok" sayılır; yazma işlemleri işlem
  /// kimliğiyle (opId) gönderildiğinden yeniden gönderimde çift kayıt oluşmaz.
  static const Duration _timeout = Duration(seconds: 20);
  bool _initialized = false;

  final StreamController<BackendEvent> _events = StreamController<BackendEvent>.broadcast();
  RealtimeChannel? _channel;
  String? _channelUser;
  StreamSubscription<AuthState>? _authSub;

  static const String _owner = 'owner:profiles!owner_id($kProfileColumns)';
  static const String _listingSelect = '*, $_owner';
  static const String _requestSelect =
      '*, owner:profiles!owner_id($kProfileColumns), requester:profiles!requester_id($kProfileColumns)';

  static String _table(ListingKind kind) => switch (kind) {
        ListingKind.yuk => 'loads',
        ListingKind.makine => 'machines',
        ListingKind.malzeme => 'materials',
        ListingKind.personel => 'jobs',
        ListingKind.sicil => 'workers',
      };

  @override
  bool get isLive => true;

  @override
  String? get userId => _db.auth.currentUser?.id;

  @override
  bool get hasSession => _db.auth.currentSession != null;

  @override
  Stream<BackendEvent> get events => _events.stream;

  String get _uid {
    final id = userId;
    if (id == null) throw const BackendException('AUTH_REQUIRED');
    return id;
  }

  @override
  Future<void> init() async {
    // "Tekrar dene" ile ikinci kez çağrılabilir: istemci yalnızca bir kez kurulur.
    if (!_initialized) {
      await Supabase.initialize(url: AppConfig.supabaseUrl, publishableKey: AppConfig.supabaseKey);
      _initialized = true;
      _authSub = _db.auth.onAuthStateChange.listen((_) => _subscribeRealtime(), onError: (Object _) {});
    }
    _subscribeRealtime();
  }

  @override
  void dispose() {
    _authSub?.cancel();
    final channel = _channel;
    if (channel != null) _db.removeChannel(channel);
    if (!_events.isClosed) _events.close();
  }

  /// Yeni bildirimleri canlı dinler (rozet ve listeler anında güncellenir).
  void _subscribeRealtime() {
    final uid = userId;
    if (uid == _channelUser) return;
    final old = _channel;
    if (old != null) _db.removeChannel(old);
    _channel = null;
    _channelUser = uid;
    if (uid == null) return;
    _channel = _db
        .channel('bildirim-$uid')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'notifications',
          filter: PostgresChangeFilter(type: PostgresChangeFilterType.eq, column: 'user_id', value: uid),
          callback: (payload) {
            if (!_events.isClosed) {
              _events.add(BackendEvent('notification', asString(payload.newRecord['title'])));
            }
          },
        )
        .subscribe();
  }

  Future<T> _guard<T>(Future<T> Function() body) async {
    try {
      return await body().timeout(_timeout);
    } on BackendException {
      rethrow;
    } on PostgrestException catch (e) {
      throw BackendException.fromServer(e.code, '${e.message} ${e.details ?? ''} ${e.hint ?? ''}');
    } on AuthException catch (e) {
      final mapped = BackendException.from(e);
      if (mapped.code != 'UNKNOWN') throw mapped;
      throw BackendException(e.statusCode == '401' || e.statusCode == '403' ? 'AUTH_REQUIRED' : 'UNKNOWN', e.message);
    } catch (e) {
      throw BackendException.from(e);
    }
  }

  Future<Map<String, dynamic>> _rpcMap(String fn, Map<String, dynamic> params) async {
    final result = await _db.rpc<dynamic>(fn, params: params);
    return asMap(result);
  }

  // ───────────── Oturum ─────────────

  @override
  Future<void> signInAnonymously() => _guard(() async {
        if (hasSession) return;
        await _db.auth.signInAnonymously();
        _subscribeRealtime();
      });

  @override
  Future<void> sendPhoneCode(String phoneE164) => _guard(() => _db.auth.signInWithOtp(phone: phoneE164));

  @override
  Future<void> verifyPhoneCode(String phoneE164, String code) => _guard(() async {
        try {
          await _db.auth.verifyOTP(phone: phoneE164, token: code.trim(), type: OtpType.sms);
        } on AuthException {
          throw const BackendException('BAD_INPUT', 'Kod hatalı veya süresi dolmuş');
        }
        _subscribeRealtime();
      });

  @override
  Future<void> signOut() => _guard(() async {
        await _db.auth.signOut();
        _subscribeRealtime();
      });

  @override
  Future<void> deleteAccount() => _guard(() async {
        await _db.rpc<dynamic>('delete_my_account');
        try {
          await _db.auth.signOut();
        } catch (_) {
          // Hesap silindiği için oturum zaten geçersiz.
        }
        _subscribeRealtime();
      });

  // ───────────── Profil ─────────────

  @override
  Future<PublicProfile?> fetchMyProfile() => _guard(() async {
        final uid = userId;
        if (uid == null) return null;
        final row = await _db.from('profiles').select(kProfileColumns).eq('id', uid).maybeSingle();
        return row == null ? null : PublicProfile.fromJson(row);
      });

  @override
  Future<String> fetchMyPhone() => _guard(() async {
        final row = await _db.from('profiles_private').select('phone').eq('id', _uid).maybeSingle();
        return asString(row?['phone']);
      });

  @override
  Future<PublicProfile> saveMyProfile({
    required String name,
    required String company,
    required UserRole role,
    required String city,
    required String phone,
  }) =>
      _guard(() async {
        final uid = _uid;
        final row = await _db
            .from('profiles')
            .upsert({'id': uid, 'name': name, 'company': company, 'role': role.name, 'city': city})
            .select(kProfileColumns)
            .single();
        await _db.from('profiles_private').upsert({'id': uid, 'phone': phone});
        return PublicProfile.fromJson(row);
      });

  @override
  Future<PublicProfile?> fetchProfile(String userId) => _guard(() async {
        final row = await _db.from('profiles').select(kProfileColumns).eq('id', userId).maybeSingle();
        return row == null ? null : PublicProfile.fromJson(row);
      });

  @override
  Future<List<PublicProfile>> fetchProfiles(List<String> ids) => _guard(() async {
        if (ids.isEmpty) return <PublicProfile>[];
        final rows = await _db.from('profiles').select(kProfileColumns).inFilter('id', ids);
        return [for (final r in rows) PublicProfile.fromJson(r)];
      });

  @override
  Future<List<Rating>> fetchRatingsFor(String userId) => _guard(() async {
        final rows =
            await _db.from('ratings').select().eq('to_id', userId).order('created_at', ascending: false).limit(50);
        return [for (final r in rows) Rating.fromJson(r)];
      });

  @override
  Future<Set<String>> fetchMyRatedDealIds() => _guard(() async {
        final rows = await _db.from('ratings').select('deal_id').eq('from_id', _uid);
        return {for (final r in rows) asString(r['deal_id'])};
      });

  @override
  Future<UsageInfo> fetchUsage() => _guard(() async => UsageInfo.fromJson(await _rpcMap('my_usage', {})));

  // ───────────── İlanlar ─────────────

  @override
  Future<List<Listing>> fetchListings(ListingKind kind) => _guard(() async {
        var query = _db.from(_table(kind)).select(_listingSelect);
        if (kind == ListingKind.yuk) {
          final today = dateOnly(DateTime.now());
          final uid = userId;
          query = uid == null ? query.gte('load_date', today) : query.or('owner_id.eq.$uid,load_date.gte.$today');
        }
        final rows = await query.order('created_at', ascending: false).limit(kind == ListingKind.malzeme ? 400 : 300);
        return [for (final r in rows) Listing.fromJson(kind, r)];
      });

  @override
  Future<Listing> saveListing(Listing listing, {required bool isNew}) => _guard(() async {
        final kind = listing.kind;
        final table = _table(kind);
        final Map<String, dynamic> row;
        if (kind == ListingKind.sicil) {
          row = await _db
              .from(table)
              .upsert({...listing.toRow(), 'owner_id': _uid}, onConflict: 'owner_id')
              .select(_listingSelect)
              .single();
        } else if (isNew && isUuid(listing.id)) {
          // Kimlik cihazda üretildi. Önceki gönderim sunucuya ulaşıp yanıtı
          // kaybolduysa ilan zaten vardır: ikinci kez eklenmez, güncellenir.
          final existing = await _db.from(table).select('id').eq('id', listing.id).maybeSingle();
          row = existing != null
              ? await _db.from(table).update(listing.toRow()).eq('id', listing.id).select(_listingSelect).single()
              : await _db.from(table).insert({...listing.toRow(), 'id': listing.id}).select(_listingSelect).single();
        } else if (isNew) {
          row = await _db.from(table).insert(listing.toRow()).select(_listingSelect).single();
        } else {
          row = await _db.from(table).update(listing.toRow()).eq('id', listing.id).select(_listingSelect).single();
        }
        return Listing.fromJson(kind, row);
      });

  @override
  Future<void> setListingStatus(ListingKind kind, String id, ListingStatus status) =>
      _guard(() => _db.from(_table(kind)).update({'status': status.name}).eq('id', id));

  @override
  Future<void> deleteListing(ListingKind kind, String id) => _guard(() => _db.from(_table(kind)).delete().eq('id', id));

  @override
  Future<void> setMachineAvailable(String id, bool available) =>
      _guard(() => _db.from('machines').update({'available': available}).eq('id', id));

  @override
  Future<DateTime> boostListing(ListingKind kind, String id, BoostOption option) => _guard(() async {
        final result = await _db.rpc<dynamic>('boost_listing', params: {
          'p_kind': kind.name,
          'p_id': id,
          'p_option': option.name,
        });
        return asDate(result);
      });

  // ───────────── İletişim hakkı ─────────────

  @override
  Future<Set<String>> fetchUnlockedKeys() => _guard(() async {
        final rows = await _db.from('unlocks').select('ref_type,ref_id').eq('user_id', _uid);
        return {for (final r in rows) '${r['ref_type']}:${r['ref_id']}'};
      });

  @override
  Future<UnlockResult> unlock(ListingKind kind, String id, {bool useCredit = false}) => _guard(() async =>
      UnlockResult.fromJson(
          await _rpcMap('unlock_listing', {'p_kind': kind.name, 'p_id': id, 'p_use_credit': useCredit})));

  @override
  Future<ContactInfo> contactFor(String refType, String refId) => _guard(() async =>
      ContactInfo.fromJson(await _rpcMap('contact_for', {'p_ref_type': refType, 'p_ref_id': refId})));

  // ───────────── Teklif / talep ─────────────

  @override
  Future<List<TradeRequest>> fetchRequests() => _guard(() async {
        final rows =
            await _db.from('requests').select(_requestSelect).order('updated_at', ascending: false).limit(300);
        return [for (final r in rows) TradeRequest.fromJson(r)];
      });

  @override
  Future<TradeRequest> createRequest(RequestDraft draft, {String? opId}) => _guard(() async {
        final row = await _rpcMap('create_request', {
          'p_kind': draft.kind.name,
          'p_listing_id': draft.listingId,
          'p_amount': draft.amount,
          'p_quantity': draft.quantity,
          'p_unit': draft.unit,
          'p_start_date': draft.startDate == null ? null : dateOnly(draft.startDate!),
          'p_address': draft.address,
          'p_note': draft.note,
          'p_op_id': opId,
        });
        return TradeRequest.fromJson(row);
      });

  @override
  Future<String?> respondRequest(String id, {required bool accept, String? opId}) => _guard(() async {
        final result = await _rpcMap('respond_request', {'p_id': id, 'p_accept': accept, 'p_op_id': opId});
        final dealId = result['deal_id'];
        return dealId == null ? null : asString(dealId);
      });

  @override
  Future<void> withdrawRequest(String id) => _guard(() => _db.rpc<dynamic>('withdraw_request', params: {'p_id': id}));

  // ───────────── Anlaşmalar ─────────────

  @override
  Future<List<Deal>> fetchDeals() => _guard(() async {
        final rows = await _db.from('deals').select().order('updated_at', ascending: false).limit(300);
        return [for (final r in rows) Deal.fromJson(r)];
      });

  @override
  Future<Deal> createDeal(DealDraft draft) => _guard(() async => Deal.fromJson(await _rpcMap('create_deal', {
            'p_title': draft.title,
            'p_details': draft.details,
            'p_my_side': draft.iAmCustomer ? 'customer' : 'provider',
            'p_counterparty_name': draft.counterpartyName,
            'p_amount': draft.amount,
            'p_payment_method': draft.paymentMethod.name,
            'p_payment_terms': draft.paymentTerms,
            'p_start_date': draft.startDate == null ? null : dateOnly(draft.startDate!),
            'p_milestones': [
              for (final m in draft.milestones) {'title': m.title, 'amount': m.amount},
            ],
          })));

  @override
  Future<Deal> joinDeal(String code) => _guard(() async {
        // Yanlış kodda sunucu boş sonuç döner (deneme sayısı sınırlıdır).
        final row = await _rpcMap('join_deal', {'p_code': code.trim().toUpperCase()});
        if (asString(row['id']).isEmpty) throw const BackendException('NOT_FOUND');
        return Deal.fromJson(row);
      });

  @override
  Future<Deal> dealAction(String id, DealAction action, {int? index, String? note, String? opId}) =>
      _guard(() async => Deal.fromJson(await _rpcMap('deal_action', {
            'p_id': id,
            'p_action': action.wire,
            'p_index': index,
            'p_note': note,
            'p_op_id': opId,
          })));

  @override
  Future<void> rateDeal(String dealId, int stars, String comment, {String? opId}) => _guard(() => _db.rpc<dynamic>(
      'rate_deal', params: {'p_deal': dealId, 'p_stars': stars, 'p_comment': comment, 'p_op_id': opId}));

  // ───────────── Güvenlik ─────────────

  @override
  Future<void> report(String targetType, String targetId, String reason, String note) => _guard(() => _db.rpc<dynamic>(
      'report_content', params: {'p_type': targetType, 'p_id': targetId, 'p_reason': reason, 'p_note': note}));

  @override
  Future<Set<String>> fetchBlockedIds() => _guard(() async {
        final rows = await _db.from('blocks').select('blocked_id').eq('blocker_id', _uid);
        return {for (final r in rows) asString(r['blocked_id'])};
      });

  @override
  Future<void> block(String userId) =>
      _guard(() => _db.from('blocks').upsert({'blocker_id': _uid, 'blocked_id': userId}));

  @override
  Future<void> unblock(String userId) =>
      _guard(() => _db.from('blocks').delete().eq('blocker_id', _uid).eq('blocked_id', userId));

  // ───────────── Bildirimler ─────────────

  @override
  Future<List<AppNotification>> fetchNotifications() => _guard(() async {
        final rows =
            await _db.from('notifications').select().order('created_at', ascending: false).limit(100);
        return [for (final r in rows) AppNotification.fromJson(r)];
      });

  @override
  Future<void> markNotificationsRead() => _guard(() => _db.rpc<dynamic>('mark_notifications_read'));

  // ───────────── Mağaza ─────────────

  @override
  Future<VerifyResult> verifyPurchase(StoreClaim claim) async {
    try {
      final response =
          await _db.functions.invoke('verify-purchase', body: claim.toJson()).timeout(const Duration(seconds: 30));
      final data = asMap(response.data);
      return VerifyResult(
        ok: asBool(data['ok']),
        error: asString(data['error']),
        premiumUntil: asDateOrNull(data['premium_until']),
        credits: data['credits'] == null ? null : asInt(data['credits']),
      );
    } on FunctionException catch (e) {
      final details = asMap(e.details);
      final error = asString(details['error']);
      if (error.isNotEmpty) return VerifyResult(ok: false, error: error);
      // Gövdesiz yanıt: oturum (401) veya sunucu (5xx) sorunu; ikisi de geçicidir, yeniden denenir.
      return VerifyResult(ok: false, error: e.status == 401 ? 'AUTH' : 'SERVER');
    } catch (e) {
      final mapped = BackendException.from(e);
      return VerifyResult(ok: false, error: mapped.code == 'UNKNOWN' ? 'SERVER' : 'NETWORK');
    }
  }

  @override
  Future<void> resetLocalData() async {}
}
