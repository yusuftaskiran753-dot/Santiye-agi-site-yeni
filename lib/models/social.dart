import 'models.dart';
import 'trade.dart';

enum SocialPostKind {
  work('İş paylaşımı'),
  jobSeek('İş arıyorum'),
  machineSeek('Makine arıyorum'),
  listing('İlan'),
  tender('İhale');

  const SocialPostKind(this.label);
  final String label;
}

enum CommentVerdict { published, filtered, pendingModeration }

enum TenderStatus {
  open('Açık'),
  closed('Kapandı'),
  awarded('Verildi');

  const TenderStatus(this.label);
  final String label;
}

enum ModerationStatus {
  published('Yayında'),
  pending('Moderasyonda'),
  rejected('Reddedildi');

  const ModerationStatus(this.label);
  final String label;
}

class SocialIdentity {
  const SocialIdentity({
    required this.userId,
    required this.profession,
    required this.sectors,
  });

  final String userId;
  final TradeProfession profession;
  final List<WorkSector> sectors;

  bool get isComplete => sectors.isNotEmpty;

  factory SocialIdentity.fromJson(Map<String, dynamic> j) => SocialIdentity(
    userId: asString(j['user_id']),
    profession: TradeCatalog.professionByName(j['profession']),
    sectors: [
      for (final n in asStringList(j['sectors'])) TradeCatalog.sectorByName(n),
    ],
  );

  Map<String, dynamic> toJson() => {
    'user_id': userId,
    'profession': profession.name,
    'sectors': [for (final s in sectors) s.name],
  };
}

