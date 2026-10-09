import 'package:flutter_test/flutter_test.dart';

import 'package:allo_service_pro/features/auth/data/profile_repository.dart';

/// Phase 2D — regression guard for the live-schema column mismatch.
///
/// Live `public.profiles` carries `full_name` (there is NO `name` column),
/// so the wire payload built by [ProfileRepository.buildProfileRow] must use
/// `full_name` and never `name`. Pure builder — no Supabase, no network.
void main() {
  test('profile row carries the display name as full_name, never name', () {
    final row = ProfileRepository.buildProfileRow(
      id: 'uid-1',
      email: 'a@b.c',
      name: 'Amina',
      phone: '+21620000000',
      role: 'client',
    );

    expect(row['full_name'], 'Amina');
    expect(row.containsKey('name'), isFalse);
    expect(
      row.keys.toSet(),
      <String>{'id', 'email', 'full_name', 'phone', 'role'},
    );
  });

  test('profile row omits role when null or empty', () {
    final withoutRole = ProfileRepository.buildProfileRow(
      id: 'uid-1',
      email: 'a@b.c',
      name: 'Amina',
      phone: '+21620000000',
    );
    expect(withoutRole.containsKey('role'), isFalse);
    expect(withoutRole.containsKey('name'), isFalse);
    expect(withoutRole['full_name'], 'Amina');

    final emptyRole = ProfileRepository.buildProfileRow(
      id: 'uid-1',
      email: 'a@b.c',
      name: 'Amina',
      phone: '+21620000000',
      role: '',
    );
    expect(emptyRole.containsKey('role'), isFalse);
  });

  group('Phase 2I — session-authenticated write gate', () {
    test('a row may only be written by the session of the same identity', () {
      // Happy path: the session's JWT belongs to the row's own identity.
      expect(
        ProfileRepository.canWriteOwnRow(
          id: 'uid-1',
          sessionUserId: 'uid-1',
          accessToken: 'jwt-1',
        ),
        isTrue,
      );
      // The policy is `auth.uid() = id`: another identity can only 42501.
      expect(
        ProfileRepository.canWriteOwnRow(
          id: 'uid-1',
          sessionUserId: 'uid-2',
          accessToken: 'jwt-2',
        ),
        isFalse,
      );
      // No session at all — the anonymous-key write that broke production.
      expect(
        ProfileRepository.canWriteOwnRow(
          id: 'uid-1',
          sessionUserId: null,
          accessToken: null,
        ),
        isFalse,
      );
      // A session without a token cannot authenticate anything either.
      expect(
        ProfileRepository.canWriteOwnRow(
          id: 'uid-1',
          sessionUserId: 'uid-1',
          accessToken: null,
        ),
        isFalse,
      );
      expect(
        ProfileRepository.canWriteOwnRow(
          id: 'uid-1',
          sessionUserId: 'uid-1',
          accessToken: '',
        ),
        isFalse,
      );
    });

    test('upsert without a session fails safe — false, no request', () async {
      // Supabase is NOT initialized in this test process: the gate must answer
      // `false` without throwing and without reaching the network.
      expect(
        await ProfileRepository.upsertProfile(
          id: 'uid-1',
          email: 'a@b.c',
          name: 'Amina',
          phone: '+21620000000',
          session: null,
        ),
        isFalse,
      );
    });
  });
}
