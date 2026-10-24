import '../models/live_location.dart';

/// Authenticated live-location operations, separate from the normal backend.
/// A stream event is a complete current snapshot, including an empty list when
/// sharing stops. Implementations must never replay removed coordinates.
abstract interface class LiveLocationBackend {
  String? get userId;

  /// A duration starts/renews a share by explicit user action. Omitting both
  /// duration arguments only updates an existing share, without extending it.
  Future<DateTime> shareLocation(
    String dealId,
    LocationFix fix, {
    int? minutes,
    bool untilDelivered = false,
  });

  Future<void> stopLocation(String dealId);
  Future<List<LiveLocation>> fetchLiveLocations(String dealId);
  Stream<List<LiveLocation>> watchLiveLocations(String dealId);
}
