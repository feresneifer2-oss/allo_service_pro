import 'package:flutter/material.dart';

import 'package:allo_service_pro/core/models/request_status.dart';
import 'package:allo_service_pro/core/theme/app_colors.dart';
import 'package:allo_service_pro/features/requests/application/request_store.dart';
import 'package:allo_service_pro/features/requests/models/service_request.dart';
import 'package:allo_service_pro/features/requests/presentation/request_detail_screen.dart';
import 'package:allo_service_pro/shared/app_locale.dart';
import 'package:allo_service_pro/shared/widgets/empty_state_widget.dart';
import 'package:allo_service_pro/shared/widgets/status_badge.dart';

class RequestListScreen extends StatefulWidget {
  const RequestListScreen({super.key});

  @override
  State<RequestListScreen> createState() => _RequestListScreenState();
}

class _RequestListScreenState extends State<RequestListScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tab;

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tab.dispose();
    super.dispose();
  }

  List<ServiceRequest> _filter(List<ServiceRequest> all, int tab) {
    switch (tab) {
      case 0:
        return all.where((r) => r.status.isActive).toList();
      case 1:
        return all.where((r) => r.status == RequestStatus.completed).toList();
      case 2:
        return all
            .where(
              (r) =>
                  r.status == RequestStatus.cancelled ||
                  r.status == RequestStatus.refused,
            )
            .toList();
      default:
        return all;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text(tr(context, fr: 'Demandes', ar: 'الطلبات')),
        bottom: TabBar(
          controller: _tab,
          labelColor: AppColors.primary,
          unselectedLabelColor: AppColors.textSecondary,
          indicatorColor: AppColors.secondary,
          tabs: [
            Tab(text: tr(context, fr: 'En cours', ar: 'جارية')),
            Tab(text: tr(context, fr: 'Terminées', ar: 'مكتملة')),
            Tab(text: tr(context, fr: 'Annulées', ar: 'ملغاة')),
          ],
        ),
      ),
      body: ValueListenableBuilder<List<ServiceRequest>>(
        valueListenable: RequestStore.requests,
        builder: (context, all, _) {
          return TabBarView(
            controller: _tab,
            children: List.generate(3, (tab) {
              final items = _filter(all, tab);
              if (items.isEmpty) {
                return EmptyStateWidget(
                  icon: Icons.receipt_long_rounded,
                  title: tr(context, fr: 'Aucune demande', ar: 'لا توجد طلبات'),
                  message: tr(context,
                      fr: 'Vos demandes apparaîtront ici.',
                      ar: 'طلباتك بتظهر هنا.'),
                );
              }
              return ListView.builder(
                padding: const EdgeInsets.all(20),
                itemCount: items.length,
                itemBuilder: (_, i) {
                  final r = items[i];
                  final service =
                      tr(context, fr: r.serviceTitleFr, ar: r.serviceTitleAr);
                  return GestureDetector(
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => RequestDetailScreen(requestId: r.id),
                        ),
                      );
                    },
                    child: Container(
                      margin: const EdgeInsets.only(bottom: 12),
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(18),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: .04),
                            blurRadius: 10,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 48,
                            height: 48,
                            decoration: BoxDecoration(
                              color: AppColors.primarySurface,
                              borderRadius: BorderRadius.circular(14),
                            ),
                            child: const Icon(Icons.receipt_long_rounded,
                                color: AppColors.primary),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(service,
                                    style: const TextStyle(
                                        fontWeight: FontWeight.w800)),
                                Text(r.professionalName,
                                    style: const TextStyle(
                                        color: AppColors.textSecondary)),
                              ],
                            ),
                          ),
                          StatusBadge(status: r.status),
                        ],
                      ),
                    ),
                  );
                },
              );
            }),
          );
        },
      ),
    );
  }
}
