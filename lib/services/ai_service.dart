import '../data/cities.dart';
import '../models/models.dart';
import 'ai_backend.dart';

/// Server-only Gemini integration with a deterministic, private on-device fallback.
/// Remote processing is attempted only after explicit UI consent.
class AiService {
  const AiService();
  static const instance = AiService();

  Future<AiResult> understand(
    String text, {
    required String myCity,
    AiBackend? backend,
    bool useRemote = false,
  }) async {
    final clean = text.trim();
    if (clean.isEmpty) return AiResult.empty;
    if (clean.length > 400) {
      return LocalUnderstanding.parse(clean.substring(0, 400), myCity: myCity);
    }
    if (useRemote && backend != null) {
      try {
        final data = await backend.understandText(clean, city: myCity);
        final result = AiResult.fromJson(data, source: AiSource.gemini);
        if (!result.isEmpty) return result;
      } catch (_) {
        // Do not log user prompts, provider responses, or session credentials.
      }
    }
    return LocalUnderstanding.parse(clean, myCity: myCity);
  }
}

enum AiSource { gemini, local }

/// Kullanıcının ne yapmak istediği.
enum AiIntent { ara, ilanVer, soru }

/// Anlaşılan istek: hem arama süzgeci hem de ilan taslağı olarak kullanılır.
class AiResult {
  const AiResult({
    this.intent = AiIntent.ara,
    this.category,
    this.fromCity,
    this.toCity,
    this.city,
    this.vehicle,
    this.machine,
    this.material,
    this.workerRole,
    this.cargo,
    this.tons,
    this.price,
    this.dayOffset,
    this.summary = '',
    this.answer,
    this.source = AiSource.local,
  });

  final AiIntent intent;
  final ListingKind? category;
  final String? fromCity;
  final String? toCity;
  final String? city;
  final VehicleType? vehicle;
  final MachineType? machine;
  final String? material;
  final WorkerRole? workerRole;
  final String? cargo;
  final double? tons;
  final double? price;

  /// Bugünden kaç gün sonra (0 = bugün, 1 = yarın).
  final int? dayOffset;

  /// "Şunu anladım" cümlesi.
  final String summary;

  /// Soru ise kısa yanıt.
  final String? answer;
  final AiSource source;

  static const empty = AiResult();

  bool get isEmpty =>
      category == null &&
      fromCity == null &&
      toCity == null &&
      city == null &&
      (answer ?? '').isEmpty &&
      summary.isEmpty;

  /// Bu istekle bir yük ilanı taslağı hazırlanabilir mi?
  bool get canDraftLoad =>
      category == ListingKind.yuk &&
      (fromCity != null || toCity != null || cargo != null);

  DateTime? get date => dayOffset == null
      ? null
      : DateTime.now().add(Duration(days: dayOffset!.clamp(0, 365).toInt()));

  /// Sunucudan/Gemini'den gelen JSON. Bilinmeyen değerler sessizce yok sayılır;
  /// il adları uygulamanın il listesiyle doğrulanır.
  factory AiResult.fromJson(
    Map<String, dynamic> j, {
    AiSource source = AiSource.gemini,
  }) {
    T? pick<T extends Enum>(List<T> values, Object? v) {
      if (v is! String || v.isEmpty) return null;
      for (final e in values) {
        if (e.name == v) return e;
      }
      return null;
    }

    String? str(Object? v, [int max = 80]) {
      if (v is! String) return null;
      final t = v.trim();
      if (t.isEmpty) return null;
      return t.length > max ? t.substring(0, max) : t;
    }

    double? number(Object? v) {
      final n = v is num
          ? v.toDouble()
          : (v is String ? double.tryParse(v.replaceAll(',', '.')) : null);
      return n == null || n <= 0 || !n.isFinite ? null : n;
    }

    String? cityOf(Object? v) => v is String ? findCity(v) : null;

    final intent = switch (j['intent']) {
      'ilan_ver' => AiIntent.ilanVer,
      'soru' => AiIntent.soru,
      _ => AiIntent.ara,
    };
    final day = j['gun'];
    return AiResult(
      intent: intent,
      category: pick(const [
        ListingKind.yuk,
        ListingKind.makine,
        ListingKind.malzeme,
        ListingKind.personel,
      ], j['kategori']),
      fromCity: cityOf(j['nereden']),
      toCity: cityOf(j['nereye']),
      city: cityOf(j['il']),
      vehicle: pick(VehicleType.values, j['arac']),
      machine: pick(MachineType.values, j['makine']),
      material: str(j['malzeme'], 40),
      workerRole: pick(WorkerRole.values, j['pozisyon']),
      cargo: str(j['yuk_cinsi'], 60),
      tons: number(j['ton']),
      price: number(j['fiyat']),
      dayOffset: day is num && day.isFinite
          ? day.toInt().clamp(0, 365).toInt()
          : null,
      summary: str(j['ozet'], 160) ?? '',
      answer: str(j['cevap'], 600),
      source: source,
    );
  }
}