class SocialPost {
  SocialPost({
    required this.id,
    required this.authorId,
    required this.kind,
    required this.caption,
    required this.sectors,
    this.photoPath = '',
    this.listingKind,
    this.listingId,
    this.tenderId,
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now();

  final String id;
  final String authorId;
  final SocialPostKind kind;
  final String caption;
  final List<WorkSector> sectors;
  final String photoPath;
  final ListingKind? listingKind;
  final String? listingId;
  final String? tenderId;
  final DateTime createdAt;

  factory SocialPost.fromJson(Map<String, dynamic> j) => SocialPost(
    id: asString(j['id']),
    authorId: asString(j['author_id']),
    kind: enumByName(SocialPostKind.values, j['kind'], SocialPostKind.work),
    caption: asString(j['caption']),
    sectors: [
      for (final n in asStringList(j['sectors'])) TradeCatalog.sectorByName(n),
    ],
    photoPath: asString(j['photo_path']),
    listingKind: j['listing_kind'] == null
        ? null
        : enumByName(ListingKind.values, j['listing_kind'], ListingKind.yuk),
    listingId: j['listing_id'] == null ? null : asString(j['listing_id']),
    tenderId: j['tender_id'] == null ? null : asString(j['tender_id']),
    createdAt: asDateOrNull(j['created_at']),
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'author_id': authorId,
    'kind': kind.name,
    'caption': caption,
    'sectors': [for (final s in sectors) s.name],
    'photo_path': photoPath,
    'listing_kind': listingKind?.name,
    'listing_id': listingId,
    'tender_id': tenderId,
    'created_at': isoOrNull(createdAt),
  };
}

class SocialComment {
  SocialComment({
    required this.id,
    required this.postId,
    required this.authorId,
    required this.text,
    this.negative = false,
    this.workedTogether = false,
    this.evidenceNote = '',
    this.status = ModerationStatus.published,
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now();

  final String id;
  final String postId;
  final String authorId;
  final String text;
  final bool negative;
  final bool workedTogether;
  final String evidenceNote;
  final ModerationStatus status;
  final DateTime createdAt;

  factory SocialComment.fromJson(Map<String, dynamic> j) => SocialComment(
    id: asString(j['id']),
    postId: asString(j['post_id']),
    authorId: asString(j['author_id']),
    text: asString(j['text']),
    negative: asBool(j['negative']),
    workedTogether: asBool(j['worked_together']),
    evidenceNote: asString(j['evidence_note']),
    status: enumByName(
      ModerationStatus.values,
      j['status'],
      ModerationStatus.published,
    ),
    createdAt: asDateOrNull(j['created_at']),
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'post_id': postId,
    'author_id': authorId,
    'text': text,
    'negative': negative,
    'worked_together': workedTogether,
    'evidence_note': evidenceNote,
    'status': status.name,
    'created_at': isoOrNull(createdAt),
  };
}

class ChatThread {
  ChatThread({
    required this.id,
    required this.userA,
    required this.userB,
    DateTime? updatedAt,
  }) : updatedAt = updatedAt ?? DateTime.now();

  final String id;
  final String userA;
  final String userB;
  final DateTime updatedAt;

  String otherId(String me) => userA == me ? userB : userA;

  factory ChatThread.fromJson(Map<String, dynamic> j) => ChatThread(
    id: asString(j['id']),
    userA: asString(j['user_a']),
    userB: asString(j['user_b']),
    updatedAt: asDateOrNull(j['updated_at']),
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'user_a': userA,
    'user_b': userB,
    'updated_at': isoOrNull(updatedAt),
  };
}

class ChatMessage {
  ChatMessage({
    required this.id,
    required this.threadId,
    required this.senderId,
    required this.text,
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now();

  final String id;
  final String threadId;
  final String senderId;
  final String text;
  final DateTime createdAt;

  factory ChatMessage.fromJson(Map<String, dynamic> j) => ChatMessage(
    id: asString(j['id']),
    threadId: asString(j['thread_id']),
    senderId: asString(j['sender_id']),
    text: asString(j['text']),
    createdAt: asDateOrNull(j['created_at']),
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'thread_id': threadId,
    'sender_id': senderId,
    'text': text,
    'created_at': isoOrNull(createdAt),
  };
}

class Tender {
  Tender({
    required this.id,
    required this.ownerId,
    required this.title,
    required this.detail,
    required this.city,
    required this.sectors,
    required this.allowedProfessions,
    this.status = TenderStatus.open,
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now();

  final String id;
  final String ownerId;
  final String title;
  final String detail;
  final String city;
  final List<WorkSector> sectors;
  final List<TradeProfession> allowedProfessions;
  final TenderStatus status;
  final DateTime createdAt;

  bool allows(TradeProfession p) => allowedProfessions.contains(p);

  factory Tender.fromJson(Map<String, dynamic> j) => Tender(
    id: asString(j['id']),
    ownerId: asString(j['owner_id']),
    title: asString(j['title']),
    detail: asString(j['detail']),
    city: asString(j['city']),
    sectors: [
      for (final n in asStringList(j['sectors'])) TradeCatalog.sectorByName(n),
    ],
    allowedProfessions: [
      for (final n in asStringList(j['allowed_professions']))
        TradeCatalog.professionByName(n),
    ],
    status: enumByName(TenderStatus.values, j['status'], TenderStatus.open),
    createdAt: asDateOrNull(j['created_at']),
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'owner_id': ownerId,
    'title': title,
    'detail': detail,
    'city': city,
    'sectors': [for (final s in sectors) s.name],
    'allowed_professions': [for (final p in allowedProfessions) p.name],
    'status': status.name,
    'created_at': isoOrNull(createdAt),
  };
}

class TenderBid {
  TenderBid({
    required this.id,
    required this.tenderId,
    required this.bidderId,
    required this.amount,
    required this.note,
    this.referenceNote = '',
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now();

  final String id;
  final String tenderId;
  final String bidderId;
  final double amount;
  final String note;
  final String referenceNote;
  final DateTime createdAt;

  factory TenderBid.fromJson(Map<String, dynamic> j) => TenderBid(
    id: asString(j['id']),
    tenderId: asString(j['tender_id']),
    bidderId: asString(j['bidder_id']),
    amount: asDouble(j['amount']),
    note: asString(j['note']),
    referenceNote: asString(j['reference_note']),
    createdAt: asDateOrNull(j['created_at']),
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'tender_id': tenderId,
    'bidder_id': bidderId,
    'amount': amount,
    'note': note,
    'reference_note': referenceNote,
    'created_at': isoOrNull(createdAt),
  };
}

class BlockRecord {
  const BlockRecord({
    required this.userId,
    required this.reason,
    required this.at,
  });

  final String userId;
  final String reason;
  final DateTime at;

  factory BlockRecord.fromJson(Map<String, dynamic> j) => BlockRecord(
    userId: asString(j['user_id']),
    reason: asString(j['reason']),
    at: asDate(j['at']),
  );

  Map<String, dynamic> toJson() => {
    'user_id': userId,
    'reason': reason,
    'at': isoOrNull(at),
  };
}
