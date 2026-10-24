import 'backend.dart';
import 'local_store.dart';

/// Başka hesapla giriş yapıldığında önceki hesabın ödemesi silinmez veya
/// yanlış hesap adına yeniden gönderilmez. Eski sahipsiz kayıtlar da korunur.
class PurchaseVerificationQueue {
  PurchaseVerificationQueue(this.store);
  final LocalStore store;
  static const key = 'billing_pending_claims';
  Future<void> _writes = Future.value();

  List<StoreClaim> forUser(String? owner) {
    if (owner == null || owner.isEmpty) return [];
    return [
      for (final row in store.readMaps(key))
        if (row['owner_id'] == owner) StoreClaim.fromJson(row),
    ];
  }

  Future<void> save(String owner, StoreClaim claim) => _change(() {
    final rows = store.readMaps(key);
    rows.removeWhere(
      (r) =>
          r['owner_id'] == owner &&
          r['platform'] == claim.platform &&
          r['token'] == claim.token,
    );
    rows.add({...claim.toJson(), 'owner_id': owner});
    return rows;
  });
  Future<void> remove(String owner, StoreClaim claim) => _change(() {
    final rows = store.readMaps(key);
    rows.removeWhere(
      (r) =>
          r['owner_id'] == owner &&
          r['platform'] == claim.platform &&
          r['token'] == claim.token,
    );
    return rows;
  });
  Future<void> _change(List<Map<String, dynamic>> Function() apply) {
    final next = _writes.then((_) => store.writeMaps(key, apply()));
    _writes = next.catchError((Object _) {});
    return next;
  }
}
