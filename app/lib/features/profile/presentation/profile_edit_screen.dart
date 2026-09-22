import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import '../../../core/l10n/app_strings.dart';
import '../../../core/models/models.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/theme/app_icons.dart';
import '../../../core/theme/app_metrics.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/theme/kora_colors.dart';
import '../../../core/widgets/buttons.dart';
import '../../../core/widgets/feedback.dart';
import '../../../core/widgets/fields.dart';
import '../../../core/widgets/misc.dart';
import '../../auth/data/auth_repository.dart';
import '../../auth/presentation/auth_providers.dart';

const _kAvatarMaxBytes = 2 * 1024 * 1024;

/// Maps the profile background choice to brand-consistent fills.
Color profileBgColor(String key) => switch (key) {
      'white' => KoraColors.white,
      'purple' => KoraColors.softPurple,
      'mist' => KoraColors.veryLightPurple,
      _ => KoraColors.lightPurple,
    };

Color profileBgTextColor(String key) =>
    key == 'purple' ? KoraColors.white : KoraColors.brandNavy;

class ProfileEditScreen extends ConsumerStatefulWidget {
  const ProfileEditScreen({super.key});

  @override
  ConsumerState<ProfileEditScreen> createState() => _ProfileEditScreenState();
}

class _ProfileEditScreenState extends ConsumerState<ProfileEditScreen> {
  final _name = TextEditingController();
  final _lastName = TextEditingController();
  final _nickname = TextEditingController();
  final _email = TextEditingController();
  String _bg = 'lavender';
  String? _avatarUrl;
  bool _loading = false;
  bool _uploading = false;
  bool _seeded = false;

  @override
  void dispose() {
    _name.dispose();
    _lastName.dispose();
    _nickname.dispose();
    _email.dispose();
    super.dispose();
  }

  void _seed(User user) {
    if (_seeded) return;
    _seeded = true;
    _name.text = user.name;
    _lastName.text = user.lastName;
    _nickname.text = user.nickname ?? '';
    _email.text = user.email ?? '';
    _bg = user.profileBg;
    _avatarUrl = user.avatarUrl;
  }

  Future<void> _pickAvatar() async {
    final picked = await ImagePicker()
        .pickImage(source: ImageSource.gallery, maxWidth: 1024);
    if (picked == null) return;
    final Uint8List bytes = await picked.readAsBytes();
    if (bytes.length > _kAvatarMaxBytes) {
      if (mounted) {
        KoraSnackbar.show(
          context,
          S.t('profile_edit.avatar_too_big'),
          isError: true,
        );
      }
      return;
    }
    setState(() => _uploading = true);
    try {
      final mime = picked.mimeType ?? 'image/jpeg';
      final url = await ref
          .read(authRepositoryProvider)
          .uploadAvatar(bytes, mime);
      if (!mounted) return;
      final user = await ref
          .read(authRepositoryProvider)
          .updateProfile(avatarUrl: url);
      ref.read(authControllerProvider.notifier).setUser(user);
      setState(() => _avatarUrl = url);
    } on ApiException catch (e) {
      if (mounted) {
        KoraSnackbar.show(context, e.message, isError: true);
      }
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  Future<void> _save() async {
    setState(() => _loading = true);
    try {
      final user = await ref.read(authRepositoryProvider).updateProfile(
            name: _name.text.trim(),
            lastName: _lastName.text.trim(),
            nickname: _nickname.text.trim(),
            profileBg: _bg,
            email: _email.text.trim(),
          );
      if (!mounted) return;
      ref.read(authControllerProvider.notifier).setUser(user);
      context.pop();
    } on ApiException catch (e) {
      KoraSnackbar.show(context, e.message, isError: true);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authControllerProvider);
    final user = switch (auth) {
      Authenticated(user: final u) => u,
      _ => null,
    };
    if (user == null) return const Scaffold();
    _seed(user);

    return Scaffold(
      appBar: AppBar(
        leading: const BackButton(),
        title: Text(S.t('profile_edit.title')),
      ),
      body: ListView(
        padding: AppSpacing.screenPadding,
        children: [
          const SizedBox(height: AppSpacing.lg),
          Center(
            child: GestureDetector(
              onTap: _uploading ? null : _pickAvatar,
              child: Stack(
                children: [
                  KoraAvatar(
                    imageUrl: _avatarUrl,
                    initials: _name.text.isEmpty
                        ? '?'
                        : _name.text.substring(0, 1).toUpperCase(),
                    radius: 48,
                  ),
                  Positioned(
                    right: 0,
                    bottom: 0,
                    child: Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: KoraColors.primary,
                        shape: BoxShape.circle,
                        border: Border.all(color: KoraColors.white, width: 2),
                      ),
                      child: _uploading
                          ? const SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: KoraColors.white,
                              ),
                            )
                          : const Icon(AppIcons.camera,
                              size: 14, color: KoraColors.white,),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.xxs),
          Center(
            child: Text(
              S.t('profile_edit.avatar_hint'),
              style: AppTypography.caption,
            ),
          ),
          const SizedBox(height: AppSpacing.xl),
          KoraTextField(controller: _name, hint: S.t('profile_edit.name')),
          const SizedBox(height: AppSpacing.sm),
          KoraTextField(
            controller: _lastName,
            hint: S.t('profile_edit.lastname'),
          ),
          const SizedBox(height: AppSpacing.sm),
          KoraTextField(
            controller: _nickname,
            hint: S.t('profile_edit.nickname'),
          ),
          const SizedBox(height: AppSpacing.sm),
          KoraTextField(
            controller: _email,
            hint: S.t('profile_edit.email'),
            keyboardType: TextInputType.emailAddress,
          ),
          const SizedBox(height: AppSpacing.xl),
          Text(S.t('profile_edit.bg'), style: AppTypography.label),
          const SizedBox(height: AppSpacing.sm),
          Row(
            children: [
              for (final key in const ['lavender', 'white', 'purple', 'mist'])
                Padding(
                  padding: const EdgeInsets.only(right: AppSpacing.sm),
                  child: _BgSwatch(
                    color: profileBgColor(key),
                    selected: _bg == key,
                    onTap: () => setState(() => _bg = key),
                  ),
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.xl),
          KoraButton(
            label: S.t('common.save'),
            loading: _loading,
            onPressed: _save,
          ),
          const SizedBox(height: AppSpacing.xl),
        ],
      ),
    );
  }
}

class _BgSwatch extends StatelessWidget {
  const _BgSwatch({
    required this.color,
    required this.selected,
    required this.onTap,
  });

  final Color color;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          border: Border.all(
            color: selected ? KoraColors.primary : KoraColors.border,
            width: selected ? 2.5 : 1,
          ),
        ),
        child: selected
            ? const Icon(AppIcons.check, size: 18, color: KoraColors.primary)
            : null,
      ),
    );
  }
}
