import 'dart:typed_data';
import '../models/work_photo.dart';

abstract interface class PortfolioBackend {
  Future<List<WorkPhoto>> fetchWorkPhotos(String userId);
  Future<Uint8List> fetchWorkPhotoBytes(String id);
  Future<WorkPhoto> uploadWorkPhoto(
    Uint8List bytes,
    String caption, {
    required String id,
  });
  Future<void> deleteWorkPhoto(String id);
}
