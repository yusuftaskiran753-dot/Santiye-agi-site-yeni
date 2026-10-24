/// Optional server capability. No provider key is shipped with the app.
abstract interface class AiBackend {
  Future<bool> aiAvailable();
  Future<Map<String, dynamic>> understandText(
    String text, {
    required String city,
  });
}
