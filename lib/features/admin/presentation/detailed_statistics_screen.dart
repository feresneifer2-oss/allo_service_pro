import 'package:flutter/material.dart';
import 'package:allo_service_pro/core/theme/app_colors.dart';
import 'package:allo_service_pro/features/admin/application/statistics_store.dart';
import 'package:allo_service_pro/features/requests/application/request_store.dart';
import 'package:allo_service_pro/shared/app_locale.dart';

class DetailedStatisticsScreen extends StatefulWidget {
  const DetailedStatisticsScreen({super.key});

  @override
  State<DetailedStatisticsScreen> createState() =>
      _DetailedStatisticsScreenState();
}

class _DetailedStatisticsScreenState extends State<DetailedStatisticsScreen> {
  String _selectedTab =
      'overview'; // 'overview', 'category', 'region', 'status'

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F172A),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0F172A),
        title: Text(
          tr(context, fr: 'Statistiques détaillées', ar: 'إحصائيات تفصيلية'),
          style: const TextStyle(color: Colors.white),
        ),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: Column(
        children: [
          // Tab selector
          SizedBox(
            height: 50,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              children: [
                _StatTab(
                  label: tr(context, fr: 'Vue d\'ensemble', ar: 'نظرة عامة'),
                  isSelected: _selectedTab == 'overview',
                  onTap: () => setState(() => _selectedTab = 'overview'),
                ),
                _StatTab(
                  label: tr(context, fr: 'Par catégorie', ar: 'حسب الفئة'),
                  isSelected: _selectedTab == 'category',
                  onTap: () => setState(() => _selectedTab = 'category'),
                ),
                _StatTab(
                  label: tr(context, fr: 'Par région', ar: 'حسب المنطقة'),
                  isSelected: _selectedTab == 'region',
                  onTap: () => setState(() => _selectedTab = 'region'),
                ),
                _StatTab(
                  label: tr(context, fr: 'Par statut', ar: 'حسب الحالة'),
                  isSelected: _selectedTab == 'status',
                  onTap: () => setState(() => _selectedTab = 'status'),
                ),
              ],
            ),
          ),
          const Divider(height: 1, color: Color(0xFF1E293B)),
          // Content
          Expanded(
            child: _buildContent(),
          ),
        ],
      ),
    );
  }

  Widget _buildContent() {
    switch (_selectedTab) {
      case 'category':
        return _CategoryStats();
      case 'region':
        return _RegionStats();
      case 'status':
        return _StatusStats();
      default:
        return _OverviewStats();
    }
  }
}

class _StatTab extends StatelessWidget {
  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  const _StatTab({
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: InkWell(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: isSelected ? AppColors.secondary : Colors.transparent,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Text(
            label,
            style: TextStyle(
              color: isSelected ? Colors.white : const Color(0xFF94A3B8),
              fontWeight: FontWeight.bold,
              fontSize: 13,
            ),
          ),
        ),
      ),
    );
  }
}

class _OverviewStats extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder(
      valueListenable: RequestStore.requests,
      builder: (context, _, __) {
        return SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                tr(context, fr: 'Vue d\'ensemble', ar: 'نظرة عامة'),
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: _StatCard(
                      title: tr(context,
                          fr: 'Revenu total', ar: 'إجمالي الإيرادات'),
                      value: '${StatisticsStore.getTotalRevenue()} DT',
                      icon: Icons.attach_money_rounded,
                      color: const Color(0xFF22C55E),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _StatCard(
                      title:
                          tr(context, fr: 'Note moyenne', ar: 'متوسط التقييم'),
                      value:
                          StatisticsStore.getAverageRating().toStringAsFixed(1),
                      icon: Icons.star_rounded,
                      color: const Color(0xFFF59E0B),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              _StatCard(
                title:
                    tr(context, fr: 'Total des demandes', ar: 'إجمالي الطلبات'),
                value: '${RequestStore.requests.value.length}',
                icon: Icons.receipt_long_rounded,
                color: AppColors.primary,
              ),
              const SizedBox(height: 24),
              Text(
                tr(context, fr: 'Demandes récentes', ar: 'الطلبات الأخيرة'),
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 12),
              ...StatisticsStore.getRecentRequests(5)
                  .map((request) => _RecentRequestCard(request: request)),
            ],
          ),
        );
      },
    );
  }
}

