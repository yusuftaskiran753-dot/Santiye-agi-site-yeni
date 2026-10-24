import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:santiye_agi/config.dart';
import 'package:santiye_agi/models/models.dart';
import 'package:santiye_agi/services/backend.dart';
import 'package:santiye_agi/services/dotnet_backend.dart';

class _Sessions implements ApiSessionStore {
  final values = <String, String>{};
  @override
  Future<String?> read(String key) async => values[key];
  @override
  Future<void> write(String key, String value) async => values[key] = value;
  @override
  Future<void> delete(String key) async => values.remove(key);
}

class _RealHttp extends HttpOverrides {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'Beş ilan türü mobil modellerle gerçek API üzerinden tamamlanır',
    () => HttpOverrides.runWithHttpOverrides(() async {
      final uri = Uri.parse(AppConfig.apiBaseUrl);
      if (!['localhost', '127.0.0.1'].contains(uri.host) ||
          !const String.fromEnvironment(
            'LOCAL_TEST_DATABASE_NAME',
          ).startsWith('santiye_test_')) {
        fail(
          'Yalnız localhost üzerinde bu çalışma için oluşturulan santiye_test_* veritabanı kullanılabilir.',
        );
      }
      final clients = <DotNetBackend>[];
      final ownerStore = _Sessions();
      final prefix = DateTime.now().millisecondsSinceEpoch % 9000000;
      Future<DotNetBackend> account(
        int suffix,
        String name, {
        ApiSessionStore? sessions,
      }) async {
        final api = DotNetBackend(sessions: sessions ?? _Sessions());
        clients.add(api);
        await api.init();
        final phone = '+90555${(prefix + suffix).toString().padLeft(7, '0')}';
        await api.sendPhoneCode(phone);
        final code = api.developmentPhoneCode;
        expect(code, isNotNull, reason: 'API Development ortamında olmalıdır.');
        await api.verifyPhoneCode(phone, code!);
        await api.saveMyProfile(
          name: name,
          company: 'Yerel kabul testi',
          role: UserRole.muteahhit,
          city: 'İstanbul',
          phone: phone,
        );
        return api;
      }

      Matcher isBackendError(String code) =>
          isA<BackendException>().having((e) => e.code, 'code', code);
      try {
        final owner = await account(
          0,
          'Kabul testi sahibi',
          sessions: ownerStore,
        );
        final other = await account(1, 'Kabul testi müşterisi');
        final profile = (await owner.fetchMyProfile())!;
        final date = dateOnly(DateTime.now().add(const Duration(days: 2)));
        final fixtures = <ListingKind, Map<String, dynamic>>{
          ListingKind.yuk: {
            'from_city': 'İstanbul',
            'to_city': 'Ankara',
            'cargo': 'Test yükü',
            'tons': 10,
            'vehicle': 'tir',
            'price': 3000,
            'load_date': date,
          },
          ListingKind.makine: {
            'type': 'ekskavator',
            'model': 'Test makinesi',
            'capacity': '20 ton',
            'city': 'İstanbul',
            'lat': 41,
            'lng': 29,
            'hourly': 500,
            'daily': 3000,
            'available': true,
            'with_operator': true,
          },
          ListingKind.malzeme: {
            'kind': 'agrega',
            'product': 'Test mıcır',
            'unit': 'ton',
            'price': 100,
            'stock': 'bol',
            'plant_name': 'Test tesis',
            'city': 'İstanbul',
            'lat': 41,
            'lng': 29,
            'delivery': true,
            'min_qty': 1,
          },
          ListingKind.personel: {
            'title': 'Test operatör aranıyor',
            'role': 'ekskavatorOp',
            'city': 'İstanbul',
            'wage': 500,
            'wage_period': 'Günlük',
            'duration': '1 ay',
            'requirements': ['MYK'],
          },
          ListingKind.sicil: {
            'role': 'ekskavatorOp',
            'city': 'İstanbul',
            'years': 5,
            'certificates': ['MYK'],
            'available': true,
            'about': 'Deneyimli operatör',
          },
        };
        final created = <Listing>[];
        for (final entry in fixtures.entries) {
          final kind = entry.key;
          final listing = await owner.saveListing(
            Listing.fromJson(kind, {
              ...entry.value,
              'id': '',
              'owner': profile.toJson(),
              'status': 'active',
            }),
            isNew: true,
          );
          created.add(listing);
          expect(listing.owner.id, owner.userId);
          expect(
            (await other.fetchListings(kind)).any((l) => l.id == listing.id),
            true,
          );
          final edited = Listing.fromJson(kind, {
            ...listing.toJson(),
            kind == ListingKind.sicil ? 'about' : 'note':
                'Düzenlenen test açıklaması',
          });
          await owner.saveListing(edited, isNew: false);
          final reopened = (await other.fetchListings(
            kind,
          )).singleWhere((l) => l.id == listing.id);
          expect(
            reopened.toRow()[kind == ListingKind.sicil ? 'about' : 'note'],
            'Düzenlenen test açıklaması',
          );
          if (kind == ListingKind.makine) {
            await owner.setMachineAvailable(listing.id, false);
            await expectLater(
              other.unlock(kind, listing.id),
              throwsA(isBackendError('NOT_AVAILABLE')),
            );
            await owner.setMachineAvailable(listing.id, true);
          }
          expect((await other.unlock(kind, listing.id)).ok, true);
          expect(
            (await other.contactFor(kind.name, listing.id)).phone,
            await owner.fetchMyPhone(),
          );
          final request = await other.createRequest(
            RequestDraft(
              kind: kind,
              listingId: listing.id,
              amount: 3000,
              quantity: 1,
              unit: 'gün',
              startDate: DateTime.parse(date),
              address: 'Test adres',
              note: 'Teklif notu',
            ),
          );
          final updated = await other.createRequest(
            RequestDraft(
              kind: kind,
              listingId: listing.id,
              amount: 3500,
              quantity: 2,
              unit: 'gün',
              startDate: DateTime.parse(date),
              address: 'Test adres',
              note: 'Güncel teklif',
            ),
          );
          expect(updated.id, request.id);
          final dealId = (await owner.respondRequest(
            request.id,
            accept: true,
          ))!;
          final deal = (await other.fetchDeals()).singleWhere(
            (d) => d.id == dealId,
          );
          expect(deal.amount, 3500);
          expect(deal.details, contains('Güncel teklif'));
          expect(deal.milestones.single.amount, 3500);
          final otherProvides =
              kind == ListingKind.yuk || kind == ListingKind.personel;
          final provider = otherProvides ? other : owner;
          final customer = otherProvides ? owner : other;
          await customer.dealAction(
            dealId,
            DealAction.dispute,
            note: 'Test sorunu',
          );
          await expectLater(
            provider.dealAction(dealId, DealAction.resolve),
            throwsA(isBackendError('FORBIDDEN')),
          );
          await customer.dealAction(dealId, DealAction.resolve);
          await customer.dealAction(dealId, DealAction.markPaid, index: 0);
          final paid = await provider.dealAction(
            dealId,
            DealAction.markReceived,
            index: 0,
          );
          expect(paid.milestones.single.received, true);
          await provider.dealAction(dealId, DealAction.deliver);
          expect(
            (await customer.dealAction(dealId, DealAction.complete)).status,
            DealStatus.completed,
          );
          await customer.rateDeal(dealId, 5, 'Başarılı test işi');
          expect(
            (await provider.fetchRatingsFor(
              provider.userId!,
            )).any((r) => r.dealId == dealId),
            true,
          );
        }
        expect((await other.fetchUsage()).freeUsed, 5);
        expect(
          (await owner.fetchUsage()).activeListings,
          4,
        ); // Kabul edilen yük kapanır.
        final material = created.singleWhere(
          (l) => l.kind == ListingKind.malzeme,
        );
        await owner.setListingStatus(
          material.kind,
          material.id,
          ListingStatus.closed,
        );
        expect(
          (await other.fetchListings(
            material.kind,
          )).any((l) => l.id == material.id),
          false,
        );
        await owner.setListingStatus(
          material.kind,
          material.id,
          ListingStatus.active,
        );
        await other.report(
          material.kind.name,
          material.id,
          'Diğer',
          'Test şikâyeti',
        );
        await other.block(owner.userId!);
        expect(await other.fetchBlockedIds(), contains(owner.userId));
        expect(
          (await other.fetchListings(
            material.kind,
          )).any((l) => l.id == material.id),
          false,
        );
        await expectLater(
          other.contactFor(material.kind.name, material.id),
          throwsA(isBackendError('BLOCKED')),
        );
        await other.unblock(owner.userId!);
        expect(
          (await other.fetchListings(
            material.kind,
          )).any((l) => l.id == material.id),
          true,
        );
        final photo = await owner.uploadWorkPhoto(
          Uint8List.fromList(
            base64Decode(
              'iVBORw0KGgoAAAANSUhEUgAAAAIAAAACCAIAAAD91JpzAAAAEElEQVR4nGP438AARAwQCgAt7gX9iz9uhAAAAABJRU5ErkJggg==',
            ),
          ),
          'Tamamlanan test işi',
          id: newUuid(),
        );
        expect(
          (await other.fetchWorkPhotos(owner.userId!)).single.id,
          photo.id,
        );
        expect((await other.fetchWorkPhotoBytes(photo.id)).take(2), [255, 216]);
        await expectLater(
          other.deleteWorkPhoto(photo.id),
          throwsA(isBackendError('FORBIDDEN')),
        );
        await owner.deleteWorkPhoto(photo.id);
        expect(await other.fetchWorkPhotos(owner.userId!), isEmpty);
        expect(await owner.fetchNotifications(), isNotEmpty);
        await owner.markNotificationsRead();
        expect(
          (await owner.fetchNotifications()).every((n) => !n.unread),
          true,
        );
        final restored = DotNetBackend(sessions: ownerStore);
        clients.add(restored);
        await restored.init();
        expect((await restored.fetchMyProfile())?.id, owner.userId);
        await restored.deleteAccount();
        await expectLater(
          owner.fetchMyProfile(),
          throwsA(isBackendError('AUTH_REQUIRED')),
        );
      } finally {
        for (final api in clients.reversed) {
          try {
            if (api.hasSession) await api.deleteAccount();
          } on BackendException catch (e) {
            if (e.code != 'AUTH_REQUIRED') rethrow;
          } finally {
            api.dispose();
          }
        }
      }
    }, _RealHttp()),
    timeout: const Timeout(Duration(minutes: 3)),
    skip: !AppConfig.usesDotNet ? 'Yerel test API adresi verilmedi.' : false,
  );
}
