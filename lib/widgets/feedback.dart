import 'dart:async';

import 'package:flutter/material.dart';

import '../services/app_notice.dart';
import '../services/backend.dart';
import '../theme.dart';

/// Uygulama genelinde tek tip kullanıcı geri bildirimi (Snackbar / toast).
///
/// * Başarı, bilgi, uyarı ve hata mesajları ayrı renk ve simgeyle gösterilir.
/// * [messengerKey] MaterialApp'e bağlıdır; böylece ekran kapandıktan sonra
///   gelen sonuçlar (ör. mağaza doğrulaması, çevrimdışı kuyruğun gönderilmesi)
///   da kullanıcıya ulaşır.
/// * Aynı mesaj kısa sürede tekrar gelirse yeniden gösterilmez.
abstract final class AppFeedback {
  static final GlobalKey<ScaffoldMessengerState> messengerKey =
      GlobalKey<ScaffoldMessengerState>();

  static String? _lastMessage;
  static DateTime _lastAt = DateTime.fromMillisecondsSinceEpoch(0);

  /// Testlerde ve dışarıdan izleme için son gösterilen mesaj.
  @visibleForTesting
  static String? get lastMessage => _lastMessage;

  static void show(
    String message, {
    NoticeKind kind = NoticeKind.info,
    BuildContext? context,
    String? actionLabel,
    VoidCallback? onAction,
    Duration? duration,
  }) {
    final text = message.trim();
    if (text.isEmpty) return;
    final now = DateTime.now();
    if (text == _lastMessage &&
        now.difference(_lastAt) < const Duration(seconds: 2)) {
      return;
    }

    ScaffoldMessengerState? messenger;
    if (context != null && context.mounted) {
      messenger = ScaffoldMessenger.maybeOf(context);
    }
    messenger ??= messengerKey.currentState;
    if (messenger == null) {
      debugPrint('Geri bildirim (gösterilemedi): $text');
      return;
    }
    _lastMessage = text;
    _lastAt = now;

    final (Color? background, IconData icon) = switch (kind) {
      NoticeKind.success => (AppColors.green, Icons.check_circle_rounded),
      NoticeKind.warning => (AppColors.amber, Icons.warning_amber_rounded),
      NoticeKind.error => (AppColors.red, Icons.error_outline_rounded),
      NoticeKind.info => (null, Icons.info_outline_rounded),
    };
    final foreground = background == null
        ? Theme.of(messenger.context).colorScheme.onInverseSurface
        : Colors.white;
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          backgroundColor: background,
          duration:
              duration ??
              (kind == NoticeKind.error || actionLabel != null
                  ? const Duration(seconds: 6)
                  : const Duration(seconds: 4)),
          content: Row(
            children: [
              Icon(icon, color: foreground, size: 20),
              const SizedBox(width: 10),
              Expanded(
                child: Text(text, style: TextStyle(color: foreground)),
              ),
            ],
          ),
          action: actionLabel == null || onAction == null
              ? null
              : SnackBarAction(
                  label: actionLabel,
                  textColor: foreground,
                  onPressed: onAction,
                ),
        ),
      );
  }

  static void success(String message, {BuildContext? context}) =>
      show(message, kind: NoticeKind.success, context: context);

  static void info(
    String message, {
    BuildContext? context,
    String? actionLabel,
    VoidCallback? onAction,
  }) => show(
    message,
    kind: NoticeKind.info,
    context: context,
    actionLabel: actionLabel,
    onAction: onAction,
  );

  static void warning(
    String message, {
    BuildContext? context,
    String? actionLabel,
    VoidCallback? onAction,
  }) => show(
    message,
    kind: NoticeKind.warning,
    context: context,
    actionLabel: actionLabel,
    onAction: onAction,
  );

  /// Hatayı Türkçe ve anlaşılır biçimde gösterir. Bağlantı / sunucu kaynaklı
  /// geçici hatalarda [onRetry] verilmişse "Tekrar dene" düğmesi çıkar.
  static void error(
    Object error, {
    BuildContext? context,
    VoidCallback? onRetry,
  }) {
    final e = BackendException.from(error);
    if (e.code == 'UNKNOWN') debugPrint('Beklenmeyen hata: $error');
    final retryable = e.isTransient && onRetry != null;
    show(
      e.message,
      kind: e.code == 'NETWORK' ? NoticeKind.warning : NoticeKind.error,
      context: context,
      actionLabel: retryable ? 'Tekrar dene' : null,
      onAction: retryable ? onRetry : null,
    );
  }

  static void notice(AppNotice n) => show(
    n.message,
    kind: n.kind,
    actionLabel: n.actionLabel,
    onAction: n.action,
  );

  /// Servis bildirim akışlarını genel gösterime bağlar.
  static StreamSubscription<AppNotice> listen(Stream<AppNotice> notices) =>
      notices.listen(notice);

  /// Yakalanmamış hatalar için tek, sakin bir mesaj (aynı mesaj tekrarlanmaz).
  static void unexpected(Object error) {
    final e = BackendException.from(error);
    show(
      e.code == 'UNKNOWN'
          ? 'Beklenmeyen bir sorun oluştu. İşleminizi kontrol edip tekrar deneyin.'
          : e.message,
      kind: e.code == 'NETWORK' ? NoticeKind.warning : NoticeKind.error,
    );
  }
}
