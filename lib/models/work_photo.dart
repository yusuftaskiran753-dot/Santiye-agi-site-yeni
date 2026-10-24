import 'models.dart';

class WorkPhoto {
  const WorkPhoto({
    required this.id,
    required this.ownerId,
    required this.caption,
  });
  final String id;
  final String ownerId;
  final String caption;
  factory WorkPhoto.fromJson(Map<String, dynamic> json) => WorkPhoto(
    id: asString(json['id']),
    ownerId: asString(json['owner_id']),
    caption: asString(json['caption']),
  );
}
