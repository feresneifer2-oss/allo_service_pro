import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:allo_service_pro/core/theme/app_colors.dart';
import 'package:allo_service_pro/features/auth/application/email_otp_service.dart';
import 'package:allo_service_pro/features/auth/application/user_store.dart';
import 'package:allo_service_pro/shared/app_locale.dart';
import 'package:allo_service_pro/shared/widgets/primary_action_button.dart';

import 'language_screen.dart';

/// Email-OTP verification screen — the second authentication factor.
///
/// A 6-digit code is issued by [EmailOtpService] and "delivered" to the
/// user's e-mail address (simulated locally in demo mode — the code is
/// surfaced in the demo banner below). Entering the correct code within
/// its validity window completes the sign-up flow.
class OtpScreen extends StatefulWidget {
  const OtpScreen({
    super.key,
    required this.email,
  });

  /// Destination e-mail address the OTP was sent to.
  final String email;

  @override
  State<OtpScreen> createState() => _OtpScreenState();
}

/// Outcome of one code-issuance attempt on the OTP screen.
///
/// The issuance lock makes "a send is already running" a first-class result
/// instead of a fake delivery failure: a concurrent request must be IGNORED,
/// never reported as "e-mail unavailable" and never allowed to burn the code
/// the user is holding.
enum _OtpIssue {
  /// A brand-new code was issued (the previous one is now invalid).
  issued,

  /// A still-valid pending code was ADOPTED untouched (nothing was sent).
  reused,

  /// Another issuance owned the lock (or the flow already completed): no-op.
  skipped,

  /// No code could be delivered in this build (release without a provider).
  unavailable,
}

class _OtpScreenState extends State<OtpScreen> {
  static const _codeLength = EmailOtpService.codeLength;

  /// Cooldown applied to "Resend OTP": the button stays disabled (and shows a
  /// live countdown) for this many seconds after a send / resend, throttling
  /// accidental spamming of the delivery channel.
  static const int _resendCooldownSeconds = 10;

  final _controllers =
      List.generate(_codeLength, (_) => TextEditingController());
  final _focusNodes = List.generate(_codeLength, (_) => FocusNode());

  int _cooldownLeft = 0;
  Timer? _cooldownTimer;
  String? _demoCode;

  /// True when the credential record could not be unlocked after a valid
  /// OTP (missing/corrupt session data). The screen then shows a secure
  /// error state and blocks any navigation past this point.
  bool _credentialUnlockFailed = false;

  /// True when no OTP could be delivered (release build: the demo channel is
  /// compiled out and no SMTP provider is wired). The screen then explains the
  /// situation instead of silently waiting for a code that never arrives.
  bool _deliveryUnavailable = false;

  /// SINGLE-FLIGHT ISSUANCE LOCK.
  ///
  /// A send is not re-entrant: two overlapping requests for the same address
  /// end with only the LAST code valid, silently invalidating the one the user
  /// may already hold (in their inbox, in the demo banner, or issued one
  /// screen earlier by a resumable registration). The lock turns any second,
  /// concurrent request into a no-op ([_OtpIssue.skipped]) instead of a code
  /// burn — and it stays correct if the delivery layer ever becomes async.
  bool _issuingOtp = false;

  /// True once a code has been verified: the flow has left this screen, so no
  /// later completion (a queued auto-submit, a stray tap) may issue or verify
  /// anything again.
  bool _completed = false;

  @override
  void initState() {
    super.initState();
    // First send + initial cooldown arm: both write state that the very first
    // build already reads, so they use the non-notifying path (calling
    // setState during the element's initial build is needless churn).
    //
    // The first send is NOT forced: a still-valid code for this address (a
    // resumed registration, a re-mounted screen after a hot reload, a
    // duplicated navigation) is ADOPTED as-is. Forcing it here is exactly the
    // bug that made a freshly delivered code unusable one frame later.
    _issueCode(notify: false);
    _startCooldown(notify: false);
  }

