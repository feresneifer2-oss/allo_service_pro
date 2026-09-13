import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:allo_service_pro/features/auth/application/user_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    UserStore.user.value = null;
  });

  test('B5 · no session → null (guest routes to welcome)', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    expect(await UserStore.checkInitialSession(), isNull);
  });

  test('B5 · client session → client', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'is_logged_in': true,
      'user_role': 'client',
    });
    expect(await UserStore.checkInitialSession(), 'client');
  });

  test('B5 · professional session → professionnel', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'is_logged_in': true,
      'user_role': 'professionnel',
    });
    expect(await UserStore.checkInitialSession(), 'professionnel');
  });

  test('B5 · admin session → admin (exists outside the UserRole enum)',
      () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'is_logged_in': true,
      'user_role': 'admin',
    });
    expect(await UserStore.checkInitialSession(), 'admin');
  });

  test('B5 · legacy session (no role key) derives route from hydrated user',
      () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'is_logged_in': true,
    });
    UserStore.user.value = UserModel(
      id: 'u_legacy',
      name: 'Ancien Pro',
      phone: '55123456',
      role: UserRole.professional,
    );
    expect(await UserStore.checkInitialSession(), 'professionnel');
  });

  test('B5 · logged-out flag beats any in-memory user', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'is_logged_in': false,
      'user_role': 'client',
    });
    UserStore.user.value = UserModel(
      id: 'u_stale',
      name: 'X',
      phone: '1',
      role: UserRole.client,
    );
    expect(await UserStore.checkInitialSession(), isNull);
  });
}