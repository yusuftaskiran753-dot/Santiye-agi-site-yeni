import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:santiye_agi/services/backend.dart';
import 'package:santiye_agi/services/local_store.dart';
import 'package:santiye_agi/services/sync_queue.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Çevrimdışı gönderim sırasının (outbox) birim testleri.

Future<LocalStore> _store([Map<String, Object> initial = const {}]) async {
  SharedPreferences.setMockInitialValues(initial);
  return LocalStore(await SharedPreferences.getInstance());
}

var _seq = 0;

SyncOp _op(SyncOpType type, Map<String, dynamic> payload, {String user = 'u1'}) =>
    SyncOp(id: 'op-${_seq++}', type: type, userId: user, payload: payload);

SyncOp _note(String dealId, String note, {String user = 'u1'}) =>
    _op(SyncOpType.dealAction, {'deal_id': dealId, 'action': 'note', 'note': note}, user: user);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('İşlemler cihazda kalıcıdır: uygulama yeniden açılınca sıra korunur', () async {
    final store = await _store();
    final q = SyncQueue(store);
    await q.enqueue(_note('d1', 'bir'));
    await q.enqueue(_note('d1', 'iki'));

    final reopened = SyncQueue(store);
    expect(reopened.countFor('u1'), 2);
    expect([for (final op in reopened.pendingFor('u1')) op.payload['note']], ['bir', 'iki']);
  });

  test('Sırayla (ilk giren ilk çıkar) gönderilir', () async {
    final q = SyncQueue(await _store());
    for (final n in ['1', '2', '3']) {
      await q.enqueue(_note('d1', n));
    }
    final sent = <String>[];
    final result = await q.flush('u1', (op) async => sent.add(op.payload['note'] as String));
    expect(sent, ['1', '2', '3']);
    expect(result.complete, isTrue);
    expect(result.applied, hasLength(3));
    expect(q.countFor('u1'), 0);
  });

  test('Bağlantı hatasında durur, kalan işlemler sırada bekler (sıra bozulmaz)', () async {
    final q = SyncQueue(await _store());
    for (final n in ['1', '2', '3']) {
      await q.enqueue(_note('d1', n));
    }
    final sent = <String>[];
    final result = await q.flush('u1', (op) async {
      if (op.payload['note'] == '2') throw const BackendException('NETWORK');
      sent.add(op.payload['note'] as String);
    });
    expect(sent, ['1']);
    expect(result.complete, isFalse);
    expect(result.stoppedBy?.code, 'NETWORK');
    expect([for (final op in q.pendingFor('u1')) op.payload['note']], ['2', '3']);
    expect(q.pendingFor('u1').first.attempts, 1);
    expect(q.pendingFor('u1').first.lastError, 'NETWORK');

    // Bağlantı gelince kaldığı yerden devam eder.
    final retry = await q.flush('u1', (op) async => sent.add(op.payload['note'] as String));
    expect(retry.complete, isTrue);
    expect(sent, ['1', '2', '3']);
  });

  test('Sunucu hatası, oturum ve hız sınırı da geçici sayılır', () async {
    for (final code in ['SERVER', 'RATE_LIMIT', 'AUTH_REQUIRED']) {
      final q = SyncQueue(await _store());
      await q.enqueue(_note('d1', 'x'));
      final r = await q.flush('u1', (_) async => throw BackendException(code));
      expect(r.stoppedBy?.code, code);
      expect(q.countFor('u1'), 1, reason: '$code işlemi silmemeli');
    }
  });

  test('Kalıcı ret işlemi sıradan çıkarır, sonrakiler gönderilmeye devam eder', () async {
    final q = SyncQueue(await _store());
    await q.enqueue(_op(SyncOpType.dealAction, {'deal_id': 'd1', 'action': 'deliver'}));
    await q.enqueue(_note('d2', 'devam'));
    final sent = <String>[];
    final result = await q.flush('u1', (op) async {
      if (op.payload['action'] == 'deliver') throw const BackendException('BAD_STATE');
      sent.add(op.payload['deal_id'] as String);
    });
    expect(result.complete, isTrue);
    expect(result.dropped.single.error.code, 'BAD_STATE');
    expect(result.dropped.single.op.type, SyncOpType.dealAction);
    expect(sent, ['d2']);
    expect(q.countFor('u1'), 0);
  });

  test('Tanınmayan hata birkaç kez denenir, sonra bırakılır', () async {
    final q = SyncQueue(await _store(), maxUnknownAttempts: 3);
    await q.enqueue(_note('d1', 'x'));
    Future<void> boom(SyncOp _) async => throw StateError('beklenmeyen');
    expect((await q.flush('u1', boom)).complete, isFalse); // 1. deneme
    expect((await q.flush('u1', boom)).complete, isFalse); // 2. deneme
    final last = await q.flush('u1', boom); // 3. deneme → bırakılır
    expect(last.complete, isTrue);
    expect(last.dropped.single.error.code, 'UNKNOWN');
    expect(q.countFor('u1'), 0);
  });

  test('Yanıtı kaybolmuş işlemin "zaten yapılmış" hatası başarı sayılır', () async {
    final q = SyncQueue(await _store());
    await q.enqueue(_op(SyncOpType.deleteListing, {'kind': 'yuk', 'id': 'L1'}));
    await q.enqueue(_op(SyncOpType.rateDeal, {'deal_id': 'd1', 'stars': 5, 'comment': ''}));
    final r1 = await q.flush('u1', (op) async {
      throw BackendException(op.type == SyncOpType.deleteListing ? 'NOT_FOUND' : 'ALREADY_RATED');
    });
    expect(r1.applied, hasLength(2));
    expect(r1.dropped, isEmpty);

    // Teklif yanıtı: yalnızca daha önce gönderilmeye çalışıldıysa NOT_PENDING "yapılmış" sayılır.
    final fresh = _op(SyncOpType.respondRequest, {'id': 'r1', 'accept': true});
    await q.enqueue(fresh);
    final r2 = await q.flush('u1', (_) async => throw const BackendException('NOT_PENDING'));
    expect(r2.dropped, hasLength(1), reason: 'İlk denemede NOT_PENDING gerçek bir ret');

    final retried = _op(SyncOpType.respondRequest, {'id': 'r2', 'accept': true})..attempts = 1;
    await q.enqueue(retried);
    final r3 = await q.flush('u1', (_) async => throw const BackendException('NOT_PENDING'));
    expect(r3.applied, hasLength(1));
  });

  test('Aynı kaydın son hâli birleştirilir ve sona taşınır', () async {
    final q = SyncQueue(await _store());
    await q.enqueue(_op(SyncOpType.saveListing, {'kind': 'yuk', 'id': 'L1', 'is_new': true, 'listing': {'cargo': 'ilk'}}));
    await q.enqueue(_note('d1', 'arada'));
    await q.enqueue(_op(SyncOpType.saveListing, {'kind': 'yuk', 'id': 'L1', 'is_new': false, 'listing': {'cargo': 'son'}}));

    final ops = q.pendingFor('u1');
    expect(ops, hasLength(2));
    expect(ops.first.type, SyncOpType.dealAction);
    expect(ops.last.payload['listing'], {'cargo': 'son'});
    expect(ops.last.payload['is_new'], isTrue, reason: 'Sunucuya hiç gitmemiş ilan "yeni" olarak gönderilir');
  });

  test('Birleştirme önceki deneme sayısını korur', () async {
    final q = SyncQueue(await _store());
    final first = _op(SyncOpType.saveProfile, {'name': 'A'})..attempts = 2;
    await q.enqueue(first);
    await q.enqueue(_op(SyncOpType.saveProfile, {'name': 'B'}));
    final only = q.pendingFor('u1').single;
    expect(only.payload['name'], 'B');
    expect(only.attempts, 2);
  });

  test('Anlaşma adımları birleştirilmez (her adım ayrı gönderilir)', () async {
    final q = SyncQueue(await _store());
    await q.enqueue(_note('d1', 'a'));
    await q.enqueue(_note('d1', 'a'));
    expect(q.countFor('u1'), 2);
  });

  test('Kullanıcıya özeldir: başka hesabın işlemleri gönderilmez', () async {
    final q = SyncQueue(await _store());
    await q.enqueue(_note('d1', 'benim', user: 'u1'));
    await q.enqueue(_note('d2', 'onun', user: 'u2'));
    final sent = <String>[];
    await q.flush('u1', (op) async => sent.add(op.payload['note'] as String));
    expect(sent, ['benim']);
    expect(q.countFor('u2'), 1);
    expect(q.countFor(null), 0);
    expect((await q.flush(null, (_) async => fail('oturumsuz gönderim'))).applied, isEmpty);

    await q.clearFor('u2');
    expect(q.countFor('u2'), 0);
  });

  test('Eşzamanlı iki gönderim çağrısı aynı işlemi iki kez göndermez', () async {
    final q = SyncQueue(await _store());
    await q.enqueue(_note('d1', 'tek'));
    var calls = 0;
    final gate = Completer<void>();
    Future<void> slow(SyncOp _) async {
      calls++;
      await gate.future;
    }

    final a = q.flush('u1', slow);
    final b = q.flush('u1', slow);
    expect(q.isFlushing, isTrue);
    gate.complete();
    final results = await Future.wait([a, b]);
    expect(calls, 1);
    expect(identical(results[0], results[1]), isTrue);
    expect(q.isFlushing, isFalse);
  });

  test('Bekleyen kayıt sorgusu ve seçerek silme', () async {
    final q = SyncQueue(await _store());
    await q.enqueue(_op(SyncOpType.saveListing, {'kind': 'yuk', 'id': 'L1', 'is_new': true, 'listing': {}}));
    await q.enqueue(_op(SyncOpType.setListingStatus, {'kind': 'yuk', 'id': 'L1', 'status': 'closed'}));
    await q.enqueue(_op(SyncOpType.saveListing, {'kind': 'yuk', 'id': 'L2', 'is_new': true, 'listing': {}}));
    expect(q.hasPendingFor('u1', 'L1'), isTrue);
    expect(q.hasPendingFor('u2', 'L1'), isFalse);
    final removed = await q.removeWhere('u1', (op) => op.refId == 'L1');
    expect(removed, hasLength(2));
    expect(q.hasPendingFor('u1', 'L1'), isFalse);
    expect(q.countFor('u1'), 1);
  });

  test('Bozuk veya tanınmayan kayıtlar yok sayılır', () async {
    final store = await _store({
      'sync_queue_v1': jsonEncode([
        {'id': 'ok', 'type': 'markNotificationsRead', 'user_id': 'u1', 'payload': {}},
        {'id': 'x', 'type': 'bilinmeyenTur', 'user_id': 'u1', 'payload': {}},
        {'type': 'block', 'user_id': 'u1'},
        'çöp',
      ]),
    });
    final q = SyncQueue(store);
    expect(q.pendingFor('u1').map((o) => o.id), ['ok']);

    final broken = await _store({'sync_queue_v1': '{bozuk json'});
    expect(SyncQueue(broken).countFor('u1'), 0);
  });

  test('JSON gidiş-dönüşü bilgileri korur', () {
    final op = SyncOp(
      id: 'abc',
      type: SyncOpType.createRequest,
      userId: 'u1',
      payload: {'listing_id': 'L9', 'draft': {'amount': 1200.5}},
      createdAt: DateTime.utc(2026, 10, 10, 8),
      attempts: 3,
      lastError: 'NETWORK',
    );
    final back = SyncOp.fromJson(jsonDecode(jsonEncode(op.toJson())) as Map<String, dynamic>)!;
    expect(back.id, 'abc');
    expect(back.type, SyncOpType.createRequest);
    expect(back.payload['draft'], {'amount': 1200.5});
    expect(back.createdAt.toUtc(), DateTime.utc(2026, 10, 10, 8));
    expect(back.attempts, 3);
    expect(back.lastError, 'NETWORK');
    expect(back.refId, 'L9');
  });

  test('Bekleme süresi katlanarak artar, 5 dakikayı geçmez', () {
    expect(SyncQueue.backoff(0), const Duration(seconds: 5));
    expect(SyncQueue.backoff(1), const Duration(seconds: 10));
    expect(SyncQueue.backoff(2), const Duration(seconds: 20));
    expect(SyncQueue.backoff(5), const Duration(seconds: 160));
    expect(SyncQueue.backoff(6), const Duration(seconds: 300));
    expect(SyncQueue.backoff(50), const Duration(seconds: 300));
    expect(SyncQueue.backoff(-3), const Duration(seconds: 5));
  });
}