  @override
  void dispose() {
    // Cancelled on unmount so no periodic callback can outlive the screen
    // (a ticking timer holding `setState` would leak the State object).
    _cooldownTimer?.cancel();
    _cooldownTimer = null;
    for (final c in _controllers) {
      c.dispose();
    }
    for (final f in _focusNodes) {
      f.dispose();
    }
    super.dispose();
  }

  /// Issues (or adopts) the code for [widget.email].
  ///
  /// [force] is the explicit "resend" semantic: a fresh code is issued and the
  /// previous one is burned. WITHOUT it, a still-valid pending code is REUSED
  /// untouched — which is what makes the resumable registration flow safe,
  /// since re-issuing there invalidates the very code the user holds.
  ///
  /// Guarded by [_issuingOtp] (single-flight) and [_completed]: a concurrent or
  /// post-completion call returns [_OtpIssue.skipped] and changes nothing.
  ///
  /// Delivery goes through the sanitized entry point: in release the service
  /// refuses (no channel) and the screen flips to the unavailable state
  /// instead of throwing.
  _OtpIssue _issueCode({bool notify = true, bool force = false}) {
    if (_issuingOtp || _completed) return _OtpIssue.skipped;
    _issuingOtp = true;
    try {
      final bool adopted =
          !force && EmailOtpService.hasPendingOtp(widget.email);
      final bool ok = adopted || EmailOtpService.trySendOtp(widget.email);

      if (mounted) {
        void apply() {
          _deliveryUnavailable = !ok;
          // Per-address lookup: when a code is ADOPTED it is the one to show,
          // and it is not necessarily the last code issued process-wide.
          _demoCode = ok && EmailOtpService.demoMode
              ? EmailOtpService.demoCodeFor(widget.email)
              : null;
        }

        if (notify) {
          setState(apply);
        } else {
          apply();
        }
      }

      if (!ok) return _OtpIssue.unavailable;
      return adopted ? _OtpIssue.reused : _OtpIssue.issued;
    } finally {
      _issuingOtp = false;
    }
  }

