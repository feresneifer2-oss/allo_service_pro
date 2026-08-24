import 'package:flutter/material.dart';

class ProfessionalCard extends StatelessWidget {
  const ProfessionalCard({
    super.key,
    this.name = "Ahmed Ben Ali",
    this.profession = "Electricien",
    this.rating = 4.9,
    this.location = "Ariana",
    this.verified = true,
    this.buttonText = "Voir",
    this.onPressed,
  });

  final String name;
  final String profession;
  final double rating;
  final String location;
  final bool verified;
  final String buttonText;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 18),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: .05),
            blurRadius: 12,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              color: const Color(0xFFEFF6FF),
              borderRadius: BorderRadius.circular(18),
            ),
            child: const Icon(
              Icons.person_rounded,
              color: Color(0xFF2563EB),
              size: 34,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Text(
                        name,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 16.5,
                          fontWeight: FontWeight.w800,
                          height: 1.15,
                        ),
                      ),
                    ),
                    if (verified) ...const [
                      SizedBox(width: 6),
                      Padding(
                        padding: EdgeInsets.only(top: 2),
                        child: Icon(
                          Icons.verified_rounded,
                          color: Color(0xFF2563EB),
                          size: 18,
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  profession,
                  style: const TextStyle(
                    color: Color(0xFF64748B),
                    fontSize: 13.5,
                  ),
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 12,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    _InfoChip(
                      icon: Icons.star_rounded,
                      iconColor: const Color(0xFFF59E0B),
                      text: rating.toStringAsFixed(1),
                    ),
                    _InfoChip(
                      icon: Icons.location_on_rounded,
                      iconColor: const Color(0xFFEF4444),
                      text: location,
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          SizedBox(
            width: 96,
            height: 42,
            child: ElevatedButton(
              onPressed: onPressed ?? () {},
              child: Text(
                buttonText,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _InfoChip extends StatelessWidget {
  const _InfoChip({
    required this.icon,
    required this.iconColor,
    required this.text,
  });

  final IconData icon;
  final Color iconColor;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 18, color: iconColor),
        const SizedBox(width: 4),
        Text(
          text,
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: Color(0xFF1E293B),
          ),
        ),
      ],
    );
  }
}
