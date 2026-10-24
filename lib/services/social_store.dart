import '../data/demo_data.dart';
import '../data/trade_catalog.dart';
import '../models/models.dart';
import '../models/social.dart';
import 'local_store.dart';

/// Sosyal katman yalnızca cihazda (dış backend yok).
class SocialStore {
  SocialStore(this._store);

  final LocalStore _store;

  static const _kIdent = 'social_identities';
  static const _kPosts = 'social_posts';
  static const _kComments = 'social_comments';
  static const _kLikes = 'social_likes';
  static const _kFollows = 'social_follows';
  static const _kThreads = 'social_threads';
  static const _kMessages = 'social_messages';
  static const _kTenders = 'social_tenders';
  static const _kBids = 'social_bids';
  static const _kBlocks = 'social_block_reasons';
  static const _kSeed = 'social_seeded_v1';

  final Map<String, SocialIdentity> identities = {};
  List<SocialPost> posts = [];
  List<SocialComment> comments = [];
  /// postId -> liker ids
  Map<String, Set<String>> likes = {};
  /// follower -> following ids
  Map<String, Set<String>> follows = {};
  List<ChatThread> threads = [];
  List<ChatMessage> messages = [];
  List<Tender> tenders = [];
  List<TenderBid> bids = [];
  Map<String, BlockRecord> blockReasons = {};

  void load() {
    identities
      ..clear()
      ..addEntries([
        for (final m in _store.readMaps(_kIdent))
          MapEntry(asString(m['user_id']), SocialIdentity.fromJson(m)),
      ]);
    posts = [for (final m in _store.readMaps(_kPosts)) SocialPost.fromJson(m)];
    comments = [
      for (final m in _store.readMaps(_kComments)) SocialComment.fromJson(m),
    ];
    likes = {
      for (final m in _store.readMaps(_kLikes))
        asString(m['post_id']): asStringList(m['user_ids']).toSet(),
    };
    follows = {
      for (final m in _store.readMaps(_kFollows))
        asString(m['user_id']): asStringList(m['following']).toSet(),
    };
    threads = [for (final m in _store.readMaps(_kThreads)) ChatThread.fromJson(m)];
    messages = [
      for (final m in _store.readMaps(_kMessages)) ChatMessage.fromJson(m),
    ];
    tenders = [for (final m in _store.readMaps(_kTenders)) Tender.fromJson(m)];
    bids = [for (final m in _store.readMaps(_kBids)) TenderBid.fromJson(m)];
    blockReasons = {
      for (final m in _store.readMaps(_kBlocks))
        asString(m['user_id']): BlockRecord.fromJson(m),
    };
  }

  Future<void> seedIfNeeded() async {
    if (_store.prefs.getBool(_kSeed) ?? false) return;
    _seedDemo();
    await persistAll();
    await _store.prefs.setBool(_kSeed, true);
  }

  void _seedDemo() {
    void ident(String id, TradeProfession p, List<WorkSector> s) {
      identities[id] = SocialIdentity(userId: id, profession: p, sectors: s);
    }

    ident('demo-u7', TradeProfession.muteahhit, [
      WorkSector.hafriyat,
      WorkSector.altyapi,
    ]);
    ident('demo-u8', TradeProfession.makineSahibi, [
      WorkSector.hafriyat,
      WorkSector.yolAsfalt,
    ]);
    ident('demo-u17', TradeProfession.muteahhit, [
      WorkSector.yolAsfalt,
      WorkSector.ustyapi,
    ]);
    ident('demo-u18', TradeProfession.muteahhit, [
      WorkSector.altyapi,
      WorkSector.elektrik,
    ]);
    ident('demo-w1', TradeProfession.operator, [WorkSector.hafriyat]);
    ident('demo-w2', TradeProfession.formen, [
      WorkSector.ustyapi,
      WorkSector.betonarme,
    ]);
    ident('demo-w3', TradeProfession.taseron, [
      WorkSector.elektrik,
      WorkSector.ustyapi,
    ]);
    ident('demo-u12', TradeProfession.operator, [WorkSector.hafriyat]);

    posts = [
      SocialPost(
        id: 'sp-1',
        authorId: 'demo-w1',
        kind: SocialPostKind.work,
        caption: 'Bugün 22 tonluk ekskavatörle temel kazısı. Referans için duvarıma ekledim.',
        sectors: const [WorkSector.hafriyat],
      ),
      SocialPost(
        id: 'sp-2',
        authorId: 'demo-u18',
        kind: SocialPostKind.jobSeek,
        caption: 'Altyapı hattı için elektrik taşeronu arıyoruz. İhaleyi de açtık.',
        sectors: const [WorkSector.elektrik, WorkSector.altyapi],
        tenderId: 'tn-1',
      ),
      SocialPost(
        id: 'sp-3',
        authorId: 'demo-u8',
        kind: SocialPostKind.machineSeek,
        caption: 'Ankara’da 3 günlük greyder boş. Operatörlü çalışır.',
        sectors: const [WorkSector.hafriyat, WorkSector.yolAsfalt],
      ),
    ];

    tenders = [
      Tender(
        id: 'tn-1',
        ownerId: 'demo-u18',
        title: 'OSB içme suyu hattı elektrik işi',
        detail: 'Orta gerilim pano + saha kablolama. Keşif dosyası sohbette.',
        city: 'Ankara',
        sectors: const [WorkSector.elektrik, WorkSector.altyapi],
        allowedProfessions: const [
          TradeProfession.taseron,
          TradeProfession.formen,
        ],
      ),
    ];
  }

