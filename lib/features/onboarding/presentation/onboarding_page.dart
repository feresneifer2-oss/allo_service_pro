import 'package:flutter/material.dart';

import 'onboarding_data.dart';

class OnboardingPage extends StatelessWidget {
  final OnboardingData item;

  const OnboardingPage({
    super.key,
    required this.item,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: 24,
      ),
      child: Column(
        children: [
          const Spacer(),
          Image.asset(
            item.image,
            width: 170,
          ),
          const SizedBox(height: 40),
          Text(
            item.title,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 30,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 20),
          Text(
            item.subtitle,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 18,
              color: Colors.grey,
              height: 1.5,
            ),
          ),
          const Spacer(),
        ],
      ),
    );
  }
}