  /// Starts (or restarts) the resend cooldown. A single `Timer.periodic`
  /// decrements the counter every second; when it reaches 0 the button is
  /// re-enabled and the timer cancels itself.
  void _startCooldown({bool notify = true}) {
    _cooldownTimer?.cancel();
    if (notify) {
      setState(() => _cooldownLeft = _resendCooldownSeconds);
    } else {
      _cooldownLeft = _resendCooldownSeconds;
    }
    _cooldownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      if (_cooldownLeft <= 1) {
        timer.cancel();
        setState(() => _cooldownLeft = 0);
      } else {
        setState(() => _cooldownLeft--);
      }
    });
  }

  /// True while the resend action must stay disabled.
  bool get _resendBlocked => _cooldownLeft > 0;

  String get _code => _controllers.map((c) => c.text).join();

  void _onDigitChanged(int index, String value) {
    if (value.length > 1) {
      _controllers[index].text = value.substring(value.length - 1);
    }
    if (value.isNotEmpty && index < _codeLength - 1) {
      _focusNodes[index + 1].requestFocus();
    }
    if (_code.length == _codeLength) {
      _verify();
    }
  }

  /// Wipes the code boxes and sends the caret back to the first one.
  ///
  /// Called after every FAILED verification so the next attempt always starts
  /// from a clean slate. Without this, the boxes would stay filled: typing the
  /// next code would make the joined value hit [codeLength] on every keystroke,
  /// firing a premature auto-submit each time and burning the service's attempt
  /// budget with partial codes before the real code could even be completed.
  void _clearCode() {
    for (final c in _controllers) {
      c.clear();
    }
    if (_focusNodes.isNotEmpty) _focusNodes.first.requestFocus();
  }

  void _resend() {
    // Guarded here as well as in the UI: a disabled button is not a
    // security boundary, the handler must refuse on its own.
    if (_resendBlocked) return;

    // Explicit resend = FORCE a fresh code (the previous one is burned).
    final outcome = _issueCode(force: true);
    // A concurrent issuance already owns the channel: this tap is a no-op, so
    // it must not claim a delivery failure nor restart the cooldown.
    if (outcome == _OtpIssue.skipped) return;
    final ok = outcome != _OtpIssue.unavailable;
    // Cooldown restarts on every SUCCESSFUL resend.
    if (ok) _startCooldown();

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          ok
              ? tr(context,
                  fr: 'Un nouveau code a été envoyé à votre e-mail.',
                  ar: 'تم إرسال رمز جديد إلى بريدك الإلكتروني.')
              : tr(context,
                  fr: "Envoi indisponible : aucun service d'e-mail n'est configuré.",
                  ar: 'الإرسال غير متاح: لم يتم إعداد خدمة البريد الإلكتروني.'),
        ),
      ),
    );
  }

  void _verify() {
    // The flow already succeeded and is navigating away: a late auto-submit or
    // a stray tap must not consume a (now absent) token or fire an error
    // snackbar on a screen that is being replaced.
    if (_completed) return;
    // Nothing can be verified on an element that is already gone.
    if (!mounted) return;

    if (_code.length != _codeLength) {
      _showError(tr(context,
          fr: 'Veuillez entrer le code complet.',
          ar: 'المرجو إدخال الرمز كاملاً.'));
      return;
    }

    final ok = EmailOtpService.verifyOtp(widget.email, _code);
    if (!ok) {
      // Start the next attempt from empty boxes (see [_clearCode]): also the
      // reason a stale full code can never auto-submit itself again.
      _clearCode();
      _showError(tr(context,
          fr: 'Code incorrect ou expiré. Demandez un nouveau code si besoin.',
          ar: 'الرمز غير صحيح أو منتهي. اطلب رمزاً جديداً عند الحاجة.'));
      return;
    }
    // The token is now VALIDATED and CONSUMED: only at this point may the
    // credential record be unlocked (releasing the isVerified lock).
    //
    // Mark the flow COMPLETE before any unlock attempt: from here on no
    // further issuance/verification may run (the lock also survives the
    // credential-unlock failure branch below, where navigation is blocked).
    _completed = true;
    // If the unlock FAILS while the record EXISTS (corrupted storage,
    // session wiped mid-flow): STOP. No navigation - show the secure
    // error state and block the user from advancing.
    // A MISSING record is not an unlock failure: the security gate (the
    // OTP token) already succeeded, and fresh registration flows create
    // the account after this handshake - navigation may proceed.
    final unlocked = UserStore.markEmailVerified(email: widget.email);
    final recordExists = UserStore.hasCredentialRecord(email: widget.email);
    if (!unlocked && recordExists) {
      _credentialUnlockFailed = true;
      if (mounted) setState(() {});
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(tr(context,
                fr: 'Session error. Please restart registration.',
                ar: 'حدث خطأ في الجلسة. الرجاء إعادة التسجيل من فضلك.')),
          ),
        );
      }
      return;
    }
    FocusScope.of(context).unfocus();
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (_) => const LanguageScreen()),
    );
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      resizeToAvoidBottomInset: true,
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 12),
              // Secure error state: the OTP was valid but the credential
              // record could not be unlocked. The user is blocked here —
              // no navigation past this point is possible.
              if (_credentialUnlockFailed)
                Container(
                  width: double.infinity,
                  margin: const EdgeInsets.only(bottom: 12),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFDECEA),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppColors.error),
                  ),
                  child: Text(
                    tr(context,
                        fr: 'Session error. Please restart registration.',
                        ar: 'حدث خطأ في الجلسة. الرجاء إعادة التسجيل من فضلك.'),
                    style: const TextStyle(color: AppColors.error),
                  ),
                ),
              Text(
                tr(context, fr: 'Vérifiez votre e-mail', ar: 'تحقق من بريدك الإلكتروني'),
                style: const TextStyle(
                  fontSize: 30,
                  fontWeight: FontWeight.bold,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                tr(context,
                    fr: 'Entrez le code à 6 chiffres envoyé à\n${widget.email}',
                    ar: 'أدخل الرمز المكوّن من 6 أرقام المرسل إلى\n${widget.email}'),
                style: const TextStyle(
                  fontSize: 16,
                  color: AppColors.textSecondary,
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 8),
              // Delivery unavailable (release builds only): the demo channel is
              // compiled out and no SMTP provider is wired, so no code can be
              // issued. Disclosed explicitly rather than leaving the user
              // waiting for an e-mail that will never arrive.
              if (_deliveryUnavailable)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppColors.background,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppColors.error, width: 1),
                  ),
                  child: Text(
                    tr(context,
                        fr: "Aucun service d'envoi d'e-mail n'est configuré : la vérification est indisponible pour le moment.",
                        ar: 'لا توجد خدمة إرسال بريد إلكتروني مُهيّأة: التحقق غير متاح حالياً.'),
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: AppColors.error,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              // Demo delivery banner: the app is fully local (no SMTP), so
              // the issued code is shown here instead of landing in an
              // inbox. Hidden automatically when a real provider is wired.
              if (EmailOtpService.demoMode && _demoCode != null)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppColors.background,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppColors.primary, width: 1),
                  ),
                  child: Text(
                    tr(context,
                        fr: 'Mode démo — votre code : $_demoCode',
                        ar: 'الوضع التجريبي — رمزك: $_demoCode'),
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: AppColors.textPrimary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              const SizedBox(height: 40),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: List.generate(
                    _codeLength,
                    (i) => _OtpBox(
                          controller: _controllers[i],
                          focusNode: _focusNodes[i],
                          onChanged: (v) => _onDigitChanged(i, v),
                          onBackspace: () {
                            if (_controllers[i].text.isEmpty && i > 0) {
                              _focusNodes[i - 1].requestFocus();
                            }
                          },
                        )),
              ),
              const SizedBox(height: 28),
              Center(
                child: _resendBlocked
                    // Cooldown active: the action is DISABLED and the live
                    // countdown doubles as the indicator (no hidden tap target,
                    // no double-send within the window).
                    ? Text(
                        tr(context,
                            fr: 'Renvoyer le code dans ${_cooldownLeft}s',
                            ar: 'إعادة إرسال الرمز بعد $_cooldownLeft ث'),
                        style: const TextStyle(color: AppColors.textSecondary),
                      )
                    : TextButton(
                        onPressed: _resend,
                        child: Text(tr(context,
                            fr: 'Renvoyer le code', ar: 'إعادة إرسال الرمز')),
                      ),
              ),
              const SizedBox(height: 48),
              PrimaryActionButton(
                label: tr(context, fr: 'Vérifier', ar: 'تحقق'),
                onPressed: _verify,
                height: 56,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _OtpBox extends StatelessWidget {
  const _OtpBox({
    required this.controller,
    required this.focusNode,
    required this.onChanged,
    required this.onBackspace,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final ValueChanged<String> onChanged;
  final VoidCallback onBackspace;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 48,
      height: 56,
      child: TextField(
        controller: controller,
        focusNode: focusNode,
        textAlign: TextAlign.center,
        keyboardType: TextInputType.number,
        maxLength: 1,
        style: const TextStyle(
          fontSize: 22,
          fontWeight: FontWeight.w700,
          color: AppColors.textPrimary,
        ),
        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
        decoration: InputDecoration(
          counterText: '',
          filled: true,
          fillColor: AppColors.background,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide(color: Colors.grey.shade300),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide(color: Colors.grey.shade300),
          ),
          focusedBorder: const OutlineInputBorder(
            borderRadius: BorderRadius.all(Radius.circular(14)),
            borderSide: BorderSide(color: AppColors.primary, width: 1.5),
          ),
        ),
        onChanged: onChanged,
        onTapOutside: (_) => FocusScope.of(context).unfocus(),
        onSubmitted: (_) {},
      ),
    );
  }
}
