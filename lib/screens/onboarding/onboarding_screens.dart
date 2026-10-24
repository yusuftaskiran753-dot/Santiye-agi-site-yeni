import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../config.dart';
import '../../state/app_state.dart';
import '../../theme.dart';
import '../../utils/format.dart';
import '../../widgets/common.dart';
import 'profile_form.dart';

/// Uygulama logosu (ikon + ad).
class AppLogo extends StatelessWidget {
  const AppLogo({super.key, this.size = 52});

  final double size;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            color: AppColors.brand,
            borderRadius: BorderRadius.circular(size * 0.3),
          ),
          child: Icon(
            Icons.engineering_rounded,
            color: Colors.white,
            size: size * 0.58,
          ),
        ),
        const SizedBox(width: 12),
        Text(
          AppConfig.appName,
          style: TextStyle(
            fontSize: size * 0.5,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.4,
          ),
        ),
      ],
    );
  }
}

class SplashScreen extends StatelessWidget {
  const SplashScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AppLogo(),
            SizedBox(height: 28),
            SizedBox(
              width: 26,
              height: 26,
              child: CircularProgressIndicator(strokeWidth: 2.6),
            ),
          ],
        ),
      ),
    );
  }
}

class StartupErrorScreen extends StatelessWidget {
  const StartupErrorScreen({super.key, required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: EmptyState(
            icon: Icons.wifi_off_rounded,
            title: 'Bağlanılamadı',
            message: message,
            actionLabel: 'Tekrar dene',
            onAction: () => context.read<AppState>().retryInit(),
          ),
        ),
      ),
    );
  }
}

/// İlk açılış: kısa tanıtım + koşulların kabulü.
class WelcomeScreen extends StatefulWidget {
  const WelcomeScreen({super.key});

  @override
  State<WelcomeScreen> createState() => _WelcomeScreenState();
}

class _WelcomeScreenState extends State<WelcomeScreen> {
  bool _accepted = false;
  bool _starting = false;

