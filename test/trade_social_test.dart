import 'package:flutter_test/flutter_test.dart';
import 'package:santiye_agi/logic/social_rules.dart';
import 'package:santiye_agi/models/models.dart';
import 'package:santiye_agi/models/social.dart';
import 'package:santiye_agi/models/trade.dart';
import 'package:santiye_agi/services/backend.dart';
import 'package:santiye_agi/services/local_backend.dart';
import 'package:santiye_agi/services/local_store.dart';
import 'package:santiye_agi/state/app_state.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<AppState> _signedIn(TradeProfession profession) async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  final store = LocalStore(prefs);
  final app = AppState(LocalBackend(store, simulate: false), store);
  await app.init();
  await app.completeOnboarding(
    name: 'Ahmet Yılmaz',
    company: 'Yılmaz İnşaat',
    role: UserRole.muteahhit,
    city: 'Ankara',
    phone: '+905551234567',
    profession: profession,
    sectors: const [WorkSector.insaat, WorkSector.hafriyat],
  );
  return app;
}

Future<void> _expectCode(Future<Object?> future, String code, [String? text]) async {
  try {
    await future;
    fail('$code bekleniyordu');
  } on BackendException catch (e) {
    expect(e.code, code);
    if (text != null) expect(e.detail, contains(text));
  }
}

Tender _tender({
  String owner = 'me',
  TenderStatus status = TenderStatus.open,
  DateTime? closesAt,
}) => Tender(
  id: 't1',
  ownerId: owner,
  title: 'Temel kazısı',
  detail: 'Detay',
  city: 'Ankara',
  sectors: const [WorkSector.hafriyat],
  allowedProfessions: const [TradeProfession.taseron],
  status: status,
  closesAt: closesAt,
);

