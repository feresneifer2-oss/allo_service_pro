import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:allo_service_pro/core/theme/app_colors.dart';
import 'package:allo_service_pro/shared/app_locale.dart';

import 'language_screen.dart';

class OtpScreen extends StatefulWidget {
  const OtpScreen({
    super.key,
    required this.phone,
  });

  final String phone;

  @override
  State<OtpScreen> createState() => _OtpScreenState();
}

class _OtpScreenState extends State<OtpScreen> {
  static const _codeLength = 6;
  static const _demoCode = '123456';

  final _controllers =
      List.generate(_codeLength, (_) => TextEditingController());
  final _focusNodes = List.generate(_codeLength, (_) => FocusNode());

  int _secondsLeft = 60;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _startTimer();
  }

  @override
  void dispose() {
    _timer?.cancel();
    for (final c in _controllers) {
      c.dispose();
    }
    for (final f in _focusNodes) {
      f.dispose();
    }
    super.dispose();
  }

  void _startTimer() {
    _timer?.cancel();
    setState(() => _secondsLeft = 60);
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (_secondsLeft <= 1) {
        t.cancel();
        setState(() => _secondsLeft = 0);
      } else {
        setState(() => _secondsLeft--);
      }
    });
  }

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

  void _verify() {
    if (_code.length != _codeLength) {
      _showError(tr(context,
          fr: 'Veuillez entrer le code complet.',
          ar: 'المرجو إدخال الرمز كاملاً.'));
      return;
    }

    if (_code != _demoCode) {
      _showError(tr(context,
          fr: 'Code incorrect. Utilisez 123456 pour cette démo locale.',
          ar: 'رمز غير صحيح. استعمل 123456 في هذا العرض التجريبي المحلي.'));
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
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 12),
              Text(
                tr(context, fr: 'Vérification', ar: 'التحقق'),
                style: const TextStyle(
                  fontSize: 34,
                  fontWeight: FontWeight.bold,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                tr(context,
                    fr: 'Entrez le code envoyé au\n${widget.phone}',
                    ar: 'أدخل الرمز المرسل إلى\n${widget.phone}'),
                style: const TextStyle(
                  fontSize: 17,
                  color: AppColors.textSecondary,
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                tr(context,
                    fr: 'Démo locale : 123456',
                    ar: 'عرض تجريبي محلي : 123456'),
                style: const TextStyle(color: AppColors.textSecondary),
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
                child: _secondsLeft > 0
                    ? Text(
                        tr(context,
                            fr: 'Renvoyer le code dans ${_secondsLeft}s',
                            ar: 'إعادة إرسال الرمز بعد $_secondsLeft ث'),
                        style: const TextStyle(color: AppColors.textSecondary),
                      )
                    : TextButton(
                        onPressed: () {
                          _startTimer();
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(tr(context,
                                  fr: 'Code renvoyé (simulation).',
                                  ar: 'تمت إعادة إرسال الرمز (محاكاة).')),
                            ),
                          );
                        },
                        child: Text(tr(context,
                            fr: 'Renvoyer le code', ar: 'إعادة إرسال الرمز')),
                      ),
              ),
              const SizedBox(height: 48),
              SizedBox(
                width: double.infinity,
                height: 56,
                child: ElevatedButton(
                  onPressed: _verify,
                  child: Text(tr(context, fr: 'Vérifier', ar: 'تحقق')),
                ),
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