  SocialIdentity? identityOf(String? userId) =>
      userId == null ? null : identities[userId];

  SocialIdentity identityOrDefault(PublicProfile p) =>
      identities[p.id] ??
      SocialIdentity(
        userId: p.id,
        profession: professionFromRole(p.role),
        sectors: defaultSectorsFor(p.role),
      );

  Future<void> saveIdentity(SocialIdentity identity) async {
    identities[identity.userId] = identity;
    await persistIdentities();
  }

  Set<String> followingOf(String userId) => follows[userId] ?? {};

  bool isFollowing(String me, String other) => followingOf(me).contains(other);

  int likeCount(String postId) => likes[postId]?.length ?? 0;

  bool likedBy(String postId, String userId) =>
      likes[postId]?.contains(userId) ?? false;

  List<SocialComment> publishedComments(String postId) => comments
      .where(
        (c) => c.postId == postId && c.status == ModerationStatus.published,
      )
      .toList()
    ..sort((a, b) => a.createdAt.compareTo(b.createdAt));

  List<TenderBid> bidsFor(String tenderId) =>
      bids.where((b) => b.tenderId == tenderId).toList()
        ..sort((a, b) => a.amount.compareTo(b.amount));

  Future<void> persistIdentities() => _store.writeMaps(_kIdent, [
    for (final i in identities.values) i.toJson(),
  ]);

  Future<void> persistPosts() =>
      _store.writeMaps(_kPosts, [for (final p in posts) p.toJson()]);

  Future<void> persistComments() =>
      _store.writeMaps(_kComments, [for (final c in comments) c.toJson()]);

  Future<void> persistLikes() => _store.writeMaps(_kLikes, [
    for (final e in likes.entries)
      {'post_id': e.key, 'user_ids': e.value.toList()},
  ]);

  Future<void> persistFollows() => _store.writeMaps(_kFollows, [
    for (final e in follows.entries)
      {'user_id': e.key, 'following': e.value.toList()},
  ]);

  Future<void> persistChat() async {
    await _store.writeMaps(_kThreads, [for (final t in threads) t.toJson()]);
    await _store.writeMaps(_kMessages, [for (final m in messages) m.toJson()]);
  }

  Future<void> persistTenders() async {
    await _store.writeMaps(_kTenders, [for (final t in tenders) t.toJson()]);
    await _store.writeMaps(_kBids, [for (final b in bids) b.toJson()]);
  }

  Future<void> persistBlocks() => _store.writeMaps(_kBlocks, [
    for (final b in blockReasons.values) b.toJson(),
  ]);

  Future<void> persistAll() async {
    await persistIdentities();
    await persistPosts();
    await persistComments();
    await persistLikes();
    await persistFollows();
    await persistChat();
    await persistTenders();
    await persistBlocks();
  }

  String displayName(String userId, {PublicProfile? me}) {
    if (me != null && me.id == userId) return me.displayName;
    if (DemoData.isDemoId(userId)) return DemoData.profile(userId).displayName;
    return 'Kullanıcı';
  }
}
