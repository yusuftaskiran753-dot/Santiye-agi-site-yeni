// Müşterinin v2.1.2 kaynak kopyasında çalıştırılan inceleme aracı.
// Bu dosyayı arşivden çıkarılan ayrı çalışma kopyasının test/ klasörüne
// kopyalayın ve orada flutter test test/customer_demo_audit_test.dart çalıştırın.
// Orijinal lib/ ve pubspec.yaml değişmez; güncel .NET mobilinde çalıştırılmaz.
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:santiye_agi/config.dart';
import 'package:santiye_agi/main.dart';
import 'package:santiye_agi/models/models.dart';
import 'package:santiye_agi/services/billing_service.dart';
import 'package:santiye_agi/services/backend.dart';
import 'package:santiye_agi/services/local_backend.dart';
import 'package:santiye_agi/services/local_store.dart';
import 'package:santiye_agi/state/app_state.dart';
import 'package:santiye_agi/theme.dart';
import 'package:santiye_agi/screens/shell.dart';
import 'package:santiye_agi/screens/market/market_screen.dart';
import 'package:santiye_agi/screens/search/search_screen.dart';
import 'package:santiye_agi/screens/listings/listing_detail_screen.dart';
import 'package:santiye_agi/screens/listings/request_sheet.dart';
import 'package:santiye_agi/screens/listings/forms/load_form.dart';
import 'package:santiye_agi/screens/listings/forms/machine_form.dart';
import 'package:santiye_agi/screens/listings/forms/material_form.dart';
import 'package:santiye_agi/screens/listings/forms/job_form.dart';
import 'package:santiye_agi/screens/listings/forms/worker_form.dart';
import 'package:santiye_agi/screens/work/work_screen.dart';
import 'package:santiye_agi/screens/deals/deal_form_screen.dart';
import 'package:santiye_agi/screens/deals/deal_detail_screen.dart';
import 'package:santiye_agi/screens/profile/profile_screen.dart';
import 'package:santiye_agi/screens/profile/public_profile_screen.dart';
import 'package:santiye_agi/screens/profile/guide_screen.dart';
import 'package:santiye_agi/screens/loads/backhaul_screen.dart';
import 'package:santiye_agi/screens/haul/haul_screen.dart';
import 'package:santiye_agi/screens/billing/paywall_screen.dart';
import 'package:santiye_agi/screens/notifications/notifications_screen.dart';

final records = <Map<String, Object?>>[];
late AppState app;
late BillingService billing;
Future<void> pump(WidgetTester t) async {
  for (var i = 0; i < 15; i++) {
    await t.pump(const Duration(milliseconds: 100));
  }
}

Future<void> tap(WidgetTester t, Finder f) async {
  for (var i = 0; f.evaluate().isEmpty && i < 15; i++) {
    final scroll = find.byWidgetPredicate(
      (w) => w is Scrollable && w.axisDirection == AxisDirection.down,
    );
    if (scroll.evaluate().isEmpty) break;
    await t.drag(scroll.first, const Offset(0, -400));
    await t.pump();
  }
  expect(f, findsWidgets);
  if (f.hitTestable().evaluate().isEmpty) {
    await t.ensureVisible(f.first);
    await t.pump();
  }
  await t.tap(f.hitTestable().first);
  await pump(t);
}

Future<void> setup(WidgetTester t, {bool signedIn = true}) async {
  t.view.physicalSize = const Size(1000, 2000);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.resetPhysicalSize);
  addTearDown(t.view.resetDevicePixelRatio);
  SharedPreferences.setMockInitialValues({});
  final store = LocalStore(await SharedPreferences.getInstance());
  app = AppState(LocalBackend(store, simulate: false), store);
  await app.init();
  billing = BillingService(
    store,
    verify: app.verifyPurchase,
    userId: () => app.myId,
    allowDebugGrant: true,
  );
  if (signedIn) {
    await app.completeOnboarding(
      name: 'Demo Denetimi',
      company: 'İnceleme',
      role: UserRole.yukSahibi,
      city: 'Ankara',
      phone: '+905551234567',
    );
    expect(app.showDemo, false);
    await app.setShowDemo(true);
  }
  addTearDown(() {
    billing.dispose();
    app.dispose();
  });
}

