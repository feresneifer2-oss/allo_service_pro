import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';

import 'package:url_launcher/url_launcher.dart';

import 'package:allo_service_pro/core/constants/app_constants.dart';
import 'package:allo_service_pro/core/services/document_media_service.dart';
import 'package:allo_service_pro/core/services/supabase_storage_service.dart';
import 'package:allo_service_pro/core/theme/app_colors.dart';
import 'package:allo_service_pro/features/admin/application/admin_store.dart';
import 'package:allo_service_pro/features/auth/application/user_store.dart';
import 'package:allo_service_pro/features/auth/presentation/welcome_screen.dart';
import 'package:allo_service_pro/features/pro_dashboard/application/pro_profile_store.dart';
import 'package:allo_service_pro/shared/app_locale.dart';

/// Full-screen gate blocking unverified professionals.
///
/// - pending : review in progress + WhatsApp inquiry pre-filled with
///             Name · Profession · PRO-XXXXX.
/// - rejected: shows the admin reason with a "Re-upload proof" action that
///             sends the account back to review without re-registering.
class VerificationGateScreen extends StatefulWidget {
  const VerificationGateScreen({super.key});

  @override
  State<VerificationGateScreen> createState() => _VerificationGateScreenState();
}

class _VerificationGateScreenState extends State<VerificationGateScreen> {
  Future<void> _openWhatsApp(UserModel user) async {
    final msg = AdminStore.whatsappMessage(
      name: user.name,
      profession: ProProfileStore.professionFr ?? '-',
      proCode: user.proCode ?? '-',
    );
    final uri = Uri.parse('https://wa.me/${AppConstants.adminWhatsAppNumber}'
        '?text=${Uri.encodeComponent(msg)}');
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(tr(context,
              fr: "Impossible d'ouvrir WhatsApp.", ar: 'تعذّر فتح واتساب.')),
          backgroundColor: AppColors.error,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<UserModel?>(
      valueListenable: UserStore.user,
      builder: (context, user, _) {
        final u = user;
        if (u == null) {
          return const Scaffold(
              body: Center(child: CircularProgressIndicator()));
        }

        final rejected = u.verificationStatus.isRejected;

        return Scaffold(
          backgroundColor: AppColors.background,
          appBar: AppBar(
            title: Text(tr(context,
                fr: 'Vérification du compte', ar: 'التحقق من الحساب')),
          ),
          body: SafeArea(
            child: SingleChildScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SizedBox(height: 8),
                  Icon(
                    rejected
                        ? Icons.cancel_rounded
                        : Icons.hourglass_top_rounded,
                    size: 72,
                    color: rejected ? AppColors.error : AppColors.warning,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    rejected
                        ? tr(context, fr: 'Compte refusé', ar: 'تم رفض الحساب')
                        : tr(context,
                            fr: 'En attente de vérification',
                            ar: 'في انتظار التحقق'),
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                        fontSize: 22, fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 8),
                  if ((u.proCode ?? '').isNotEmpty)
                    Center(
                      child: Chip(
                        label: Text(u.proCode!),
                        backgroundColor: AppColors.primarySurface,
                        labelStyle: const TextStyle(
                            color: AppColors.primary,
                            fontWeight: FontWeight.w700),
                      ),
                    ),
                  const SizedBox(height: 16),
                  if (rejected && (u.rejectionReason ?? '').isNotEmpty) ...[
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: AppColors.error.withValues(alpha: .08),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                            color: AppColors.error.withValues(alpha: .35)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                              tr(context,
                                  fr: 'Motif du refus :', ar: 'سبب الرفض:'),
                              style:
                                  const TextStyle(fontWeight: FontWeight.w700)),
                          const SizedBox(height: 4),
                          Text(u.rejectionReason!),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],
                  Text(
                    rejected
                        ? tr(context,
                            fr:
                                'Corrigez le problème puis renvoyez votre preuve.',
                            ar: 'صحّح المشكلة ثم أعد رفع الإثبات.')
                        : tr(context,
                            fr: 'Votre compte est en cours de vérification par l\'administration.',
                            ar: 'حسابك قيد المراجعة من قبل الإدارة.'),
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: AppColors.textSecondary),
                  ),
                  const SizedBox(height: 24),

                  // ── Re-upload proof (rejected flow) ──
                  if (rejected)
                    ElevatedButton.icon(
                      // REAL re-capture (image_picker): the old flow pushed
                      // the bundled placeholder as "the proof", so a rejected
                      // professional could "fix" a refusal without ever
                      // photographing a new document — and the admin would
                      // review the same placeholder again.
                      onPressed: () async {
                        final messenger = ScaffoldMessenger.of(context);
                        final errorText = tr(
                          context,
                          fr: "Aucune photo n'a été prise. Veuillez "
                              "réessayer ou autoriser l'accès à la "
                              "caméra.",
                          ar: "لم يتم التقاط أي صورة. يرجى المحاولة "
                              "مرة أخرى أو منح إذن الوصول للكاميرا.",
                        );
                        // Captured BEFORE the async pick so the post-await
                        // SnackBar never touches `context` (avoids
                        // use_build_context_synchronously).
                        final mismatchText = tr(
                          context,
                          fr: 'Aucune demande en cours ne correspond '
                              'à votre identifiant PRO.',
                          // Polished Arabic (CodeRabbit): the previous wording
                          // ("لا توجد طلبة…") misused the plural of « طالب »
                          // (students) and read ambiguously. This version uses
                          // the correct term for a verification request
                          // (« طلب تحقّق ») and closes with an actionable,
                          // professional next step.
                          ar: 'لا يوجد أي طلب تحقّق قيد المراجعة مرتبط '
                              'بمعرّفك المهني. يُرجى التواصل مع الإدارة '
                              'لمتابعة حالة حسابك.',
                        );

                        final path = await DocumentMediaService.pickDocument(
                          fromCamera: true, // the fast path: photograph it
                        );
                        if (path == null) {
                          // Camera capture failed or the user denied the
                          // permission — give immediate, actionable feedback
                          // instead of a silent no-op.
                          if (!mounted) return;
                          messenger.showSnackBar(
                            SnackBar(
                              content: Text(errorText),
                              backgroundColor: AppColors.error,
                            ),
                          );
                          return;
                        }
                        if (!mounted) {
                          // ORPHAN CLEANUP (CodeRabbit): the screen went away
                          // before the capture could be bound to anything, so
                          // the freshly copied file is deleted right away
                          // instead of lingering unreferenced in `pro_media`.
                          await DocumentMediaService.discard(path);
                          return;
                        }
                        // STRICT RESUBMISSION GATE (CodeRabbit): the local
                        // session is re-queued ONLY when the admin registry
                        // actually ACCEPTED the new proof. Every other outcome
                        // halts this callback with an explicit `return;`
                        // immediately after its snackbar, so the account can
                        // never be un-rejected locally while the admin dossier
                        // still carries the old refusal (a silent desync
                        // between the two sides).
                        //
                        // STRICT IDENTIFIER GUARD (CodeRabbit): the lookup
                        // below is NEVER attempted with a null/blank/whitespace
                        // PRO code — a code match on two absent codes is
                        // `null == null`,
                        // which would select an admin-seeded dossier that also
                        // carries none and re-queue the WRONG entry. At least
                        // one VALID, non-empty identifier (PRO code, or the
                        // legacy account id) is strictly required; a session
                        // with neither owns no dossier and is refused here.
                        final proCode = (u.proCode ?? '').trim();
                        final accountId = u.id.trim();
                        if (proCode.isEmpty && accountId.isEmpty) {
                          debugPrint(
                              'VerificationGate: blank PRO code and blank '
                              'account id — dossier lookup refused.');
                          // ORPHAN CLEANUP (CodeRabbit): nothing can ever bind
                          // this capture, so it is deleted immediately.
                          await DocumentMediaService.discard(path);
                          if (!mounted) return;
                          messenger.showSnackBar(
                            SnackBar(content: Text(mismatchText)),
                          );
                          return;
                        }
                        // The dossier is resolved by a NON-EMPTY PRO code or a
                        // NON-EMPTY account id ([AdminStore.entryForUser]
                        // enforces exactly that guard internally too).
                        final entry = AdminStore.entryForUser(u);
                        if (entry == null) {
                          // MISMATCH HANDLER (CodeRabbit): the signing-in pro
                          // has NO dossier in the admin registry (the entry
                          // was removed, or the code drifted). Failing
                          // silently here would leave the admin side desynced
                          // from the user-side resubmission, so it is
                          // reported in debug AND surfaced to the user.
                          debugPrint(
                              'VerificationGate: no pending entry found for '
                              'proCode "${u.proCode}" / id "${u.id}" — '
                              'resubmitProof skipped.');
                          // ORPHAN CLEANUP (CodeRabbit): this capture can never
                          // be bound to a dossier (the registry has no matching
                          // entry), so the file is deleted NOW — a refused
                          // resubmission must not leave an unreferenced image
                          // behind in `pro_media`.
                          await DocumentMediaService.discard(path);
                          if (!mounted) return;
                          messenger.showSnackBar(
                            SnackBar(
                              content: Text(mismatchText),
                            ),
                          );
                          // HALT IMMEDIATELY (CodeRabbit): the explicit return
                          // right after the mismatch snackbar guarantees that
                          // `updateProVerification` below is NEVER reached
                          // with a registry that changed nothing — the local
                          // account can therefore never be un-rejected while
                          // the admin still shows the refusal.
                          return;
                        }
                        // GUARDED UPDATE (CodeRabbit): the local session is
                        // rebound ONLY when the repository actually accepted
                        // the re-submission. A `false` (store refusal) means
                        // the registry changed NOTHING, so mutating the
                        // account now would desync it — surface the retry
                        // prompt and skip `updateProVerification`.
                        final accepted = await AdminStore.resubmitProof(
                          entry.id,
                          proofPath: path,
                        );
                        if (!accepted) {
                          debugPrint(
                              'VerificationGate: resubmitProof refused — local update skipped.');
                          // ORPHAN CLEANUP (CodeRabbit): the store ACCEPTED
                          // nothing, so this capture is unbound — delete it and
                          // keep `pro_media` free of orphaned proofs.
                          await DocumentMediaService.discard(path);
                          if (!mounted) return;
                          messenger.showSnackBar(
                            SnackBar(content: Text(mismatchText)),
                          );
                          // HALT IMMEDIATELY: same guard as above — a refused
                          // re-submission must not touch the local account.
                          return;
                        }
                        // SUPABASE STORAGE MIRROR: the registry ACCEPTED the
                        // new proof, so the durable backend copy is pushed to
                        // the PRIVATE `documents` bucket (`<uid>/proof_<ts>`).
                        //
                        // BLANK-ID GUARD (CodeRabbit): the earlier gate only
                        // requires ONE of (proCode, accountId) to be non-empty
                        // — `accountId` alone may still be blank, and an empty
                        // folder prefix would land the file at the BUCKET ROOT
                        // (`/proof_<ts>`), an unowned shared path any user can
                        // collide with. The upload key therefore prefers the
                        // PRO code and falls back to the account id; the
                        // bucket-key is never blank.
                        final storageUid =
                            proCode.isNotEmpty ? proCode : accountId;
                        // LOCAL PENDING-STATE RESTORE (CodeRabbit): the
                        // registry ACCEPTED the re-submission — the local
                        // session is re-queued EXPLICITLY and AWAITED so the
                        // gate's ValueListenableBuilder re-renders to the
                        // pending view immediately (no re-login, no stale
                        // rejection banner) even if the registry→session
                        // bridge missed this identity.
                        await UserStore.updateProVerification(
                          status: ProVerification.pending,
                          proofPath: path,
                          clearReason: true,
                        );
                        // DURABLE PROOF HANDLE (CodeRabbit): the upload is
                        // AWAITED (no longer fire-and-forget) and the returned
                        // remote path is PERSISTED INTO THE DOSSIER — the
                        // admin on any device resolves the backend copy, not
                        // a device-local artifact. A failed upload keeps the
                        // local path operative (graceful fallback).
                        try {
                          final remotePath =
                              await SupabaseStorageService.uploadDocument(
                            storageUid,
                            File(path),
                            kind: 'proof',
                          );
                          if (remotePath != null && remotePath.isNotEmpty) {
                            await AdminStore.attachProofRemotePath(
                              entry.id,
                              remotePath: remotePath,
                            );
                            // The session's proof pointer follows the
                            // durable copy too.
                            await UserStore.updateProVerification(
                              status: ProVerification.pending,
                              proofPath: remotePath,
                              clearReason: true,
                            );
                          }
                        } catch (e) {
                          debugPrint('VerificationGate: proof upload failed — '
                              'local path remains operative: $e');
                        }
                      },
                      icon: const Icon(Icons.upload_file_rounded),
                      label: Text(tr(context,
                          fr: 'Re-téléverser la preuve',
                          ar: 'إعادة رفع الإثبات')),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                    ),

                  const SizedBox(height: 12),

                  // ── WhatsApp inquiry (pre-filled) ──
                  OutlinedButton.icon(
                    onPressed: () => _openWhatsApp(u),
                    icon: const Icon(Icons.chat_rounded),
                    label: Text(tr(context,
                        fr: 'Contacter via WhatsApp',
                        ar: 'التواصل عبر واتساب')),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.success,
                      side: BorderSide(
                          color: AppColors.success.withValues(alpha: .4)),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                  ),
                  const SizedBox(height: 24),
                  TextButton(
                    onPressed: () async {
                      final messenger = ScaffoldMessenger.of(context);
                      // Capture the navigator BEFORE the async gap — the
                      // gate lives INSIDE ProShell (no route to pop), so
                      // the old popUntil was a silent no-op freeze.
                      // Wipe the whole session (SharedPreferences keys +
                      // local stores) and jump to Welcome with an empty
                      // navigation stack — 100% reliable.
                      // GUARDED NAVIGATION (CodeRabbit): a `false` means the
                      // persisted cleanup FAILED — the session stays ALIVE
                      // and nothing was reset, so navigating to Welcome
                      // would strand the user on a logged-out screen with a
                      // live session. Show a retry prompt instead.
                      final navigator = Navigator.of(context);
                      final signedOut = await UserStore.signOutAndReset();
                      if (!context.mounted) return;
                      if (!signedOut) {
                        messenger.showSnackBar(
                          SnackBar(
                            content: Text(tr(context,
                                fr: 'Déconnexion impossible pour le moment — réessayez.',
                                ar: 'تعذّر تسجيل الخروج حالياً — حاول مجدداً.')),
                            backgroundColor: AppColors.error,
                          ),
                        );
                        return;
                      }
                      navigator.pushAndRemoveUntil(
                        MaterialPageRoute(
                            builder: (_) => const WelcomeScreen()),
                        (route) => false,
                      );
                    },
                    child: Text(tr(context,
                        fr: "Retour à l'accueil", ar: 'العودة للرئيسية')),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