class _CategoryStats extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder(
      valueListenable: RequestStore.requests,
      builder: (context, _, __) {
        final categoryStats = StatisticsStore.getRequestsByCategory();
        final sortedCategories = categoryStats.entries.toList()
          ..sort((a, b) => b.value.compareTo(a.value));

        return SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                tr(context,
                    fr: 'Statistiques par catégorie', ar: 'إحصائيات حسب الفئة'),
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 16),
              if (sortedCategories.isEmpty)
                const Center(
                  child: Text(
                    'Aucune donnée disponible',
                    style: TextStyle(color: Color(0xFF64748B)),
                  ),
                )
              else
                ...sortedCategories.map((entry) => _StatBar(
                      label: entry.key,
                      value: entry.value,
                      total: RequestStore.requests.value.length,
                      color: AppColors.secondary,
                    )),
            ],
          ),
        );
      },
    );
  }
}

class _RegionStats extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder(
      valueListenable: RequestStore.requests,
      builder: (context, _, __) {
        final regionStats = StatisticsStore.getRequestsByRegion();
        final sortedRegions = regionStats.entries.toList()
          ..sort((a, b) => b.value.compareTo(a.value));

        return SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                tr(context,
                    fr: 'Statistiques par région', ar: 'إحصائيات حسب المنطقة'),
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 16),
              if (sortedRegions.isEmpty)
                const Center(
                  child: Text(
                    'Aucune donnée disponible',
                    style: TextStyle(color: Color(0xFF64748B)),
                  ),
                )
              else
                ...sortedRegions.map((entry) => _StatBar(
                      label: entry.key,
                      value: entry.value,
                      total: RequestStore.requests.value.length,
                      color: AppColors.primary,
                    )),
            ],
          ),
        );
      },
    );
  }
}

class _StatusStats extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder(
      valueListenable: RequestStore.requests,
      builder: (context, _, __) {
        final statusStats = StatisticsStore.getRequestsByStatus();
        final sortedStatuses = statusStats.entries.toList()
          ..sort((a, b) => b.value.compareTo(a.value));

        return SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                tr(context,
                    fr: 'Statistiques par statut', ar: 'إحصائيات حسب الحالة'),
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 16),
              if (sortedStatuses.isEmpty)
                const Center(
                  child: Text(
                    'Aucune donnée disponible',
                    style: TextStyle(color: Color(0xFF64748B)),
                  ),
                )
              else
                ...sortedStatuses.map((entry) => _StatBar(
                      label: entry.key,
                      value: entry.value,
                      total: RequestStore.requests.value.length,
                      color: AppColors.success,
                    )),
            ],
          ),
        );
      },
    );
  }
}

class _StatCard extends StatelessWidget {
  final String title;
  final String value;
  final IconData icon;
  final Color color;

  const _StatCard({
    required this.title,
    required this.value,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: color, size: 24),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: Color(0xFF94A3B8),
                    fontSize: 12,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  value,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
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

class _StatBar extends StatelessWidget {
  final String label;
  final int value;
  final int total;
  final Color color;

  const _StatBar({
    required this.label,
    required this.value,
    required this.total,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final percentage =
        total > 0 ? (value / total * 100).toStringAsFixed(1) : '0.0';

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                label,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
              ),
              Text(
                '$value ($percentage%)',
                style: TextStyle(
                  color: color,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: LinearProgressIndicator(
              value: total > 0 ? value / total : 0,
              backgroundColor: const Color(0xFF334155),
              valueColor: AlwaysStoppedAnimation<Color>(color),
              minHeight: 8,
            ),
          ),
        ],
      ),
    );
  }
}

class _RecentRequestCard extends StatelessWidget {
  final dynamic request;

  const _RecentRequestCard({required this.request});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          const Icon(Icons.receipt_long_rounded,
              color: AppColors.primary, size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  request.serviceTitleFr,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                ),
                Text(
                  '${request.customerName} • ${request.dateTime.day}/${request.dateTime.month}',
                  style: const TextStyle(
                    color: Color(0xFF94A3B8),
                    fontSize: 12,
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
