import 'package:allo_service_pro/features/admin/data/admin_auth_repository.dart';

/// Test double for the SERVER-SIDE admin authorization boundary.
///
/// Production authorization lives in the Postgres predicate `is_admin()`
/// (SECURITY DEFINER, keyed on `auth.uid()`); unit and widget tests cannot
/// reach a database, so they inject this fake through
/// `AdminAuth.configure(...)` and drive the answers the backend can give:
///
///   • [enrolled] = true  → the identity IS an administrator ([uid] returned);
///   • [enrolled] = false → denied (not enrolled, revoked, offline, RPC error).
///
/// [expectedEmail] / [expectedPassword] make the fake credential-aware: when
/// provided, a mismatching pair is refused exactly like Supabase Auth would —
/// so a test can prove that the SERVER response (not the typed string) is what
/// decides the admin route.
class FakeAdminAuthRepository implements AdminAuthRepository {
  FakeAdminAuthRepository({
    this.enrolled = false,
    this.uid = 'uid-admin-test',
    this.expectedEmail,
    this.expectedPassword,
    this.configured = true,
    this.provisionSucceeds = true,
    this.rejectSucceeds = true,
  });

  /// Whether the backend considers the authenticated identity an admin.
  bool enrolled;

  /// The `auth.uid()` the backend reports for the authenticated identity.
  String uid;

  /// Optional credential expectations for the sign-in half of the gate.
  String? expectedEmail;
  String? expectedPassword;

  /// Whether a backend is reachable at all (Supabase configured).
  bool configured;

  /// Whether the provisioning RPC (`admin_provision_professional`) succeeds.
  /// A test flips this to `false` to simulate the RPC failing (offline,
  /// revoked admin, unknown profile, any server error).
  bool provisionSucceeds;

  /// Whether the rejection RPC (`admin_reject_professional`) succeeds — same
  /// fail-closed simulation as [provisionSucceeds] for the reject path.
  bool rejectSucceeds;

  /// How many times each remote call was consulted — lets a test assert the
  /// gate is genuinely server-driven.
  int isAdminCalls = 0;
  int credentialCalls = 0;

  /// How many times the provisioning RPC was consulted — lets a test assert
  /// the RPC IS called for a valid uuid and is NEVER called for a
  /// null/invalid one.
  int provisionCalls = 0;

  /// Exact arguments the LAST provisioning call carried (mapping proof).
  String? lastProvisionUserId;
  String? lastProvisionSpecialty;
  String? lastProvisionBio;

  /// How many times the rejection RPC was consulted, and the exact arguments
  /// the LAST call carried (mapping proof, parity with the provisioning
  /// counters above).
  int rejectCalls = 0;
  String? lastRejectUserId;
  String? lastRejectReason;

  /// Remote credential exchanges actually performed (an empty/invalid pair is
  /// refused locally, exactly like the production implementation, so this
  /// stays 0).
  int remoteExchanges = 0;

  @override
  bool get isConfigured => configured;

  @override
  String? get lastVerifiedUserId => (configured && enrolled) ? uid : null;

  @override
  Future<bool> isAdmin() async {
    isAdminCalls++;
    return configured && enrolled;
  }

  @override
  Future<String?> verifyAdminCredentials({
    required String email,
    required String password,
  }) async {
    credentialCalls++;
    // Mirrors the production guard: an empty pair never reaches the backend.
    if (email.isEmpty || password.isEmpty) return null;
    if (!configured) return null;
    remoteExchanges++;
    if (expectedEmail != null && email != expectedEmail) return null;
    if (expectedPassword != null && password != expectedPassword) return null;
    return enrolled ? uid : null;
  }

  @override
  Future<String?> provisionProfessional({
    required String userId,
    String? specialty,
    String? bio,
  }) async {
    provisionCalls++;
    lastProvisionUserId = userId;
    lastProvisionSpecialty = specialty;
    lastProvisionBio = bio;
    // Mirrors the production fail-closed boundary: no reachable backend, no
    // admin identity, or a server-side refusal can never CONFIRM a
    // provisioning — the caller then keeps the professional pending.
    if (!configured || !enrolled || !provisionSucceeds) return null;
    // The production RPC returns the (verified) professional id — the same
    // uuid it was asked to provision.
    return userId;
  }

  @override
  Future<bool> rejectProfessional({
    required String userId,
    required String reason,
  }) async {
    rejectCalls++;
    lastRejectUserId = userId;
    lastRejectReason = reason;
    // Mirrors the production fail-closed boundary: no reachable backend, no
    // admin identity, a blank uuid, or a server-side refusal can never
    // CONFIRM a rejection — the caller then keeps the professional as-is.
    if (!configured || !enrolled || !rejectSucceeds) return false;
    return userId.trim().isNotEmpty;
  }
}
