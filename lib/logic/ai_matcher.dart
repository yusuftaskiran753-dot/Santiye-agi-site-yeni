import '../data/cities.dart';
import '../models/models.dart';
import '../services/ai_service.dart';
import '../utils/format.dart';

/// Yapay zekânın anladığı isteğe göre pazar ilanlarını süzer ve sıralar.
/// Saf fonksiyon: ekrandan bağımsız test edilebilir.
class AiMatch {
  const AiMatch(this.items, {this.exact = true});

  final List<Listing> items;

  /// false: tam eşleşme bulunamadı, yakın sonuçlar gösteriliyor.
  final bool exact;
}

AiMatch matchListings(
  AiResult r, {
  required String myCity,
  required List<Load> loads,
  required List<Machine> machines,
  required List<MaterialListing> materials,
  required List<JobPost> jobs,
  required List<WorkerCard> workers,
}) {
  switch (r.category) {
    case ListingKind.yuk:
      return _loads(r, loads.where((l) => l.isOpen).toList());
    case ListingKind.makine:
      return _machines(
        r,
        machines.where((m) => m.isOpen).toList(),
        r.city ?? myCity,
      );
    case ListingKind.malzeme:
      return _materials(
        r,
        materials.where((m) => m.isOpen).toList(),
        r.city ?? myCity,
      );
    case ListingKind.personel:
    case ListingKind.sicil:
      return _people(
        r,
        jobs.where((j) => j.isOpen).toList(),
        workers.where((w) => w.isOpen).toList(),
      );
    case null:
      return const AiMatch([]);
  }
}

AiMatch _loads(AiResult r, List<Load> all) {
  bool fromOk(Load l) => r.fromCity == null || l.fromCity == r.fromCity;
  bool toOk(Load l) => r.toCity == null || l.toCity == r.toCity;
  bool vehicleOk(Load l) => r.vehicle == null || l.vehicle == r.vehicle;
  int byDate(Load a, Load b) {
    if (r.date != null) {
      final da = a.date.difference(r.date!).inHours.abs(),
          db = b.date.difference(r.date!).inHours.abs();
      if (da != db) return da.compareTo(db);
    }
    return a.date.compareTo(b.date);
  }

  final exact = all.where((l) => fromOk(l) && toOk(l) && vehicleOk(l)).toList()
    ..sort(byDate);
  if (exact.isNotEmpty) return AiMatch(exact);
  // Yakın sonuçlar: güzergâhın bir ucu tutan yükler (araç tipi gözetmeden).
  final near =
      all
          .where(
            (l) =>
                (r.fromCity != null && l.fromCity == r.fromCity) ||
                (r.toCity != null && l.toCity == r.toCity),
          )
          .toList()
        ..sort(byDate);
  return AiMatch(near, exact: false);
}

AiMatch _machines(AiResult r, List<Machine> all, String near) {
  final ref = cityLatLng(near);
  final typed = r.machine == null
      ? all
      : all.where((m) => m.type == r.machine).toList();
  int score(Machine a, Machine b) {
    if (a.available != b.available) return a.available ? -1 : 1;
    return roadKm(ref, a.position).compareTo(roadKm(ref, b.position));
  }

  final exact = typed.where((m) => r.city == null || m.city == r.city).toList()
    ..sort(score);
  if (exact.isNotEmpty) return AiMatch(exact);
  return AiMatch(typed.toList()..sort(score), exact: false);
}

AiMatch _materials(AiResult r, List<MaterialListing> all, String near) {
  final q = r.material == null ? null : normalizeTr(r.material!);
  final ref = cityLatLng(near);
  bool productOk(MaterialListing m) =>
      q == null ||
      normalizeTr(
        '${m.product} ${m.materialKind.label}',
      ).contains(q.split('/').first);
  int cheapest(MaterialListing a, MaterialListing b) =>
      a.price.compareTo(b.price);
  final exact =
      all
          .where((m) => productOk(m) && (r.city == null || m.city == r.city))
          .toList()
        ..sort(cheapest);
  if (exact.isNotEmpty) return AiMatch(exact);
  final near2 = all.where(productOk).toList()
    ..sort(
      (a, b) => roadKm(ref, a.position).compareTo(roadKm(ref, b.position)),
    );
  return AiMatch(near2, exact: false);
}

AiMatch _people(AiResult r, List<JobPost> jobs, List<WorkerCard> workers) {
  bool roleOk(WorkerRole role) => r.workerRole == null || role == r.workerRole;
  bool cityOk(String c) => r.city == null || c == r.city;
  // İş ilanı vermek isteyen (işveren) operatör kartlarını, iş arayan iş ilanlarını görmek ister.
  final List<Listing> exact = r.intent == AiIntent.ilanVer
      ? workers.where((w) => roleOk(w.role) && cityOk(w.city)).toList()
      : [
          ...jobs.where((j) => roleOk(j.role) && cityOk(j.city)),
          ...workers.where((w) => roleOk(w.role) && cityOk(w.city)),
        ];
  if (exact.isNotEmpty) return AiMatch(exact);
  final List<Listing> near = [
    ...jobs.where((j) => roleOk(j.role)),
    ...workers.where((w) => roleOk(w.role)),
  ];
  return AiMatch(near, exact: false);
}