  Future<void> _start() async {
    if (_starting) return;
    setState(() => _starting = true);
    try {
      final app = context.read<AppState>();
      await app.refreshAuthPolicy();
      if (!mounted) return;
      await pushPage<void>(
        context,
        app.requiresPhoneVerification
            ? const PhoneAuthScreen()
            : const ProfileSetupScreen(),
      );
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _starting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(22, 28, 22, 24),
          children: [
            const AppLogo(),
            const SizedBox(height: 26),
            const Text(
              'Şantiyenin pazar yeri.',
              style: TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.w800,
                height: 1.15,
                letterSpacing: -0.5,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Yük, iş makinesi, malzeme ve operatör ilanları tek uygulamada. Aracısız ve komisyonsuz anlaşın.',
              style: TextStyle(color: muted, fontSize: 16, height: 1.4),
            ),
            const SizedBox(height: 26),
            const _Point(
              Icons.campaign_outlined,
              'İlan verin, teklif toplayın',
              'Yükünüz, makineniz veya ürününüz için dakikalar içinde ilan verin; teklifler bildirim olarak gelsin.',
            ),
            const _Point(
              Icons.handshake_outlined,
              'Doğrudan anlaşın',
              'Ödemeler taraflar arasında doğrudan yapılır; uygulama paranıza dokunmaz, aracılık ücreti kesmez.',
            ),
            const _Point(
              Icons.verified_user_outlined,
              'Kayıt ve puanla güvende kalın',
              'Dijital anlaşma kaydı, ödeme takibi ve yalnızca tamamlanan işlerden gelen puanlar.',
            ),
            const SizedBox(height: 20),
            Card(
              child: CheckboxListTile(
                value: _accepted,
                onChanged: (v) => setState(() => _accepted = v ?? false),
                controlAffinity: ListTileControlAffinity.leading,
                title: const Text(
                  'Kullanım Koşulları\'nı kabul ediyorum; Gizlilik Politikası ve KVKK Aydınlatma Metni\'ni okudum.',
                  style: TextStyle(fontSize: 14),
                ),
                subtitle: const Text(
                  'Uygulama bir ilan ve buluşma platformudur; iş, teslimat ve ödemenin tarafı değildir. '
                  'Uygunsuz içerik ve kötüye kullanım hoş görülmez.',
                  style: TextStyle(fontSize: 12.5),
                ),
              ),
            ),
            const LegalLinks(),
            const SizedBox(height: 8),
            FilledButton(
              onPressed: _accepted && !_starting ? _start : null,
              child: const Text('Başla'),
            ),
            if (context.watch<AppState>().passwordLoginEnabled)
              TextButton(
                onPressed: _accepted && !_starting
                    ? () => pushPage<void>(context, const AccountLoginScreen())
                    : null,
                child: const Text('Hesabım var — kullanıcı adıyla giriş'),
              ),
            if (!context.read<AppState>().isLive) ...[
              const SizedBox(height: 14),
              const InfoBanner(
                title: 'Demo modu',
                text:
                    'Sunucu bağlanmadığı için veriler yalnızca bu cihazda tutulur. Örnek firmalar teklif ve '
                    'taleplerinize otomatik yanıt verir; böylece bütün akışı deneyebilirsiniz.',
                icon: Icons.science_outlined,
                color: AppColors.grey,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class AccountLoginScreen extends StatefulWidget {
  const AccountLoginScreen({super.key});
  @override
  State<AccountLoginScreen> createState() => _AccountLoginScreenState();
}

class _AccountLoginScreenState extends State<AccountLoginScreen> {
  final _username = TextEditingController();
  final _password = TextEditingController();
  bool _busy = false;
  @override
  void dispose() {
    _username.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    if (_busy) return;
    if (_username.text.trim().isEmpty || _password.text.length < 12) {
      showError(
        context,
        'Kullanıcı adınızı ve en az 12 karakterli parolanızı girin.',
      );
      return;
    }
    setState(() => _busy = true);
    try {
      await context.read<AppState>().signInWithPassword(
        _username.text,
        _password.text,
      );
      if (mounted) Navigator.of(context).popUntil((route) => route.isFirst);
    } catch (error) {
      if (mounted) showError(context, error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Hesabına giriş yap')),
    body: AutofillGroup(
      child: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          const Text(
            'Daha önce size tanımlanan kullanıcı adı ve parolayla hesabınıza erişin.',
          ),
          const SizedBox(height: 20),
          TextField(
            controller: _username,
            enabled: !_busy,
            autofillHints: const [AutofillHints.username],
            autocorrect: false,
            textCapitalization: TextCapitalization.none,
            decoration: const InputDecoration(labelText: 'Kullanıcı adı'),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _password,
            enabled: !_busy,
            obscureText: true,
            autofillHints: const [AutofillHints.password],
            autocorrect: false,
            enableSuggestions: false,
            onSubmitted: (_) => _login(),
            decoration: const InputDecoration(labelText: 'Parola'),
          ),
          const SizedBox(height: 24),
          FilledButton(
            onPressed: _busy ? null : _login,
            child: Text(_busy ? 'Giriş yapılıyor…' : 'Giriş yap'),
          ),
        ],
      ),
    ),
  );
}

class _Point extends StatelessWidget {
  const _Point(this.icon, this.title, this.text);

  final IconData icon;
  final String title;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          IconBadge(icon, size: 42),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 16,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  text,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Telefon + SMS kodu ile giriş (AppConfig.authMode == AuthMode.phone).
class PhoneAuthScreen extends StatefulWidget {
  const PhoneAuthScreen({super.key});

  @override
  State<PhoneAuthScreen> createState() => _PhoneAuthScreenState();
}

class _PhoneAuthScreenState extends State<PhoneAuthScreen> {
  final _phone = TextEditingController();
  final _code = TextEditingController();
  String? _sentTo;
  int _wait = 0;
  Timer? _timer;

  @override
  void dispose() {
    _timer?.cancel();
    _phone.dispose();
    _code.dispose();
    super.dispose();
  }

  void _startTimer() {
    _timer?.cancel();
    setState(() => _wait = 60);
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted || _wait <= 1) {
        t.cancel();
        if (mounted) setState(() => _wait = 0);
        return;
      }
      setState(() => _wait--);
    });
  }

  Future<void> _send() async {
    final phone = normalizePhoneTr(_phone.text);
    // SMS yalnızca cep telefonuna (5xx) gider; sabit hat kabul edilmez.
    if (phone.isEmpty || !phone.startsWith('+905')) {
      showSnack(
        context,
        'Geçerli bir cep telefonu yazın (05xx xxx xx xx)',
        kind: NoticeKind.warning,
      );
      return;
    }
    try {
      await context.read<AppState>().sendPhoneCode(phone);
      if (!mounted) return;
      setState(() => _sentTo = phone);
      _startTimer();
    } catch (e) {
      if (mounted) showError(context, e, onRetry: _send);
    }
  }

  Future<void> _verify() async {
    final phone = _sentTo;
    if (phone == null) return;
    if (!RegExp(r'^\d{6}$').hasMatch(_code.text.trim())) {
      showSnack(
        context,
        'SMS ile gelen 6 haneli kodu yazın',
        kind: NoticeKind.warning,
      );
      return;
    }
    final app = context.read<AppState>();
    final navigator = Navigator.of(context);
    try {
      final hasProfile = await app.verifyPhoneCode(phone, _code.text);
      if (hasProfile) {
        navigator.popUntil((r) => r.isFirst);
      } else {
        await navigator.pushReplacement(
          MaterialPageRoute<void>(
            builder: (_) => ProfileSetupScreen(verifiedPhone: phone),
          ),
        );
      }
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    final isLive = context.read<AppState>().isLive;
    return Scaffold(
      appBar: AppBar(title: const Text('Telefonla giriş')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
        children: [
          Text(
            _sentTo == null
                ? 'Cep telefonunuza tek kullanımlık bir kod gönderelim. Numaranız ilanlarda görünmez.'
                : '${formatPhoneDisplay(_sentTo!)} numarasına gönderilen 6 haneli kodu yazın.',
            style: TextStyle(color: muted, fontSize: 15, height: 1.4),
          ),
          const SizedBox(height: 18),
          if (_sentTo == null) ...[
            LabeledField(
              label: 'Cep telefonu',
              controller: _phone,
              hint: '05xx xxx xx xx',
              keyboardType: TextInputType.phone,
            ),
            AsyncButton(label: 'Kod gönder', onPressed: _send),
          ] else ...[
            TextField(
              controller: _code,
              autofocus: true,
              keyboardType: TextInputType.number,
              maxLength: 6,
              style: const TextStyle(
                fontSize: 24,
                letterSpacing: 8,
                fontWeight: FontWeight.w700,
              ),
              decoration: const InputDecoration(
                hintText: '······',
                counterText: '',
              ),
            ),
            const SizedBox(height: 14),
            AsyncButton(label: 'Doğrula', onPressed: _verify),
            const SizedBox(height: 6),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                TextButton(
                  onPressed: () => setState(() => _sentTo = null),
                  child: const Text('Numarayı değiştir'),
                ),
                TextButton(
                  onPressed: _wait > 0 ? null : _send,
                  child: Text(
                    _wait > 0 ? 'Tekrar gönder ($_wait)' : 'Kodu tekrar gönder',
                  ),
                ),
              ],
            ),
          ],
          if (context.read<AppState>().developmentPhoneCode != null) ...[
            const SizedBox(height: 12),
            InfoBanner(
              text:
                  'Geliştirme test kodu: ${context.read<AppState>().developmentPhoneCode}',
              icon: Icons.science_outlined,
              color: AppColors.grey,
            ),
          ],
          if (!isLive) ...[
            const SizedBox(height: 12),
            const InfoBanner(
              text: 'Demo modunda doğrulama kodu: 123456',
              icon: Icons.science_outlined,
              color: AppColors.grey,
            ),
          ],
        ],
      ),
    );
  }
}

/// Profil bilgileri (ilk açılış). Kaydedilince ana ekrana geçilir.
class ProfileSetupScreen extends StatelessWidget {
  const ProfileSetupScreen({super.key, this.verifiedPhone});

  final String? verifiedPhone;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Sizi tanıyalım')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
        children: [
          Text(
            'Bu bilgiler ilanlarınızda ve anlaşma kayıtlarınızda görünür. Telefon numaranızı iletişim '
            'hakkı açan kullanıcılar, teklif/talebin tarafları ve anlaşmanın tarafları görebilir.',
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 16),
          ProfileForm(
            submitLabel: 'Kaydet ve başla',
            initialPhone: verifiedPhone ?? '',
            phoneLocked: verifiedPhone != null,
            onSubmit: (input) async {
              final app = context.read<AppState>();
              final navigator = Navigator.of(context);
              try {
                await app.completeOnboarding(
                  name: input.name,
                  company: input.company,
                  role: input.role,
                  city: input.city,
                  phone: input.phone,
                );
                navigator.popUntil((r) => r.isFirst);
              } catch (e) {
                if (context.mounted) showError(context, e);
              }
            },
          ),
        ],
      ),
    );
  }
}
