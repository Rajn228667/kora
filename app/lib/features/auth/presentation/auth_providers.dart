import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/models/models.dart';
import '../data/auth_repository.dart';

/// Global auth state consumed by the router redirect.
sealed class AuthState {
  const AuthState();
}

final class AuthLoading extends AuthState {
  const AuthLoading();
}

final class Unauthenticated extends AuthState {
  const Unauthenticated();
}

final class Authenticated extends AuthState {
  const Authenticated(this.user, {this.needsProfile = false});
  final User user;
  final bool needsProfile;
}

class AuthController extends Notifier<AuthState> {
  @override
  AuthState build() {
    Future.microtask(_restore);
    return const AuthLoading();
  }

  Future<void> _restore() async {
    final repo = ref.read(authRepositoryProvider);
    final user = await repo.restoreSession();
    state = user == null
        ? const Unauthenticated()
        : Authenticated(user, needsProfile: user.name.isEmpty);
  }

  void setUser(User user, {bool needsProfile = false}) {
    state = Authenticated(user, needsProfile: needsProfile);
  }

  Future<void> logout() async {
    await ref.read(authRepositoryProvider).logout();
    state = const Unauthenticated();
  }

  Future<void> deleteAccount({String? password}) async {
    await ref.read(authRepositoryProvider).deleteAccount(password: password);
    state = const Unauthenticated();
  }
}

final authControllerProvider =
    NotifierProvider<AuthController, AuthState>(AuthController.new);