/// İnternetsiz / yapay zekâsız çalışan basit anlayıcı. Gemini kadar akıllı değildir
/// ama en sık cümleleri ("yarın İstanbul'dan Ankara'ya tır lazım") doğru çözer.
class LocalUnderstanding {
  const LocalUnderstanding._();

  static const _suffixes = {
    '',
    'dan',
    'den',
    'tan',
    'ten',
    'a',
    'e',
    'ya',
    'ye',
    'na',
    'ne',
    'da',
    'de',
    'ta',
    'te',
    'daki',
    'deki',
    'taki',
    'teki',
  };

  static const _vehicleWords = <String, VehicleType>{
    'frigo': VehicleType.frigo,
    'soguk': VehicleType.frigo,
    'damper': VehicleType.damperli,
    'kirkayak': VehicleType.kirkayak,
    'lowbed': VehicleType.lowbed,
    'kamyonet': VehicleType.kamyonet,
    'panelvan': VehicleType.kamyonet,
    'kamyon': VehicleType.kamyon,
    'tir': VehicleType.tir,
    'tenteli': VehicleType.tir,
  };

  static const _machineWords = <String, MachineType>{
    'ekskavator': MachineType.ekskavator,
    'paletli': MachineType.ekskavator,
    'kepce': MachineType.ekskavator,
    'silindir': MachineType.silindir,
    'greyder': MachineType.greyder,
    'finiser': MachineType.finiser,
    'bekoloder': MachineType.bekoloder,
    'beko': MachineType.bekoloder,
    'jcb': MachineType.bekoloder,
    'loder': MachineType.loder,
    'dozer': MachineType.dozer,
    'vinc': MachineType.vinc,
  };

  static const _materialWords = <String, String>{
    'c35': 'C35/45',
    'c30': 'C30/37',
    'c25': 'C25/30',
    'beton': 'Beton',
    'micir': 'Mıcır',
    'kum': 'Kum',
    'agrega': 'Agrega',
    'pmt': 'Plent-miks',
    'stabilize': 'Stabilize',
    'binder': 'Binder',
    'asinma': 'Aşınma',
    'asfalt': 'Asfalt',
  };

  static const _roleWords = <String, WorkerRole>{
    'ekskavator operator': WorkerRole.ekskavatorOp,
    'silindir operator': WorkerRole.silindirOp,
    'greyder operator': WorkerRole.greyderOp,
    'finiser operator': WorkerRole.finiserOp,
    'vinc operator': WorkerRole.vincOp,
    'sofor': WorkerRole.tirSoforu,
    'ustabasi': WorkerRole.ustabasi,
    'formen': WorkerRole.ustabasi,
    'isci': WorkerRole.isci,
    'eleman': WorkerRole.isci,
  };

