import '../models/models.dart';
import '../models/trade.dart';

export '../models/trade.dart';

/// Meslek ↔ mevcut pazar rolü eşlemesi (ilan sistemi aynı kalır).
UserRole listingRoleOf(TradeProfession p) => switch (p) {
  TradeProfession.nakliyeci || TradeProfession.sefor => UserRole.nakliyeci,
  TradeProfession.yukSahibi => UserRole.yukSahibi,
  TradeProfession.makineSahibi => UserRole.makineSahibi,
  TradeProfession.tedarikci || TradeProfession.satinAlma => UserRole.tedarikci,
  TradeProfession.muteahhit ||
  TradeProfession.taseron ||
  TradeProfession.muhendis ||
  TradeProfession.mimar ||
  TradeProfession.santiyeSefi ||
  TradeProfession.insaatMuhendisi ||
  TradeProfession.elektrikMuhendisi ||
  TradeProfession.makineMuhendisi ||
  TradeProfession.haritaMuhendisi ||
  TradeProfession.jeolojiMuhendisi ||
  TradeProfession.metraj => UserRole.muteahhit,
  TradeProfession.operator ||
  TradeProfession.vincOperatoru => UserRole.makineSahibi,
  _ => UserRole.personel,
};

TradeProfession professionFromRole(UserRole role) => switch (role) {
  UserRole.nakliyeci => TradeProfession.nakliyeci,
  UserRole.yukSahibi => TradeProfession.yukSahibi,
  UserRole.makineSahibi => TradeProfession.makineSahibi,
  UserRole.muteahhit => TradeProfession.muteahhit,
  UserRole.tedarikci => TradeProfession.tedarikci,
  UserRole.personel => TradeProfession.operator,
};

List<WorkSector> defaultSectorsFor(UserRole role) => switch (role) {
  UserRole.nakliyeci => const [WorkSector.nakliye, WorkSector.hafriyat],
  UserRole.yukSahibi => const [WorkSector.nakliye, WorkSector.ustyapi],
  UserRole.makineSahibi => const [WorkSector.hafriyat, WorkSector.altyapi],
  UserRole.muteahhit => const [WorkSector.ustyapi, WorkSector.altyapi],
  UserRole.tedarikci => const [WorkSector.betonSantrali, WorkSector.ustyapi],
  UserRole.personel => const [WorkSector.hafriyat, WorkSector.ustyapi],
};

WorkSector listingKindSector(ListingKind kind) => switch (kind) {
  ListingKind.yuk => WorkSector.nakliye,
  ListingKind.makine => WorkSector.hafriyat,
  ListingKind.malzeme => WorkSector.betonSantrali,
  ListingKind.personel => WorkSector.ustyapi,
  ListingKind.sicil => WorkSector.hafriyat,
};