TenderBid _bid(String id, double amount, {String bidder = 'b', DateTime? at, bool approved = false}) =>
    TenderBid(
      id: id,
      tenderId: 't1',
      bidderId: bidder,
      amount: amount,
      note: 'Malzeme ve işçilik dâhil',
      contactApproved: approved,
      createdAt: at,
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Yorum kuralları', () {
    CommentReview review({
      String text = 'Güvenilir bir firma',
      bool negative = false,
      bool worked = true,
      bool answered = true,
      String note = '',
      bool photo = false,
    }) => SocialRules.reviewComment(
      text: text,
      negative: negative,
      workedTogether: worked,
      evidenceNote: note,
      workedAnswered: answered,
      hasEvidencePhoto: photo,
    );

    test('küfürlü yorum engellenir (harf sansürü dâhil)', () {
      expect(review(text: 'sen s.k adamsın').verdict, CommentVerdict.filtered);
      expect(review(text: 'a m k').verdict, CommentVerdict.filtered);
      expect(review(text: 'iyi', note: 'orospu').verdict, CommentVerdict.filtered);
    });

    test('"Çalıştın mı?" yanıtlanmadan yorum yayınlanmaz', () {
      final r = review(answered: false);
      expect(r.verdict, CommentVerdict.evidenceRequired);
      expect(r.status, ModerationStatus.rejected);
    });

    test('Hayır denirse kanıt şart: kanıtsız yorum kaydedilmez', () {
      final r = review(worked: false);
      expect(r.verdict, CommentVerdict.evidenceRequired);
      expect(r.message, contains('kanıt'));
    });

    test('Hayır + fotoğraf veya açıklama kanıtı ile olumlu yorum yayınlanır', () {
      expect(review(worked: false, photo: true).verdict, CommentVerdict.published);
      expect(review(worked: false, note: 'Aynı şantiyede gördüm').verdict, CommentVerdict.published);
    });

    test('Evet denirse olumlu yorum doğrudan yayınlanır', () {
      expect(review().verdict, CommentVerdict.published);
    });

    test('Olumsuz yorum, çalışılmadıysa ya da kanıtsızsa incelemeye düşer', () {
      expect(review(negative: true).verdict, CommentVerdict.pendingModeration);
      expect(review(negative: true, worked: false, photo: true).verdict, CommentVerdict.pendingModeration);
      expect(review(negative: true, note: 'Sözleşme 12.03').verdict, CommentVerdict.published);
      expect(review(negative: true, photo: true).verdict, CommentVerdict.published);
    });

    test('boş yorum reddedilir', () {
      expect(review(text: '  ').verdict, CommentVerdict.filtered);
    });
  });

  group('İhale kuralları', () {
    test('teklifte açıklama zorunludur', () {
      expect(SocialRules.reviewBid(amount: 1000, note: ''), contains('zorunlu'));
      expect(SocialRules.reviewBid(amount: 1000, note: 'kısa'), contains('en az'));
      expect(SocialRules.reviewBid(amount: 0, note: 'Malzeme ve işçilik dâhil'), contains('tutar'));
      expect(SocialRules.reviewBid(amount: 1000, note: 'sen salak mısın ya'), isNotNull);
      expect(SocialRules.reviewBid(amount: 1000, note: 'Malzeme ve işçilik dâhil'), isNull);
    });

    test('telefon yalnızca ihaleyi açan onaylarsa ve yalnız iki tarafa görünür', () {
      final t = _tender();
      final waiting = _bid('b1', 100);
      final approved = _bid('b1', 100, approved: true);
      for (final viewer in ['me', 'b', 'baskasi']) {
        expect(SocialRules.canRevealPhone(tender: t, bid: waiting, viewerId: viewer), isFalse);
      }
      expect(SocialRules.canRevealPhone(tender: t, bid: approved, viewerId: 'me'), isTrue);
      expect(SocialRules.canRevealPhone(tender: t, bid: approved, viewerId: 'b'), isTrue);
      expect(SocialRules.canRevealPhone(tender: t, bid: approved, viewerId: 'baskasi'), isFalse);
    });

    test('en iyi teklif en düşük tutardır; eşitlikte ilk verilen', () {
      final a = _bid('a', 500, at: DateTime(2026, 1, 2));
      final b = _bid('b', 400, at: DateTime(2026, 1, 3));
      final c = _bid('c', 400, at: DateTime(2026, 1, 1));
      expect(SocialRules.bestBid([a, b, c])!.id, 'c');
      expect(SocialRules.bestBid(const []), isNull);
    });

    test('süresi dolan veya kapanan ihaleye teklif verilemez', () {
      final past = DateTime.now().subtract(const Duration(hours: 1));
      final future = DateTime.now().add(const Duration(days: 1));
      expect(_tender(closesAt: future).acceptsBids(), isTrue);
      expect(_tender(closesAt: past).acceptsBids(), isFalse);
      expect(_tender(closesAt: past).needsAward(), isTrue);
      expect(_tender(status: TenderStatus.closed).needsAward(), isTrue);
      expect(_tender().needsAward(), isFalse);
      expect(
        SocialRules.canBid(
          tender: _tender(status: TenderStatus.closed),
          profession: TradeProfession.taseron,
          myId: 'x',
        ),
        isFalse,
      );
    });

    test('eski kayıtlar (yeni alanlar olmadan) okunur', () {
      final bid = TenderBid.fromJson({'id': 'x', 'tender_id': 't', 'bidder_id': 'b', 'amount': 5, 'note': 'n'});
      expect(bid.contactApproved, isFalse);
      expect(bid.decision, BidStatus.pending);
      final t = Tender.fromJson({'id': 't', 'owner_id': 'o', 'title': 'a', 'detail': 'b', 'city': 'c'});
      expect(t.awardedBidId, isNull);
      expect(t.closesAt, isNull);
      expect(BlockRecord.fromJson({'user_id': 'u', 'reason': 'r', 'at': '2026-01-01T00:00:00Z'}).evidencePhotoPath, '');
    });
  });

  group('Mesajlar 24 saat içinde silinir', () {
    test('süre dolunca mesaj ömrünü tamamlar', () {
      final m = ChatMessage(id: '1', threadId: 't', senderId: 'a', text: 'x');
      expect(m.isExpired(), isFalse);
      expect(m.isExpired(DateTime.now().add(const Duration(hours: 23))), isFalse);
      expect(m.isExpired(DateTime.now().add(const Duration(hours: 24, seconds: 1))), isTrue);
    });

    test('depodan süresi dolan mesajlar silinir', () async {
      final app = await _signedIn(TradeProfession.taseron);
      final old = ChatMessage(
        id: 'old',
        threadId: 'th',
        senderId: 'demo-u8',
        text: 'eski',
        createdAt: DateTime.now().subtract(const Duration(hours: 25)),
      );
      final fresh = ChatMessage(id: 'new', threadId: 'th', senderId: 'demo-u8', text: 'yeni');
      app.social.messages = [old, fresh];
      await app.social.persistChat();
      app.social.load();
      expect(app.social.messages.map((m) => m.id), ['new']);
      await app.social.purgeExpiredMessages();
      expect(app.messagesOf('th').map((m) => m.id), ['new']);
    });
  });

  group('AppState: ihale akışı', () {
    test('teklif: açıklamasız kabul edilmez, tek teklif, onaysız telefon gizli', () async {
      final app = await _signedIn(TradeProfession.taseron);
      final tender = app.social.tenders.first; // örnek ihale (demo-u18 açtı)
      await _expectCode(
        app.bidTender(tender: tender, amount: 1000, note: '', referenceNote: ''),
        'BAD_INPUT',
        'zorunlu',
      );
      final bid = await app.bidTender(
        tender: tender,
        amount: 125000,
        note: 'Malzeme ve işçilik dâhil, 10 gün',
        referenceNote: '',
      );
      expect(bid.contactApproved, isFalse);
      await _expectCode(
        app.bidTender(tender: tender, amount: 1, note: 'Malzeme ve işçilik dâhil', referenceNote: ''),
        'BAD_STATE',
      );
      // Teklif sahibi de, ihaleyi açan onaylamadan karşı tarafın numarasını göremez.
      await _expectCode(app.contactForTenderBid(tender, bid), 'FORBIDDEN');
      // Teklif sahibi, ihaleyi açan olmadığı için onay veremez.
      await _expectCode(app.approveBidContact(tender.id, bid.id), 'FORBIDDEN');
    });

    test('ihaleyi açan onaylar, süre bitince en iyi teklifi seçer', () async {
      final app = await _signedIn(TradeProfession.muteahhit);
      final tender = await app.createTender(
        title: 'Altyapı hattı kazısı',
        detail: 'Saha kazısı ve dolgu işi',
        city: 'Ankara',
        sectors: const [WorkSector.altyapi],
        allowed: const [TradeProfession.taseron],
      );
      app.social.bids.addAll([
        TenderBid(id: 'b1', tenderId: tender.id, bidderId: 'demo-w3', amount: 90000, note: 'Malzeme dâhil, 12 gün'),
        TenderBid(id: 'b2', tenderId: tender.id, bidderId: 'demo-w2', amount: 80000, note: 'Malzeme hariç, 9 gün'),
      ]);

      // Onaydan önce kimsenin numarası görünmez.
      final b1 = app.social.bidsFor(tender.id).firstWhere((b) => b.id == 'b1');
      await _expectCode(app.contactForTenderBid(tender, b1), 'FORBIDDEN');

      // İhale hâlâ açıkken kazanan seçilemez.
      await _expectCode(app.awardTender(tender.id, 'b2'), 'BAD_STATE');

      await app.approveBidContact(tender.id, 'b1');
      final approved = app.social.bidsFor(tender.id).firstWhere((b) => b.id == 'b1');
      final contact = await app.contactForTenderBid(tender, approved);
      expect(contact.name, isNotEmpty);

      await app.closeTender(tender.id);
      final closed = app.social.tenderById(tender.id)!;
      expect(closed.status, TenderStatus.closed);
      expect(closed.needsAward(), isTrue);
      expect(SocialRules.bestBid(app.social.bidsFor(tender.id))!.id, 'b2');

      await app.awardTender(tender.id, 'b2');
      final done = app.social.tenderById(tender.id)!;
      expect(done.status, TenderStatus.awarded);
      expect(done.awardedBidId, 'b2');
      final bids = {for (final b in app.social.bidsFor(tender.id)) b.id: b};
      expect(bids['b2']!.decision, BidStatus.selected);
      expect(bids['b2']!.contactApproved, isTrue);
      expect(bids['b1']!.decision, BidStatus.notSelected);
      await _expectCode(app.awardTender(tender.id, 'b1'), 'BAD_STATE');
    });

    test('ihaleyi açmayan kişi kapatamaz ve kazanan seçemez', () async {
      final app = await _signedIn(TradeProfession.taseron);
      final tender = app.social.tenders.first;
      await _expectCode(app.closeTender(tender.id), 'FORBIDDEN');
      await _expectCode(app.awardTender(tender.id, 'x'), 'FORBIDDEN');
    });
  });

  group('AppState: yorum ve engelleme', () {
    test('küfürlü ve kanıtsız yorum kaydedilmez, kanıtlı olan kaydedilir', () async {
      final app = await _signedIn(TradeProfession.taseron);
      final post = app.social.posts.first;
      Future<CommentReview> send(String text, {bool answered = true, bool worked = true, String photo = ''}) =>
          app.addComment(
            postId: post.id,
            text: text,
            negative: false,
            workedTogether: worked,
            evidenceNote: '',
            workedAnswered: answered,
            evidencePhotoPath: photo,
          );

      expect((await send('s.i.k.t.i.r')).verdict, CommentVerdict.filtered);
      expect((await send('Güzel iş', answered: false)).verdict, CommentVerdict.evidenceRequired);
      expect((await send('Güzel iş', worked: false)).verdict, CommentVerdict.evidenceRequired);
      expect(app.social.publishedComments(post.id), isEmpty);

      expect((await send('Güzel iş', worked: false, photo: '/tmp/kanit.jpg')).verdict, CommentVerdict.published);
      expect((await send('Çok memnun kaldık')).verdict, CommentVerdict.published);
      expect(app.social.publishedComments(post.id).length, 2);
      expect(app.social.publishedComments(post.id).first.evidencePhotoPath, '/tmp/kanit.jpg');
    });

    test('engelleme: sebep ve kanıt fotoğrafı zorunlu', () async {
      final app = await _signedIn(TradeProfession.taseron);
      await _expectCode(app.blockWithProof('demo-u8', reason: '', evidencePhotoPath: '/tmp/a.jpg'), 'BAD_INPUT', 'sebep');
      await _expectCode(app.blockWithProof('demo-u8', reason: 'Hakaret / küfür', evidencePhotoPath: ''), 'BAD_INPUT', 'fotoğraf');
      expect(app.isBlocked('demo-u8'), isFalse);

      await app.blockWithProof('demo-u8', reason: 'Hakaret / küfür', evidencePhotoPath: '/tmp/a.jpg');
      expect(app.isBlocked('demo-u8'), isTrue);
      expect(app.social.blockReasons['demo-u8']!.evidencePhotoPath, '/tmp/a.jpg');
    });
  });
}