  static AiResult parse(String text, {required String myCity}) {
    // Kesme işareti silinir ("İstanbul'dan" → "istanbuldan"), diğer noktalama boşluk olur.
    final t =
        ' ${normalizeTr(text).replaceAll(RegExp(r"[’'`]"), '').replaceAll(RegExp(r'[.,!?;:()/]'), ' ')} ';

    // İller: metindeki sıraya göre; "-dan/-den" eki çıkışı, "-a/-e/-ya/-ye" eki varışı gösterir.
    final found =
        <(int, String, String)>[]; // (konum, il, ekten sonraki harfler)
    for (final name in kCityNames) {
      final n = normalizeTr(name);
      // Yalnızca il adı + bilinen bir hâl eki eşleşir ("musait" içindeki "Muş" gibi yanlışları önler).
      for (final m in RegExp('\\s$n([a-z]*)(?=\\s)').allMatches(t)) {
        final suffix = m.group(1) ?? '';
        if (_suffixes.contains(suffix)) {
          found.add((m.start, name, suffix));
          break;
        }
      }
    }
    found.sort((a, b) => a.$1.compareTo(b.$1));
    String? from, to, city;
    for (final (_, name, suffix) in found) {
      if (RegExp(r'^(dan|den|tan|ten)').hasMatch(suffix)) {
        from ??= name;
      } else if (RegExp(r'^(a|e|ya|ye|na|ne)$').hasMatch(suffix)) {
        to ??= name;
      } else {
        city ??= name;
      }
    }
    if (from == null && to == null && found.length >= 2) {
      from = found[0].$2;
      to = found[1].$2;
      city = null;
    }

    VehicleType? vehicle;
    for (final e in _vehicleWords.entries) {
      if (t.contains(e.key)) {
        vehicle = e.value;
        break;
      }
    }
    MachineType? machine;
    for (final e in _machineWords.entries) {
      if (t.contains(e.key)) {
        machine = e.value;
        break;
      }
    }
    String? material;
    for (final e in _materialWords.entries) {
      if (t.contains(e.key)) {
        material = e.value;
        break;
      }
    }
    WorkerRole? role;
    for (final e in _roleWords.entries) {
      if (t.contains(e.key)) {
        role = e.value;
        break;
      }
    }
    final wantsPerson =
        role != null ||
        t.contains('operator') ||
        t.contains('personel') ||
        t.contains('is ariyorum');

    final ListingKind? category = wantsPerson
        ? ListingKind.personel
        : machine != null && !t.contains(' ton yuk')
        ? ListingKind.makine
        : material != null
        ? ListingKind.malzeme
        : (from != null ||
              to != null ||
              vehicle != null ||
              t.contains('yuk') ||
              t.contains('nakliye'))
        ? ListingKind.yuk
        : null;
    if (category == ListingKind.personel && role == null && machine != null) {
      role = switch (machine) {
        MachineType.ekskavator => WorkerRole.ekskavatorOp,
        MachineType.silindir => WorkerRole.silindirOp,
        MachineType.greyder => WorkerRole.greyderOp,
        MachineType.finiser => WorkerRole.finiserOp,
        MachineType.vinc => WorkerRole.vincOp,
        _ => null,
      };
    }

    double? tons;
    final tm = RegExp(r'(\d+(?:[.,]\d+)?)\s*ton').firstMatch(t);
    if (tm != null) tons = double.tryParse(tm.group(1)!.replaceAll(',', '.'));

    double? price;
    final pm = RegExp(r'(\d+(?:[.,]\d+)?)\s*(bin|tl|lira)').firstMatch(t);
    if (pm != null) {
      final raw = pm.group(1)!;
      final v = double.tryParse(
        pm.group(2) == 'bin'
            ? raw.replaceAll(',', '.')
            : raw.replaceAll('.', '').replaceAll(',', '.'),
      );
      if (v != null) price = pm.group(2) == 'bin' ? v * 1000 : v;
    }

    final int? day = t.contains('obur gun') || t.contains('ertesi gun')
        ? 2
        : t.contains('yarin')
        ? 1
        : t.contains('bugun')
        ? 0
        : null;

    final posting =
        RegExp(
          r'(tasit|tasitmak|gondermek|gonderecek|kiraya ver|ilan ver|satiyorum|satmak|eleman ariyorum|ariyorum operator|operator ariyorum)',
        ).hasMatch(t) ||
        (category != null &&
            category != ListingKind.personel &&
            RegExp(r'(\svar\s|tasinacak|yukum|m var\s)').hasMatch(t) &&
            !t.contains('lazim') &&
            !RegExp(
              r'\s(mi|mu)\s',
            ).hasMatch(t)); // "müsait kamyon var mı" bir aramadır

    final result = AiResult(
      intent: posting ? AiIntent.ilanVer : AiIntent.ara,
      category: category,
      fromCity: from,
      toCity: to,
      city:
          city ??
          (category == ListingKind.makine || category == ListingKind.malzeme
              ? (from ?? to)
              : null),
      vehicle: vehicle,
      machine: machine,
      material: material,
      workerRole: role,
      tons: tons,
      price: price,
      dayOffset: day,
      source: AiSource.local,
    );
    return AiResult(
      intent: result.intent,
      category: result.category,
      fromCity: result.fromCity,
      toCity: result.toCity,
      city: result.city,
      vehicle: result.vehicle,
      machine: result.machine,
      material: result.material,
      workerRole: result.workerRole,
      tons: result.tons,
      price: result.price,
      dayOffset: result.dayOffset,
      summary: describe(result, myCity: myCity),
      source: AiSource.local,
    );
  }

  /// Türkçe ses uyumuyla il eki: İstanbul'dan, İzmir'den, Sinop'tan; Ankara'ya, İzmir'e.
  static String _withSuffix(String city, {required bool ablative}) {
    final lower = city.toLowerCase();
    final vowels = RegExp(
      '[aıouâeiöüî]',
    ).allMatches(lower).map((m) => m.group(0)!).toList();
    final back = vowels.isEmpty || 'aıouâ'.contains(vowels.last);
    final last = lower.isEmpty ? '' : lower[lower.length - 1];
    final endsWithVowel = 'aıouâeiöüî'.contains(last);
    if (ablative) {
      final hard = 'çfhkpsşt'.contains(last);
      return "$city'${hard ? 't' : 'd'}${back ? 'an' : 'en'}";
    }
    return "$city'${endsWithVowel ? 'y' : ''}${back ? 'a' : 'e'}";
  }

  /// Anlaşılanı tek cümleyle anlatır (yerel anlayıcı için; Gemini kendi özetini yazar).
  static String describe(AiResult r, {required String myCity}) {
    final when = switch (r.dayOffset) {
      0 => 'bugün ',
      1 => 'yarın ',
      2 => 'öbür gün ',
      _ => '',
    };
    switch (r.category) {
      case ListingKind.yuk:
        final route = [
          if (r.fromCity != null) _withSuffix(r.fromCity!, ablative: true),
          if (r.toCity != null) _withSuffix(r.toCity!, ablative: false),
        ].join(' ');
        final what = r.vehicle?.label.toLowerCase() ?? 'yük';
        return r.intent == AiIntent.ilanVer
            ? '${route.isEmpty ? '' : '$route '}${when}yük göndermek istiyorsunuz.'
            : '${route.isEmpty ? '' : '$route '}$when$what arıyorsunuz.';
      case ListingKind.makine:
        return '${r.city ?? myCity} çevresinde kiralık ${r.machine?.label.toLowerCase() ?? 'iş makinesi'} arıyorsunuz.';
      case ListingKind.malzeme:
        return '${r.city ?? myCity} çevresinde ${r.material ?? 'malzeme'} fiyatlarına bakıyorsunuz.';
      case ListingKind.personel:
        return r.intent == AiIntent.ilanVer
            ? '${r.workerRole?.label ?? 'Personel'} arıyorsunuz (iş ilanı).'
            : '${r.workerRole?.label ?? 'Personel'} ilanlarına bakıyorsunuz.';
      default:
        return 'Tüm ilanlarda arıyoruz.';
    }
  }
}
