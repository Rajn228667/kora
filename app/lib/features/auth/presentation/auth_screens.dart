import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/config/env.dart';
import '../../../core/l10n/app_strings.dart';
import '../../../core/media/kora_image.dart';
import '../../../core/models/models.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/theme/app_icons.dart';
import '../../../core/theme/app_metrics.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/theme/kora_colors.dart';
import '../../../core/widgets/buttons.dart';
import '../../../core/widgets/feedback.dart';
import '../../../core/widgets/fields.dart';
import '../data/auth_repository.dart';
import 'auth_providers.dart';

// ---------------------------------------------------------------------------
// Welcome — value prop + start auth.
// ---------------------------------------------------------------------------

class WelcomeScreen extends StatelessWidget {
  const WelcomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: AppSpacing.screenPadding,
          child: Column(
            children: [
              const SizedBox(height: AppSpacing.xl),
              ClipRRect(
                borderRadius: AppRadius.card,
                child: Stack(
                  children: [
                    const KoraImage(
                      url:
                          'https://images.unsplash.com/photo-1504674900247-0877df9cc836?auto=format&fit=crop&w=1920&q=90',
                      height: 230,
                      width: double.infinity,
                    ),
                    Positioned(
                      bottom: AppSpacing.md,
                      left: AppSpacing.md,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: AppSpacing.sm,
                          vertical: AppSpacing.xxs,
                        ),
                        decoration: BoxDecoration(
                          color: KoraColors.white,
                          borderRadius: BorderRadius.circular(AppRadius.pill),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Image.asset(
                              'assets/brand/kora_logo_k.png',
                              width: 18,
                              height: 18,
                            ),
                            const SizedBox(width: AppSpacing.xs),
                            Text(
                              'KORA',
                              style: AppTypography.label.copyWith(
                                color: KoraColors.brandNavy,
                                letterSpacing: 1.2,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const Spacer(),
              Text(
                'KORA',
                style: AppTypography.displayLarge.copyWith(
                  color: KoraTheme.dark
                      ? KoraColors.darkTextPrimary
                      : KoraColors.brandNavy,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.5,
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(
                S.t('welcome.subtitle'),
                textAlign: TextAlign.center,
                style: AppTypography.bodySecondary,
              ),
              const SizedBox(height: AppSpacing.xl),
              _FeatureRow(
                icon: AppIcons.bike,
                text: S.t('welcome.f_delivery'),
              ),
              const SizedBox(height: AppSpacing.sm),
              _FeatureRow(
                icon: AppIcons.wallet,
                text: S.t('welcome.f_cashback'),
              ),
              const SizedBox(height: AppSpacing.sm),
              _FeatureRow(
                icon: AppIcons.locationOut,
                text: S.t('welcome.f_tracking'),
              ),
              const Spacer(),
              KoraButton(
                label: S.t('welcome.cta'),
                icon: AppIcons.phone,
                onPressed: () => context.push('/auth/phone'),
              ),
              const SizedBox(height: AppSpacing.xxl),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Phone input (+7 mask).
// ---------------------------------------------------------------------------

class PhoneScreen extends ConsumerStatefulWidget {
  const PhoneScreen({super.key});

  @override
  ConsumerState<PhoneScreen> createState() => _PhoneScreenState();
}

class _PhoneScreenState extends ConsumerState<PhoneScreen> {
  final _controller = TextEditingController(text: '+7 ');
  bool _loading = false;
  String? _error;

  bool get _valid => KzPhoneFormatter.toE164(_controller.text).length == 12;

  Future<void> _submit() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final repo = ref.read(authRepositoryProvider);
      final req =
          await repo.requestOtp(KzPhoneFormatter.toE164(_controller.text));
      if (!mounted) return;
      unawaited(context.push('/auth/otp', extra: req));
    } on ApiException catch (e) {
      setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(leading: const BackButton()),
      body: SafeArea(
        child: Padding(
          padding: AppSpacing.screenPadding,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(S.t('phone.title'), style: AppTypography.headline),
              const SizedBox(height: AppSpacing.sm),
              Text(
                S.t('phone.subtitle'),
                style: AppTypography.bodySecondary,
              ),
              const SizedBox(height: AppSpacing.xxl),
              KoraTextField(
                controller: _controller,
                hint: S.t('phone.hint'),
                keyboardType: TextInputType.phone,
                inputFormatters: const [KzPhoneFormatter()],
                errorText: _error,
                autofocus: true,
                semanticLabel: S.t('phone.semantic'),
                onChanged: (_) => setState(() => _error = null),
                onSubmitted: (_) => _valid ? _submit() : null,
              ),
              if (AppEnv.isDev) ...[
                const SizedBox(height: AppSpacing.md),
                Text(
                  S.t('phone.dev_hint'),
                  style: AppTypography.caption,
                ),
              ],
              const Spacer(),
              KoraButton(
                label: S.t('phone.get_code'),
                loading: _loading,
                onPressed: _valid ? _submit : null,
              ),
              const SizedBox(height: AppSpacing.sm),
              Center(
                child: KoraGhostButton(
                  label: S.t('phone.admin_login'),
                  icon: AppIcons.admin,
                  onPressed: () => _staffLoginSheet(context),
                ),
              ),
              const SizedBox(height: AppSpacing.xl),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// OTP — 6-digit code with countdown resend.
// ---------------------------------------------------------------------------

class OtpScreen extends ConsumerStatefulWidget {
  const OtpScreen({super.key, required this.request});

  final OtpRequest request;

  @override
  ConsumerState<OtpScreen> createState() => _OtpScreenState();
}

class _OtpScreenState extends ConsumerState<OtpScreen> {
  final _controller = TextEditingController();
  Timer? _timer;
  int _secondsLeft = 0;
  bool _loading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _secondsLeft = widget.request.ttlSeconds;
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (_secondsLeft <= 1) {
        t.cancel();
        setState(() => _secondsLeft = 0);
      } else {
        setState(() => _secondsLeft--);
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  Future<void> _verify() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final repo = ref.read(authRepositoryProvider);
      final result = await repo.verifyOtp(widget.request, _controller.text);
      if (!mounted) return;
      ref
          .read(authControllerProvider.notifier)
          .setUser(result.user, needsProfile: result.user.name.isEmpty);
      context.go(result.user.name.isEmpty ? '/auth/profile' : '/home');
    } on ApiException catch (e) {
      setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _resend() async {
    try {
      final repo = ref.read(authRepositoryProvider);
      final req = await repo.requestOtp(widget.request.phone);
      if (!mounted) return;
      context.pushReplacement('/auth/otp', extra: req);
    } on ApiException catch (e) {
      KoraSnackbar.show(context, e.message, isError: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(leading: const BackButton()),
      body: SafeArea(
        child: Padding(
          padding: AppSpacing.screenPadding,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(S.t('otp.title'), style: AppTypography.headline),
              const SizedBox(height: AppSpacing.sm),
              Text(
                S.t('otp.sent_to', {'phone': widget.request.phone}),
                style: AppTypography.bodySecondary,
              ),
              if (widget.request.devOtp != null)
                Container(
                  margin: const EdgeInsets.only(top: AppSpacing.sm),
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.md,
                    vertical: AppSpacing.xs,
                  ),
                  decoration: BoxDecoration(
                    color: KoraColors.selected,
                    borderRadius: BorderRadius.circular(AppRadius.sm),
                  ),
                  child: Text(
                    S.t('otp.dev_code', {'code': '${widget.request.devOtp}'}),
                    style: AppTypography.caption
                        .copyWith(color: KoraColors.deepPurple),
                  ),
                ),
              const SizedBox(height: AppSpacing.xxl),
              KoraTextField(
                controller: _controller,
                hint: S.t('otp.hint'),
                keyboardType: TextInputType.number,
                maxLength: 6,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                errorText: _error,
                autofocus: true,
                semanticLabel: S.t('otp.semantic'),
                onChanged: (v) {
                  setState(() => _error = null);
                  if (v.length == 6) _verify();
                },
              ),
              const SizedBox(height: AppSpacing.lg),
              Center(
                child: _secondsLeft > 0
                    ? Text(
                        S.t('otp.resend_in', {'sec': '$_secondsLeft'}),
                        style: AppTypography.caption,
                      )
                    : KoraGhostButton(
                        label: S.t('otp.resend'),
                        onPressed: _resend,
                      ),
              ),
              const Spacer(),
              KoraButton(
                label: S.t('otp.confirm'),
                loading: _loading,
                onPressed: _controller.text.length == 6 ? _verify : null,
              ),
              const SizedBox(height: AppSpacing.xl),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Profile setup — first name after registration.
// ---------------------------------------------------------------------------

class ProfileSetupScreen extends ConsumerStatefulWidget {
  const ProfileSetupScreen({super.key});

  @override
  ConsumerState<ProfileSetupScreen> createState() => _ProfileSetupScreenState();
}

class _ProfileSetupScreenState extends ConsumerState<ProfileSetupScreen> {
  final _controller = TextEditingController();
  bool _loading = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final name = _controller.text.trim();
    if (name.isEmpty) return;
    setState(() => _loading = true);
    try {
      final user =
          await ref.read(authRepositoryProvider).updateProfile(name: name);
      if (!mounted) return;
      ref.read(authControllerProvider.notifier).setUser(user);
      context.go('/home');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: AppSpacing.screenPadding,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: AppSpacing.xxl),
              Text(S.t('profile_setup.title'), style: AppTypography.headline),
              const SizedBox(height: AppSpacing.sm),
              Text(
                S.t('profile_setup.subtitle'),
                style: AppTypography.bodySecondary,
              ),
              const SizedBox(height: AppSpacing.xxl),
              KoraTextField(
                controller: _controller,
                hint: S.t('profile_setup.hint'),
                autofocus: true,
                onChanged: (_) => setState(() {}),
                onSubmitted: (_) => _save(),
              ),
              const Spacer(),
              KoraButton(
                label: S.t('profile_setup.continue'),
                loading: _loading,
                onPressed: _controller.text.trim().isNotEmpty ? _save : null,
              ),
              const SizedBox(height: AppSpacing.xl),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Staff console login — email + password (manager/admin). Credentials are
// verified by the backend (`POST /auth/login`); nothing is stored client-side.
// ---------------------------------------------------------------------------

void _staffLoginSheet(BuildContext context) {
  KoraBottomSheet.show<void>(
    context,
    child: const StaffLoginSheet(),
  );
}

class StaffLoginSheet extends ConsumerStatefulWidget {
  const StaffLoginSheet({super.key});

  @override
  ConsumerState<StaffLoginSheet> createState() => _StaffLoginSheetState();
}

class _StaffLoginSheetState extends ConsumerState<StaffLoginSheet> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _loading = false;
  bool _obscure = true;
  String? _error;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    if (_email.text.trim().isEmpty || _password.text.isEmpty) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final router = GoRouter.of(context);
      final result = await ref
          .read(authRepositoryProvider)
          .loginWithPassword(_email.text.trim(), _password.text);
      ref.read(authControllerProvider.notifier).setUser(result.user);
      if (!mounted) return;
      Navigator.of(context).pop();
      // Admins and managers land on their consoles, not the customer home.
      final role = result.user.role;
      router.go(
        switch (role) {
          UserRole.admin => '/admin',
          UserRole.manager => '/manager',
          UserRole.courier => '/courier',
          UserRole.customer => '/home',
        },
      );
    } on ApiException catch (e) {
      setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: AppSpacing.cardPadding,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: const BoxDecoration(
                  gradient: KoraColors.primaryGradient,
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  AppIcons.admin,
                  color: KoraColors.white,
                  size: 20,
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Text(
                  S.t('admin.login_title'),
                  style: AppTypography.title,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.lg),
          KoraTextField(
            controller: _email,
            hint: S.t('admin.email'),
            keyboardType: TextInputType.emailAddress,
            prefixIcon: AppIcons.profile,
            autofocus: true,
          ),
          const SizedBox(height: AppSpacing.sm),
          KoraTextField(
            controller: _password,
            hint: S.t('admin.password'),
            obscure: _obscure,
            prefixIcon: AppIcons.security,
            suffix: IconButton(
              icon: Icon(
                _obscure ? AppIcons.eye : AppIcons.eyeOff,
                size: 20,
              ),
              onPressed: () => setState(() => _obscure = !_obscure),
            ),
            errorText: _error,
            onSubmitted: (_) => _login(),
          ),
          const SizedBox(height: AppSpacing.lg),
          KoraButton(
            label: S.t('admin.login_btn'),
            loading: _loading,
            onPressed: _login,
          ),
          SizedBox(height: MediaQuery.of(context).viewInsets.bottom),
        ],
      ),
    );
  }
}

class _FeatureRow extends StatelessWidget {
  const _FeatureRow({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: KoraColors.lightPurple,
            borderRadius: BorderRadius.circular(AppRadius.md),
          ),
          child: Icon(icon, color: KoraColors.primary, size: 18),
        ),
        const SizedBox(width: AppSpacing.md),
        Expanded(child: Text(text, style: AppTypography.body)),
      ],
    );
  }
}
