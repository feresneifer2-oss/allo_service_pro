import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:allo_service_pro/features/admin/application/admin_store.dart';
import 'package:allo_service_pro/features/admin/data/admin_auth_repository.dart';
import 'package:allo_service_pro/features/auth/application/user_store.dart';

import 'support/fake_admin_auth.dart';

/// Phase 1 — Admin authorization hardening (client-side contract).
///
/// The client holds NO admin secret and performs NO credential comparison:
/// membership is decided by the backend predicate `is_admin()` (SECURITY
/// DEFINER, keyed on `auth.uid()` — see
/// `supabase/migrations/20260927173046_phase1_admin_authorization.sql`).
///
/// These tests pin the client half of that contract:
///   1. every answer comes from the auth boundary (server), never from a
///      compiled-in credential pair;
///   2. the persisted routing marker is the SERVER-verified `auth.uid()`;
///   3. every failure mode is FAIL-CLOSED;
///   4. no credential material survives anywhere in `lib/`.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    UserStore.user.value = null;
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  tearDown(AdminAuth.resetToDefault);

  group('AdminStore.isAdminSignedIn · server-driven', () {
    test('answers exactly what the backend answers', () async {
      final fake = FakeAdminAuthRepository(enrolled: false);
      AdminAuth.configure(fake);

      expect(await AdminStore.isAdminSignedIn(), isFalse);
      expect(fake.isAdminCalls, 1, reason: 'the boundary must be consulted');

      fake.enrolled = true;
      expect(await AdminStore.isAdminSignedIn(), isTrue);
      expect(fake.isAdminCalls, 2);
    });
  });

  group('AdminAuthRepository.verifyAdminCredentials · sign-in gate', () {
    test('denies an identity the backend does not enrol (nothing persists)',
        () async {
      AdminAuth.configure(
        FakeAdminAuthRepository(
          enrolled: false,
          expectedEmail: 'operator@allo.test',
          expectedPassword: 'operator-pass',
        ),
      );

      expect(
        await AdminAuth.instance.verifyAdminCredentials(
          email: 'operator@allo.test',
          password: 'operator-pass',
        ),
        isNull,
      );

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool('is_logged_in'), isNull);
      expect(prefs.getString('user_role'), isNull);
      expect(prefs.getString('admin_uid'), isNull);
    });

    test('returns the server-verified uid for an enrolled identity', () async {
      AdminAuth.configure(
        FakeAdminAuthRepository(
          enrolled: true,
          uid: 'uid-operator-42',
          expectedEmail: 'operator@allo.test',
          expectedPassword: 'operator-pass',
        ),
      );

      expect(
        await AdminAuth.instance.verifyAdminCredentials(
          email: 'operator@allo.test',
          password: 'operator-pass',
        ),
        'uid-operator-42',
      );
    });

    test('refuses empty credentials without a remote exchange', () async {
      final fake = FakeAdminAuthRepository(enrolled: true, uid: 'uid-x');
      AdminAuth.configure(fake);

      expect(
        await AdminAuth.instance
            .verifyAdminCredentials(email: '', password: ''),
        isNull,
      );
      expect(fake.remoteExchanges, 0,
          reason: 'an empty pair must never be sent to the backend');
    });

    test('the production boundary is FAIL-CLOSED without a Supabase session',
        () async {
      // Default state of the app in this process: Supabase never initialized.
      expect(AdminAuth.instance, isA<SupabaseAdminAuthRepository>());
      expect(AdminAuth.instance.isConfigured, isFalse);
      expect(await AdminAuth.instance.isAdmin(), isFalse);
      expect(
        await AdminAuth.instance.verifyAdminCredentials(
          email: 'operator@allo.test',
          password: 'operator-pass',
        ),
        isNull,
      );
    });
  });

  group('persisted admin session marker', () {
    test('setAdminSession stores the VERIFIED uid and drops legacy markers',
        () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        // A pre-Phase-1 marker derived from the removed client-side gate.
        'admin_session_sig': 'stale-pre-phase-1-signature',
      });

      await UserStore.setAdminSession(adminUid: 'uid-operator-42');

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool('is_logged_in'), isTrue);
      expect(prefs.getString('user_role'), 'admin');
      expect(prefs.getString('admin_uid'), 'uid-operator-42');
      expect(prefs.getString('admin_session_sig'), isNull,
          reason: 'the obsolete client-side marker must never linger');
    });

    test('cold start re-confirms the SAME identity server-side', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        'is_logged_in': true,
        'user_role': 'admin',
        'admin_uid': 'uid-operator-42',
      });

      AdminAuth.configure(
        FakeAdminAuthRepository(enrolled: true, uid: 'uid-operator-42'),
      );
      expect(await UserStore.checkInitialSession(), 'admin');

      // Enrolment revoked server-side → the next boot opens as a guest, even
      // though the device still holds the old marker.
      AdminAuth.configure(
        FakeAdminAuthRepository(enrolled: false, uid: 'uid-operator-42'),
      );
      expect(await UserStore.checkInitialSession(), isNull);
    });

    test('sign-out wipes the admin marker and the legacy key', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        'is_logged_in': true,
        'user_role': 'admin',
        'admin_uid': 'uid-operator-42',
        'admin_session_sig': 'stale-pre-phase-1-signature',
      });

      expect(await UserStore.signOut(), isTrue);

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool('is_logged_in') ?? false, isFalse);
      expect(prefs.getString('user_role'), isNull);
      expect(prefs.getString('admin_uid'), isNull);
      expect(prefs.getString('admin_session_sig'), isNull);
    });
  });

  group('Phase 1 · source-level guards', () {
    /// Every Dart file shipped in `lib/`.
    List<File> libDartFiles() => Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'))
        .toList();

    String relative(File file) =>
        file.path.replaceAll('\\', '/').split('lib/').last;

    test('lib/ ships NO client-side admin credential material', () {
      const forbidden = <String>[
        'ADMIN_EMAIL',
        'ADMIN_PASSWORD',
        'LocalAdminAuthRepository',
        'adminSessionSignature',
        'sessionSignature',
      ];

      final offenders = <String>[];
      for (final file in libDartFiles()) {
        final text = file.readAsStringSync();
        for (final needle in forbidden) {
          if (text.contains(needle)) {
            offenders.add('${relative(file)} :: $needle');
          }
        }
      }

      expect(
        offenders,
        isEmpty,
        reason: 'the admin gate must not carry client-side credentials — '
            'authorization is server-side only',
      );
    });

    test('the legacy admin preference key is only ever REMOVED', () {
      final hits = <String>[];
      for (final file in libDartFiles()) {
        if (file.readAsStringSync().contains("'admin_session_sig'")) {
          hits.add(relative(file));
        }
      }

      expect(
        hits,
        <String>['features/auth/application/user_store.dart'],
        reason: 'only the documented legacy-cleanup constant may name the key',
      );
    });
  });
}
