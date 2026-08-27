import 'package:flutter/material.dart';

import 'package:allo_service_pro/core/models/request_status.dart';
import 'package:allo_service_pro/core/theme/app_colors.dart';
import 'package:allo_service_pro/features/chat/application/chat_store.dart';
import 'package:allo_service_pro/features/chat/presentation/chat_screen.dart';
import 'package:allo_service_pro/features/pro_dashboard/application/pro_profile_store.dart';
import 'package:allo_service_pro/features/pro_dashboard/application/subscription_store.dart';
import 'package:allo_service_pro/features/pro_dashboard/presentation/service_zones_screen.dart';
import 'package:allo_service_pro/features/requests/application/request_store.dart';
import 'package:allo_service_pro/features/requests/models/service_request.dart';
import 'package:allo_service_pro/shared/app_locale.dart';
import 'package:allo_service_pro/shared/widgets/status_badge.dart';

class ProDashboardScreen extends StatelessWidget {
  const ProDashboardScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.slate900,
      body: SafeArea(
        child: ValueListenableBuilder(
          valueListenable: RequestStore.requests,
          builder: (context, all, _) {
            final pending =
                all.where((r) => r.status == RequestStatus.pending).length;
            final accepted =
                all.where((r) => r.status == RequestStatus.accepted).length;

            return ValueListenableBuilder<bool>(
              valueListenable: ProProfileStore.isAvailable,
              builder: (context, available, _) {
                return SingleChildScrollView(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  tr(context,
                                      fr: 'Bonjour Ahmed 👋',
                                      ar: 'مرحبا Ahmed 👋'),
                                  style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 26,
                                      fontWeight: FontWeight.w800),
                                ),
                                const SizedBox(height: 4),
                                Row(
                                  children: [
                                    Container(
                                      width: 10,
                                      height: 10,
                                      decoration: BoxDecoration(
                                        color: available
                                            ? AppColors.success
                                            : AppColors.error,
                                        shape: BoxShape.circle,
                                      ),
                                    ),
                                    const SizedBox(width: 6),
                                    Text(
                                      available
                                          ? tr(context,
                                              fr: 'Disponible', ar: 'متاح')
                                          : tr(context,
                                              fr: 'Indisponible',
                                              ar: 'غير متاح'),
                                      style: TextStyle(
                                        color: available
                                            ? AppColors.success
                                            : AppColors.error,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                          Switch(
                            value: available,
                            activeThumbColor: AppColors.success,
                            onChanged: (v) =>
                                ProProfileStore.isAvailable.value = v,
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      OutlinedButton.icon(
                        onPressed: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => const ServiceZonesScreen(),
                            ),
                          );
                        },
                        icon: const Icon(Icons.location_city_rounded, size: 18),
                        label: Text(
                          tr(context,
                              fr: 'Zones de service', ar: 'مناطق الخدمة'),
                          style: const TextStyle(fontSize: 13),
                        ),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppColors.secondary,
                          side: const BorderSide(color: AppColors.secondary),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 8,
                          ),
                        ),
                      ),
                      const SizedBox(height: 24),
                      Row(
                        children: [
                          Expanded(
                            child: _StatCard(
                              label: tr(context,
                                  fr: 'Nouvelles demandes', ar: 'طلبات جديدة'),
                              value: '$pending',
                              color: AppColors.secondary,
                              icon: Icons.inbox_rounded,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: _StatCard(
                              label: tr(context, fr: 'Acceptées', ar: 'مقبولة'),
                              value: '$accepted',
                              color: AppColors.primary,
                              icon: Icons.check_circle_outline_rounded,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      ValueListenableBuilder<int>(
                        valueListenable: ProProfileStore.tokens,
                        builder: (context, tokenCount, _) {
                          return ValueListenableBuilder<bool>(
                            valueListenable:
                                SubscriptionStore.isPaidSubscriber,
                            builder: (_, isPaid, __) => _StatCard(
                              label: tr(context, fr: 'Tokens', ar: 'توكن'),
                              value: isPaid ? '∞' : '$tokenCount',
                              color: AppColors.success,
                              icon: Icons.diamond_rounded,
                            ),
                          );
                        },
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: ValueListenableBuilder<int>(
                              valueListenable:
                                  ProProfileStore.completedServices,
                              builder: (_, v, __) => _StatCard(
                                label: tr(context,
                                    fr: 'Services terminés',
                                    ar: 'خدمات مكتملة'),
                                value: '$v',
                                color: AppColors.success,
                                icon: Icons.done_all_rounded,
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: ValueListenableBuilder<double>(
                              valueListenable: ProProfileStore.rating,
                              builder: (_, v, __) => _StatCard(
                                label: tr(context, fr: 'Note', ar: 'التقييم'),
                                value: v.toStringAsFixed(1),
                                color: AppColors.secondary,
                                icon: Icons.star_rounded,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 24),
                      ValueListenableBuilder<bool>(
                        valueListenable: SubscriptionStore.isPaidSubscriber,
                        builder: (_, isPaid, ____) =>
                            ValueListenableBuilder<int>(
                          valueListenable: ProProfileStore.tokens,
                          builder: (_, tokens, ___) {
                            return Container(
                              width: double.infinity,
                              padding: const EdgeInsets.all(20),
                              decoration: BoxDecoration(
                                gradient: AppColors.accentGradient,
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: Row(
                                children: [
                                  Icon(
                                    isPaid
                                        ? Icons.all_inclusive_rounded
                                        : Icons.monetization_on_rounded,
                                    color: Colors.white,
                                    size: 36,
                                  ),
                                  const SizedBox(width: 16),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          tr(context,
                                              fr: 'Tokens', ar: 'توكن'),
                                          style: const TextStyle(
                                              color: Colors.white70),
                                        ),
                                        Text(
                                          isPaid
                                              ? tr(context,
                                                  fr: 'Illimité',
                                                  ar: 'غير محدود')
                                              : '$tokens Tokens',
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(
                                            color: Colors.white,
                                            fontSize: 24,
                                            fontWeight: FontWeight.w800,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                );
              },
            );
          },
        ),
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard({
    required this.label,
    required this.value,
    required this.color,
    required this.icon,
  });

  final String label;
  final String value;
  final Color color;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.slate800,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: .04),
              blurRadius: 10,
              offset: const Offset(0, 4)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color),
          const SizedBox(height: 8),
          Text(value,
              style: TextStyle(
                  fontSize: 28, fontWeight: FontWeight.w800, color: color)),
          Text(label,
              style: const TextStyle(color: AppColors.slate400, fontSize: 12)),
        ],
      ),
    );
  }
}

class ProRequestsScreen extends StatelessWidget {
  const ProRequestsScreen({super.key});

  static const _statusFlow = [
    RequestStatus.accepted,
    RequestStatus.enRoute,
    RequestStatus.arrived,
    RequestStatus.inProgress,
    RequestStatus.completed,
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.slate900,
      appBar: AppBar(
        backgroundColor: AppColors.slate800,
        title: Text(tr(context, fr: 'Demandes', ar: 'الطلبات'),
            style: const TextStyle(color: Colors.white)),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: ValueListenableBuilder<List<ServiceRequest>>(
        valueListenable: RequestStore.requests,
        builder: (context, all, _) {
          if (all.isEmpty) {
            return Center(
              child: Text(
                tr(context, fr: 'Aucune demande', ar: 'لا طلبات'),
                style: const TextStyle(color: AppColors.slate400),
              ),
            );
          }

          return ListView.builder(
            padding: const EdgeInsets.all(20),
            itemCount: all.length,
            itemBuilder: (_, i) {
              final r = all[i];
              final service =
                  tr(context, fr: r.serviceTitleFr, ar: r.serviceTitleAr);

              return Container(
                margin: const EdgeInsets.only(bottom: 16),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppColors.slate800,
                  borderRadius: BorderRadius.circular(18),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(service,
                              style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w800,
                                  fontSize: 17)),
                        ),
                        StatusBadge(status: r.status),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text('📍 ${r.address}',
                        style: const TextStyle(color: AppColors.slate400)),
                    Text(
                      '📅 ${r.dateTime.day}/${r.dateTime.month} 🕐 ${r.dateTime.hour}:${r.dateTime.minute.toString().padLeft(2, '0')}',
                      style: const TextStyle(color: AppColors.slate400),
                    ),
                    if (r.message.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Text(r.message,
                          style: const TextStyle(
                              color: AppColors.slate400,
                              fontStyle: FontStyle.italic)),
                    ],
                    const SizedBox(height: 12),
                    if (r.status == RequestStatus.pending)
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton(
                              onPressed: () => RequestStore.updateStatus(
                                  r.id, RequestStatus.refused),
                              style: OutlinedButton.styleFrom(
                                  foregroundColor: AppColors.error),
                              child:
                                  Text(tr(context, fr: 'Refuser', ar: 'رفض')),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: ElevatedButton(
                              onPressed: () {
                                // Paid subscribers confirm freely; trial
                                // accounts need at least 10 tokens.
                                final canConfirm =
                                    SubscriptionStore.isPaidSubscriber.value ||
                                        ProProfileStore.tokens.value >= 10;
                                if (canConfirm) {
                                  RequestStore.updateStatus(
                                      r.id, RequestStatus.accepted);
                                } else {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text(tr(context,
                                          fr: 'Tokens insuffisants (10 requis)',
                                          ar: 'رصيد التوكن غير كافٍ (10 مطلوب)')),
                                      backgroundColor: AppColors.error,
                                    ),
                                  );
                                }
                              },
                              child:
                                  Text(tr(context, fr: 'Accepter', ar: 'قبول')),
                            ),
                          ),
                        ],
                      ),
                    if (r.status != RequestStatus.pending &&
                        r.status != RequestStatus.refused &&
                        r.status != RequestStatus.cancelled &&
                        r.status != RequestStatus.completed) ...[
                      const SizedBox(height: 8),
                      DropdownButton<RequestStatus>(
                        isExpanded: true,
                        value: r.status,
                        dropdownColor: AppColors.slate800,
                        items: _statusFlow
                            .map(
                              (s) => DropdownMenuItem(
                                value: s,
                                child: Text(
                                    tr(context,
                                        fr: s.labelFr(s), ar: s.labelAr(s)),
                                    style:
                                        const TextStyle(color: Colors.white)),
                              ),
                            )
                            .toList(),
                        onChanged: (s) {
                          if (s == null) return;
                          final ok = RequestStore.updateStatus(r.id, s);
                          if (!ok) {
                            // Confirmation refused (insufficient tokens).
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(tr(context,
                                    fr: 'Tokens insuffisants pour confirmer (10 requis).',
                                    ar: 'الرصيد غير كافٍ للتأكيد (مطلوب 10 توكن).')),
                                backgroundColor: Colors.red,
                              ),
                            );
                          }
                        },
                      ),
                    ],
                    if (RequestStore.isChatAllowed(r.id))
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: SizedBox(
                          width: double.infinity,
                          child: OutlinedButton.icon(
                            onPressed: () {
                              ChatStore.seedDemo(r.id);
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                    builder: (_) =>
                                        ChatScreen(
                                            requestId: r.id,
                                            isCustomer: false)),
                              );
                            },
                            icon: const Icon(Icons.chat_rounded),
                            label: Text(tr(context, fr: 'Chat', ar: 'محادثة')),
                          ),
                        ),
                      ),
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }
}
