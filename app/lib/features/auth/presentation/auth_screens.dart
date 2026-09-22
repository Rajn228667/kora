import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
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
  String _channel = 'sms';
  bool _loading = false;
  String? _error;

  bool get _valid => KzPhoneFormatter.isValid(_controller.text);

  Future<void> _submit() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final repo = ref.read(authRepositoryProvider);
      final req = await repo.requestOtp(
          KzPhoneFormatter.toE164(_controller.text),
          channel: _channel,);
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
                prefix: const Padding(
                  padding: EdgeInsets.symmetric(horizontal: AppSpacing.md),
                  child: KazakhstanFlag(),
                ),
                keyboardType: TextInputType.phone,
                inputFormatters: const [KzPhoneFormatter()],
                errorText: _error,
                autofocus: true,
                semanticLabel: S.t('phone.semantic'),
                onChanged: (value) => setState(() {
                  final digits = value.replaceAll(RegExp(r'\D'), '').length;
                  _error =
                      digits >= 11 && !_valid ? S.t('phone.invalid') : null;
                }),
                onSubmitted: (_) {
                  if (_valid) {
                    _submit();
                  } else {
                    setState(() => _error = S.t('phone.invalid'));
                  }
                },
              ),
              const SizedBox(height: AppSpacing.lg),
              Text(
                S.t('phone.channel_label'),
                style: AppTypography.overline,
              ),
              const SizedBox(height: AppSpacing.sm),
              SizedBox(
                width: double.infinity,
                child: SegmentedButton<String>(
                  segments: [
                    ButtonSegment(
                      value: 'sms',
                      label: Text(S.t('phone.channel_sms')),
                      icon: const Icon(AppIcons.send, size: 18),
                    ),
                    ButtonSegment(
                      value: 'whatsapp',
                      label: Text(S.t('phone.channel_whatsapp')),
                      icon: const Icon(AppIcons.chat, size: 18),
                    ),
                  ],
                  selected: {_channel},
                  onSelectionChanged: (v) =>
                      setState(() => _channel = v.first),
                  style: ButtonStyle(
                    visualDensity: VisualDensity.comfortable,
                    textStyle: WidgetStatePropertyAll(AppTypography.label),
                  ),
                ),
              ),
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
      final req = await repo.requestOtp(widget.request.phone,
          channel: widget.request.channel,);
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
  final _name = TextEditingController();
  final _lastName = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  bool _terms = false;
  bool _privacy = false;
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _lastName.dispose();
    _email.dispose();
    _password.dispose();
    _confirm.dispose();
    super.dispose();
  }

  bool get _valid =>
      _name.text.trim().isNotEmpty &&
      _lastName.text.trim().isNotEmpty &&
      _terms &&
      _privacy &&
      (_password.text.isEmpty ||
          (_password.text.length >= 8 &&
              _password.text == _confirm.text));

  Future<void> _save() async {
    if (!_valid) {
      setState(() => _error = (!_terms || !_privacy)
          ? S.t('profile_setup.consent_error')
          : _password.text.isNotEmpty &&
                  (_password.text.length < 8 ||
                      _password.text != _confirm.text)
              ? S.t('profile_setup.password_error')
              : null,);
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final repo = ref.read(authRepositoryProvider);
      final email = _email.text.trim();
      final user = await repo.updateProfile(
        name: _name.text.trim(),
        lastName: _lastName.text.trim(),
        email: email.isEmpty ? null : email,
        acceptTerms: true,
        acceptPrivacy: true,
      );
      // Optional password — enables password login fallback later.
      if (_password.text.isNotEmpty) {
        await repo.setPassword(newPassword: _password.text);
      }
      if (!mounted) return;
      ref.read(authControllerProvider.notifier).setUser(user);
      context.go('/home');
    } on ApiException catch (e) {
      setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: AppSpacing.screenPadding,
          children: [
            const SizedBox(height: AppSpacing.xl),
            Text(S.t('profile_setup.title'), style: AppTypography.headline),
            const SizedBox(height: AppSpacing.sm),
            Text(
              S.t('profile_setup.subtitle'),
              style: AppTypography.bodySecondary,
            ),
            const SizedBox(height: AppSpacing.xl),
            KoraTextField(
              controller: _name,
              hint: S.t('profile_setup.hint'),
              autofocus: true,
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: AppSpacing.sm),
            KoraTextField(
              controller: _lastName,
              hint: S.t('profile_setup.lastname'),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: AppSpacing.sm),
            KoraTextField(
              controller: _email,
              hint: S.t('profile_setup.email'),
              keyboardType: TextInputType.emailAddress,
            ),
            const SizedBox(height: AppSpacing.sm),
            KoraTextField(
              controller: _password,
              hint: S.t('profile_setup.password'),
              obscure: true,
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: AppSpacing.sm),
            KoraTextField(
              controller: _confirm,
              hint: S.t('profile_setup.password_confirm'),
              obscure: true,
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: AppSpacing.md),
            _ConsentTile(
              value: _terms,
              label: S.t('profile_setup.terms'),
              onChanged: (v) => setState(() => _terms = v),
            ),
            _ConsentTile(
              value: _privacy,
              label: S.t('profile_setup.privacy'),
              onChanged: (v) => setState(() => _privacy = v),
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: AppSpacing.sm),
                child: Text(
                  _error!,
                  style: AppTypography.caption
                      .copyWith(color: KoraColors.error),
                ),
              ),
            const SizedBox(height: AppSpacing.xl),
            KoraButton(
              label: S.t('profile_setup.continue'),
              loading: _loading,
              onPressed: _save,
            ),
            const SizedBox(height: AppSpacing.xl),
          ],
        ),
      ),
    );
  }
}

class _ConsentTile extends StatelessWidget {
  const _ConsentTile({
    required this.value,
    required this.label,
    required this.onChanged,
  });

  final bool value;
  final String label;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => onChanged(!value),
      borderRadius: BorderRadius.circular(AppRadius.sm),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
        child: Row(
          children: [
            SizedBox(
              width: 22,
              height: 22,
              child: Checkbox(
                value: value,
                onChanged: (v) => onChanged(v ?? false),
                activeColor: KoraColors.primary,
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(child: Text(label, style: AppTypography.caption)),
          ],
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
