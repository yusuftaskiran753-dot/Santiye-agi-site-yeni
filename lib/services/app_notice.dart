/// Servislerin (senkron kuyruğu, mağaza) arayüze ilettiği kısa bildirimler.
///
/// Servisler Flutter'a bağımlı olmasın diye yalnızca bu veri sınıfını üretir;
/// ekranda nasıl gösterileceğine (renk, simge, süre) widgets/feedback.dart karar verir.
library;

enum NoticeKind { info, success, warning, error }

class AppNotice {
  const AppNotice(this.message, {this.kind = NoticeKind.info, this.actionLabel, this.action});

  const AppNotice.info(this.message, {this.actionLabel, this.action}) : kind = NoticeKind.info;
  const AppNotice.success(this.message, {this.actionLabel, this.action}) : kind = NoticeKind.success;
  const AppNotice.warning(this.message, {this.actionLabel, this.action}) : kind = NoticeKind.warning;
  const AppNotice.error(this.message, {this.actionLabel, this.action}) : kind = NoticeKind.error;

  final String message;
  final NoticeKind kind;

  /// İsteğe bağlı düğme (ör. "Tekrar dene").
  final String? actionLabel;
  final void Function()? action;

  @override
  String toString() => 'AppNotice(${kind.name}: $message)';
}
