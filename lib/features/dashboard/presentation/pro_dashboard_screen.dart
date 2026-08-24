import 'package:flutter/material.dart';

class ProDashboardScreen extends StatelessWidget {
  const ProDashboardScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        title: const Text("Dashboard"),
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          const Text(
            "Overview",
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w800,
              color: Color(0xFF1E293B),
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: const [
              Expanded(
                child: _StatCard(
                  title: "Requests",
                  value: "3",
                  color: Color(0xFF2563EB),
                  icon: Icons.inbox_rounded,
                ),
              ),
              SizedBox(width: 12),
              Expanded(
                child: _StatCard(
                  title: "Rating",
                  value: "4.8",
                  color: Color(0xFFF59E0B),
                  icon: Icons.star_rounded,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          const _StatCard(
            title: "Earnings (month)",
            value: "0 TND",
            color: Color(0xFF22C55E),
            icon: Icons.payments_rounded,
            fullWidth: true,
          ),
          const SizedBox(height: 24),
          const Text(
            "Latest requests",
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w800,
              color: Color(0xFF1E293B),
            ),
          ),
          const SizedBox(height: 12),
          const _RequestTile(title: "Electricity - Ariana", subtitle: "2 hours ago"),
          const _RequestTile(title: "Plumbing - Tunis", subtitle: "Today 10:30"),
          const _RequestTile(title: "Cleaning - La Marsa", subtitle: "Yesterday"),
        ],
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard({
    required this.title,
    required this.value,
    required this.color,
    required this.icon,
    this.fullWidth = false,
  });

  final String title;
  final String value;
  final Color color;
  final IconData icon;
  final bool fullWidth;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(.05),
            blurRadius: 12,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: color.withOpacity(.12),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(icon, color: color),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(color: Color(0xFF64748B))),
                const SizedBox(height: 4),
                Text(
                  value,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF1E293B),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _RequestTile extends StatelessWidget {
  const _RequestTile({required this.title, required this.subtitle});

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(
        children: [
          const Icon(Icons.bolt_rounded, color: Color(0xFF2563EB)),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
                const SizedBox(height: 4),
                Text(subtitle, style: const TextStyle(color: Color(0xFF64748B))),
              ],
            ),
          ),
          const Icon(Icons.chevron_right_rounded, color: Color(0xFF64748B)),
        ],
      ),
    );
  }
}