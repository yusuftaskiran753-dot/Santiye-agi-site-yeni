/// Bildirim belirtecini oturum açmış hesaba bağlayan API yeteneği.
abstract interface class PushBackend {
  Future<void> registerPushDevice(String token, String platform);
  Future<void> unregisterPushDevice();
  void receivedPush({bool opened = false});
}