Future<void> mount(WidgetTester t, Widget page) async {
  await t.pumpWidget(const SizedBox());
  await t.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<AppState>.value(value: app),
        ChangeNotifierProvider<BillingService>.value(value: billing),
      ],
      child: MaterialApp(
        theme: buildTheme(Brightness.light),
        locale: const Locale('tr', 'TR'),
        supportedLocales: const [Locale('tr', 'TR')],
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        home: page,
      ),
    ),
  );
  await pump(t);
}

void record(String name, String actions) {
  final labels = find
      .byType(Text)
      .evaluate()
      .map((e) => (e.widget as Text).data)
      .whereType<String>()
      .toSet()
      .toList();
  records.add({'screen': name, 'actions': actions, 'texts': labels});
}

void audit(String name, Future<void> Function(WidgetTester) body) {
  testWidgets(name, (t) async {
    await setup(t);
    await body(t);
    expect(t.takeException(), isNull);
    await t.pumpWidget(const SizedBox());
    await pump(t);
  });
}

void main() {
  tearDownAll(() {
    File('audit-ui-evidence.json').writeAsStringSync(
      const JsonEncoder.withIndent('  ').convert({
        'baseline': 'customer-v2.1.2+5',
        'archive_sha256':
            '557661ECFA3CB93B8A65BE821F82489668684C928DE3E5FD08BEC0F29209ACC1',
        'surface': 'Flutter widget tester 1000x2000, DPR 1',
        'demo':
            'LocalBackend, simulate:false; sample toggle explicitly enabled after onboarding',
        'external_services_exercised': false,
        'screens': records,
      }),
    );
  });
  testWidgets('İlk açılış: onay, profil oluşturma ve ana menü', (t) async {
    await setup(t, signedIn: false);
    await t.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<AppState>.value(value: app),
          ChangeNotifierProvider<BillingService>.value(value: billing),
        ],
        child: const SantiyeApp(),
      ),
    );
    await pump(t);
    expect(
      t
          .widget<FilledButton>(find.widgetWithText(FilledButton, 'Başla'))
          .onPressed,
      isNull,
    );
    await tap(t, find.byType(CheckboxListTile));
    await tap(t, find.widgetWithText(FilledButton, 'Başla'));
    final fields = find.byType(TextFormField);
    await t.enterText(fields.at(0), 'Demo Denetimi');
    await t.enterText(fields.at(2), '0555 123 45 67');
    await tap(t, find.text('Kaydet ve başla'));
    expect(app.me?.name, 'Demo Denetimi');
    expect(find.byType(NavigationBar), findsOneWidget);
    record(
      'Başlangıç',
      'Onay kutusu, Başla, ad/telefon girme, Kaydet ve başla; ilk örnek ilan ayarı kapalı',
    );
    await t.pumpWidget(const SizedBox());
    await pump(t);
  });
  audit('Ana menü ve alt sekmeler', (t) async {
    await mount(t, const MainShell());
    for (final label in [
      'İlanlar',
      'İşlerim',
      'Profil',
      'Ana Sayfa',
      'İlan ver',
    ]) {
      await tap(
        t,
        find.descendant(
          of: find.byType(NavigationBar),
          matching: find.text(label),
        ),
      );
      record('Alt menü: $label', 'Alt menü düğmesine basıldı');
    }
    expect(find.text('Ne yayınlamak istersiniz?'), findsOneWidget);
  });
  for (final cat in MarketCategory.values) {
    audit('Pazar ${cat.label}', (t) async {
      final category = ValueNotifier<MarketCategory>(MarketCategory.yuk);
      await mount(t, MarketScreen(category: category));
      await tap(t, find.widgetWithText(ChoiceChip, cat.label));
      if (cat == MarketCategory.makine) {
        await tap(t, find.widgetWithText(FilterChip, 'Müsait'));
        await tap(t, find.text('Harita'));
        await tap(t, find.text('Liste'));
      } else if (cat == MarketCategory.personel) {
        await tap(t, find.text('Operatörler'));
        await tap(t, find.text('İş ilanları'));
      }
      final sort = find.byTooltip('Sırala');
      if (sort.evaluate().isNotEmpty) {
        await tap(t, sort);
        record('Sıralama: ${cat.label}', 'Sıralama menüsü açıldı');
        final selection = find.text(
          cat == MarketCategory.yuk
              ? 'En yeni'
              : cat == MarketCategory.makine
              ? 'En ucuz (günlük)'
              : 'Fiyatı en ucuz',
        );
        // Menü metni hit-test ağacında IgnorePointer altındadır; aynı koordinattaki menü öğesine basılır.
        await t.tapAt(t.getCenter(selection.first));
        await pump(t);
        expect(
          find.text(
            cat == MarketCategory.yuk
                ? 'En yeni'
                : cat == MarketCategory.makine
                ? 'En ucuz (günlük)'
                : 'Fiyatı en ucuz',
          ),
          findsOneWidget,
        );
      }
      record(
        'Pazar: ${cat.label}',
        'Kategori seçimi; makine müsait/liste/harita, personel iş/operatör; varsa son sıralama seçeneği',
      );
    });
  }
  audit('Genel arama', (t) async {
    await mount(t, const SearchScreen());
    await tap(t, find.widgetWithText(ActionChip, 'Ekskavatör'));
    expect(find.textContaining('Makine ('), findsWidgets);
    await tap(t, find.byTooltip('Temizle'));
    await t.enterText(find.byType(TextField), 'zzzzbenzersiz');
    await pump(t);
    expect(find.textContaining('için sonuç yok'), findsOneWidget);
    record(
      'Arama',
      'Hazır arama, sonuçlar, temizleme, sonuç bulunamayan sorgu',
    );
  });
  for (final kind in ListingKind.values) {
    audit('İlan ayrıntısı ve talep ${kind.name}', (t) async {
      final l = app.market(kind).first;
      await mount(t, ListingDetailScreen(kind: kind, id: l.id, initial: l));
      await tap(t, find.byTooltip('Diğer'));
      expect(find.text('Şikâyet et'), findsWidgets);
      record(
        'İlan ayrıntısı: ${kind.name}',
        'Diğer menüsü açıldı; şikâyet/engelleme seçenekleri',
      );
      Navigator.of(t.element(find.byType(Scaffold).first)).pop();
      await pump(t);
      await mount(t, Scaffold(body: RequestSheet(listing: l)));
      await tap(t, find.text('Gönder'));
      record(
        'Talep formu: ${kind.name}',
        'Gönder düğmesi çalıştırıldı; önceden dolan/default alanlar geçerliyse kayıt gönderildi, eksik zorunlu alanlar varsa doğrulama gösterildi',
      );
    });
  }
  final forms = <String, Widget>{
    'Yük ilanı ver': const LoadFormScreen(),
    'Makinemi ekle': const MachineFormScreen(),
    'Ürün / fiyat ekle': const MaterialFormScreen(),
    'Personel ilanı ver': const JobFormScreen(),
    'Sicil kartım': const WorkerFormScreen(),
    'Anlaşma kaydı oluştur': const DealFormScreen(),
  };
  for (final entry in forms.entries) {
    audit('Yeni kayıt ${entry.key}', (t) async {
      await mount(t, entry.value);
      record(
        entry.key,
        'Form açıldı; alanlar kaydedildi; boş form gönderimi ile doğrulama denendi',
      );
      final b = find.descendant(
        of: find.byType(Scaffold).first,
        matching: find.byType(FilledButton),
      );
      await tap(t, b.last);
    });
  }
  audit('İşlerim dört sekme', (t) async {
    await mount(t, WorkScreen(tab: ValueNotifier(0), onOpenMarket: () {}));
    for (final label in ['Gelen', 'Giden', 'Anlaşmalar', 'İlanlarım']) {
      await tap(t, find.widgetWithText(Tab, label));
      record('İşlerim: $label', 'Sekme seçildi');
    }
  });
  audit('Profil örnekleri aç/kapat ve düzenle', (t) async {
    await mount(t, const ProfileScreen());
    await tap(t, find.widgetWithText(SwitchListTile, 'Örnek ilanları göster'));
    expect(app.showDemo, false);
    await tap(t, find.widgetWithText(SwitchListTile, 'Örnek ilanları göster'));
    expect(app.showDemo, true);
    await mount(t, const ProfileScreen());
    await tap(t, find.byTooltip('Düzenle'));
    expect(find.text('Profili düzenle'), findsOneWidget);
    await t.enterText(find.byType(TextFormField).first, 'Yeni Demo Adı');
    await tap(t, find.text('Kaydet'));
    expect(app.me?.name, 'Yeni Demo Adı');
    record(
      'Profil',
      'Örnekler açıldı/kapatıldı; profil adı düzenlenip kaydedildi',
    );
  });
  audit('Herkese açık profil ve engellenenler', (t) async {
    final p = app.marketLoads.first.owner;
    await mount(t, PublicProfileScreen(userId: p.id, initial: p));
    await tap(t, find.byType(PopupMenuButton<String>));
    record(
      'Herkese açık profil',
      'Profil/puan/ilanlar; şikâyet ve engelleme menüsü',
    );
    Navigator.of(t.element(find.byType(Scaffold).first)).pop();
    await pump(t);
    await app.block(p.id);
    await mount(t, const BlockedUsersScreen());
    await tap(t, find.text('Engeli kaldır'));
    expect(app.isBlocked(p.id), false);
    record('Engellenenler', 'Engeli kaldır düğmesi çalıştırıldı');
  });
  audit('Rehber sekmeleri', (t) async {
    await mount(t, const GuideScreen());
    await tap(t, find.widgetWithText(Tab, 'Güvenli ticaret'));
    record('Güvenli ticaret', 'Rehber sekmesi seçildi');
    await tap(t, find.widgetWithText(Tab, 'Nasıl çalışır?'));
    record('Nasıl çalışır?', 'Rehber sekmesi seçildi');
  });
  audit('Boş dönüş eşleştirme', (t) async {
    await mount(t, const BackhaulScreen());
    await tap(t, find.text('Uygun yükleri bul'));
    record(
      'Boş dönüş',
      'Boşaldığım il seçilmeden Uygun yükleri bul basıldı; il seçme uyarısı denendi',
    );
  });
  audit('Hafriyat örnekleri ve optimizasyon', (t) async {
    await app.verifyPurchase(
      const StoreClaim(
        platform: 'android',
        productId: AppConfig.premiumMonthlyId,
        token: 'audit-premium',
        isSubscription: true,
      ),
    );
    await mount(t, const HaulScreen());
    await tap(t, find.byType(PopupMenuButton<String>));
    await tap(t, find.text('Örnek sahaları yükle'));
    await tap(t, find.text('Rotayı Optimize Et'));
    expect(find.text('Toplam sefer'), findsOneWidget);
    record(
      'Hafriyat',
      'Yerel Premium simülasyonu; örnek sahaları yükle ve optimizasyon; hesap sonucu görüntülendi',
    );
  });
  audit('Premium ve kredi ekranları', (t) async {
    await mount(t, const PaywallScreen());
    record(
      'Premium',
      'Aylık/yıllık planlar ve satın alma/geri yükleme kontrolleri görüntülendi; gerçek satın alma yapılmadı',
    );
    await mount(t, const CreditsScreen());
    expect(find.text('5 kredi'), findsWidgets);
    expect(find.text('15 kredi'), findsWidgets);
    expect(find.text('40 kredi'), findsWidgets);
    record(
      'Kredi',
      'Üç kredi paketi görüntülendi; gerçek satın alma yapılmadı',
    );
  });
  audit('Bildirim ekranı', (t) async {
    await mount(t, NotificationsScreen(onOpenWork: (_) {}));
    record(
      'Bildirimler',
      'Boş bildirim ekranı; dolu bildirim işlemleri iş kuralı testlerinde',
    );
  });
  audit('Elle anlaşma başlatma', (t) async {
    final d = await app.createDeal(
      const DealDraft(
        title: 'Demo hafriyat',
        iAmCustomer: true,
        counterpartyName: 'Örnek Firma',
        amount: 1000,
        paymentMethod: PaymentMethod.havale,
      ),
    );
    await mount(t, DealDetailScreen(dealId: d.id));
    record(
      'Anlaşma: davet',
      'Davet, kod kopyalama, kendi kaydım olarak başlat seçenekleri',
    );
    await tap(t, find.text('Kendi kaydım olarak başlat'));
    final confirm = find.widgetWithText(FilledButton, 'Başlat');
    if (confirm.evaluate().isNotEmpty) await tap(t, confirm);
    record('Anlaşma: başlatma', 'Kendi kaydım olarak başlat düğmesine basıldı');
  });
  for (final kind in ListingKind.values) {
    audit('Talep gönderme ve geri çekme: ${kind.name}', (t) async {
      final l = app.market(kind).first;
      await app.unlock(l);
      await mount(t, Scaffold(body: RequestSheet(listing: l)));
      final fields = find.byType(TextFormField);
      switch (kind) {
        case ListingKind.yuk:
          await t.enterText(fields.at(0), '10000');
        case ListingKind.makine:
          await tap(t, find.text('Saatlik'));
          await t.enterText(fields.at(0), '8');
          await t.enterText(fields.at(1), 'Ankara test şantiyesi');
        case ListingKind.malzeme:
          await t.enterText(fields.at(0), '100');
          await t.enterText(fields.at(1), 'Ankara test şantiyesi');
        case ListingKind.personel:
          await t.enterText(fields.at(0), 'Deneyimli test personeli');
        case ListingKind.sicil:
          await t.enterText(fields.at(0), '2000');
          await t.enterText(fields.at(1), 'Ankara test şantiyesi');
      }
      await tap(t, find.text('Gönder'));
      expect(app.outgoingRequests.length, 1);
      await mount(t, WorkScreen(tab: ValueNotifier(1), onOpenMarket: () {}));
      await tap(t, find.text('Geri çek'));
      await tap(t, find.widgetWithText(FilledButton, 'Geri çek'));
      expect(app.outgoingRequests.single.status, RequestStatus.withdrawn);
      record(
        'Başarılı talep: ${kind.name}',
        'İletişim hakkı test hazırlığında açıldı; türün gerekli alanları dolduruldu; Gönder ve Geri çek onayı çalıştırıldı',
      );
    });
  }
  audit('Makine formu yayınla, sahibi menüsü ve müsaitlik', (t) async {
    await mount(t, const MachineFormScreen());
    final fields = find.byType(TextFormField);
    await t.enterText(fields.at(0), 'Test Ekskavatör');
    await t.enterText(fields.at(1), '20 ton');
    await t.enterText(fields.at(2), '15000');
    await tap(t, find.widgetWithText(SwitchListTile, 'Operatör dahil'));
    await tap(t, find.text('Yayınla'));
    expect(app.mine(ListingKind.makine).length, 1);
    final l = app.mine(ListingKind.makine).single as Machine;
    expect(l.withOperator, false);
    await mount(t, ListingDetailScreen(kind: l.kind, id: l.id));
    await tap(t, find.widgetWithText(SwitchListTile, 'Kiralamaya müsait'));
    expect((app.listingById(l.kind, l.id) as Machine).available, false);
    await tap(t, find.byTooltip('Diğer'));
    await tap(t, find.text('Yayından kaldır'));
    expect(app.listingById(l.kind, l.id)?.status, ListingStatus.closed);
    await tap(t, find.byTooltip('Diğer'));
    await tap(t, find.text('Yeniden yayınla'));
    expect(app.listingById(l.kind, l.id)?.status, ListingStatus.active);
    await tap(t, find.byTooltip('Diğer'));
    await tap(t, find.text('Sil'));
    await tap(t, find.widgetWithText(FilledButton, 'Sil'));
    expect(app.mine(ListingKind.makine), isEmpty);
    record(
      'Kendi ilanını yönetme',
      'Makine formu doldurulup yayınlandı; operatör, müsaitlik, yayından kaldır, yeniden yayınla ve sil onayı çalıştırıldı',
    );
  });
  audit('Malzeme formu öneri, stok ve nakliye', (t) async {
    await mount(t, const MaterialFormScreen());
    await tap(t, find.widgetWithText(ActionChip, 'C30/37'));
    final fields = find.byType(TextFormField);
    await t.enterText(fields.at(1), '3000');
    await tap(t, find.widgetWithText(ChoiceChip, 'Stok az'));
    await tap(t, find.widgetWithText(SwitchListTile, 'Nakliye sağlıyoruz'));
    await tap(t, find.text('Yayınla'));
    final m = app.mine(ListingKind.malzeme).single as MaterialListing;
    expect(m.product, 'C30/37');
    expect(m.stock, StockLevel.az);
    expect(m.delivery, false);
    record(
      'Malzeme yayınlama',
      'Hazır ürün önerisi, birim fiyat, stok az, nakliye anahtarı ve Yayınla çalıştırıldı',
    );
  });
  audit('Personel ilanı ve sicil kartı yayınlama', (t) async {
    await mount(t, const JobFormScreen());
    await t.enterText(
      find.byType(TextFormField).first,
      'Test operatör arıyoruz',
    );
    await tap(t, find.text('İlanı yayınla'));
    expect(app.mine(ListingKind.personel).length, 1);
    await mount(t, const WorkerFormScreen());
    await t.enterText(find.byType(TextFormField).first, '5');
    await tap(t, find.text('Kaydet'));
    expect(app.myWorkerCard?.years, 5);
    record(
      'Personel ve sicil yayınlama',
      'Başlıkla personel ilanı yayınlandı; 5 yıl deneyim ile sicil kartı kaydedildi',
    );
  });
  audit('Anlaşma ödeme, sorun ve tamamlama düğmeleri', (t) async {
    final d = await app.createDeal(
      const DealDraft(
        title: 'Test işi',
        iAmCustomer: true,
        counterpartyName: 'Test firma',
        amount: 1000,
        paymentMethod: PaymentMethod.havale,
        milestones: [DealMilestone(title: 'Tam ödeme', amount: 1000)],
      ),
    );
    await app.dealAction(d, DealAction.confirm);
    await mount(t, DealDetailScreen(dealId: d.id));
    await tap(t, find.text('Ödedim'));
    await tap(t, find.text('İşaretle'));
    expect(app.deals.single.milestones.single.paid, true);
    await tap(t, find.text('Tahsil ettim'));
    await tap(t, find.text('Evet, tahsil ettim'));
    expect(app.deals.single.milestones.single.received, true);
    await mount(t, DealDetailScreen(dealId: d.id));
    await tap(t, find.text('Sorun bildir'));
    await t.enterText(find.byType(TextField).last, 'Test teslim sorunu');
    await pump(t);
    await tap(t, find.text('Gönder'));
    expect(app.deals.single.status, DealStatus.disputed);
    await tap(t, find.text('Sorun çözüldü'));
    expect(app.deals.single.status, DealStatus.active);
    await tap(t, find.text('Teslim aldım, tamamla'));
    await tap(t, find.text('Tamamla'));
    expect(app.deals.single.status, DealStatus.completed);
    record(
      'Anlaşma düğmeleri',
      'Tek kişilik kayıtta Ödedim, Tahsil ettim, Sorun bildir, Sorun çözüldü, Teslim aldım tamamla ve onayları çalıştırıldı',
    );
  });
}
