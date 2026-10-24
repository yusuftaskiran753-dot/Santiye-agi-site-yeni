import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:santiye_agi/services/backend.dart';
import 'package:santiye_agi/services/local_store.dart';
import 'package:santiye_agi/services/purchase_verification_queue.dart';

void main() {
  late LocalStore store;
  late PurchaseVerificationQueue queue;
  const claim = StoreClaim(
    platform: 'android',
    productId: 'santiye_kredi_5',
    token: 'purchase-a',
  );
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    store = LocalStore(await SharedPreferences.getInstance());
    queue = PurchaseVerificationQueue(store);
  });
  test(
    'Bekleyen ödeme başka hesapta görünmez ve o hesabın temizliğiyle silinmez',
    () async {
      await queue.save('hesap-a', claim);
      expect(queue.forUser('hesap-b'), isEmpty);
      await queue.remove('hesap-b', claim);
      expect(queue.forUser('hesap-a').single.token, claim.token);
      await queue.remove('hesap-a', claim);
      expect(queue.forUser('hesap-a'), isEmpty);
    },
  );
  test(
    'Eşzamanlı gelen satın almalar ve yeniden teslim edilen makbuz kaybolmaz',
    () async {
      const second = StoreClaim(
        platform: 'ios',
        productId: 'santiye_kredi_15',
        token: 'purchase-b',
      );
      await Future.wait([
        queue.save('a', claim),
        queue.save('a', second),
        queue.save('a', claim),
      ]);
      expect(queue.forUser('a').map((c) => c.token).toSet(), {
        'purchase-a',
        'purchase-b',
      });
    },
  );
  test(
    'Eski sahipsiz kayıt korunur; mevcut hesaba kendiliğinden atanmaz',
    () async {
      await store.writeMaps(PurchaseVerificationQueue.key, [claim.toJson()]);
      expect(queue.forUser('a'), isEmpty);
      expect(queue.forUser(null), isEmpty);
      await queue.save(
        'b',
        const StoreClaim(
          platform: 'android',
          productId: 'santiye_kredi_5',
          token: 'new',
        ),
      );
      expect(store.readMaps(PurchaseVerificationQueue.key), hasLength(2));
      expect(
        store.readMaps(PurchaseVerificationQueue.key).first['owner_id'],
        isNull,
      );
    },
  );
}
