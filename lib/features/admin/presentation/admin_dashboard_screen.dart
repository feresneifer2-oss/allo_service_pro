import 'dart:io';

import 'package:flutter/material.dart';

import 'package:allo_service_pro/core/models/request_status.dart';
import 'package:allo_service_pro/core/theme/app_colors.dart';
import 'package:allo_service_pro/features/admin/application/admin_store.dart';
import 'package:allo_service_pro/features/admin/domain/pending_pro_model.dart';
import 'package:allo_service_pro/features/admin/domain/pro_badges.dart';
import 'package:allo_service_pro/features/auth/application/user_store.dart';
import 'package:allo_service_pro/features/chat/application/chat_store.dart';
import 'package:allo_service_pro/features/notifications/application/notification_store.dart';
import 'package:allo_service_pro/features/notifications/domain/notification_model.dart';
import 'package:allo_service_pro/features/requests/application/request_store.dart';
import 'package:allo_service_pro/features/professionals/data/professionals_repository.dart';
import 'package:allo_service_pro/features/pro_dashboard/application/pro_profile_store.dart';
import 'package:allo_service_pro/features/requests/models/service_request.dart';
import 'package:allo_service_pro/features/support/presentation/support_screen.dart'
    show SupportStore, SupportTicket, ChatMsg;
import 'package:allo_service_pro/shared/app_locale.dart';
import 'package:allo_service_pro/shared/widgets/logout_tile.dart';

/// ─────────────────────────────────────────────────────────────────────────────
/// ADMIN DASHBOARD — clean-slate build (5 tabs · KPIs · global search).
/// Tabs: Professionnels · En attente · Tickets · Clients · Paramètres.
/// All state lives in AdminStore/UserStore/SupportStore ValueNotifiers and
/// persists to SharedPreferences.
/// ─────────────────────────────────────────────────────────────────────────────
class AdminDashboardScreen extends StatefulWidget {
  const AdminDashboardScreen({super.key});

  @override
  State<AdminDashboardScreen> createState() => _AdminDashboardScreenState();
}

class _AdminDashboardScreenState extends State<AdminDashboardScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  final _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 5, vsync: this);
    _searchController.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _tabController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      resizeToAvoidBottomInset: true,
      backgroundColor: AppColors.slate900,
      appBar: AppBar(
        backgroundColor: AppColors.slate900,
        foregroundColor: Colors.white,
        title: Text(tr(context,
            fr: 'Panneau d\'administration', ar: 'لوحة الإدارة')),
      ),
      body: SafeArea(
        child: Column(
          children: [
            // ── Scrollable header (search + KPI rows) ─────────────────────
            // Flexible (loose fit): takes exactly its content height when
            // space is plentiful, and gracefully shrinks + scrolls when the
            // keyboard eats into the viewport — never a pixel overflow.
            Flexible(
              child: SingleChildScrollView(
                keyboardDismissBehavior:
                    ScrollViewKeyboardDismissBehavior.onDrag,
                physics: const ClampingScrollPhysics(),
                padding: const EdgeInsets.only(bottom: 4),
                child: Column(
                  children: [
                    _buildSearchBar(),
                    _buildKpiRows(),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 8),
            _buildTabBar(),
            const SizedBox(height: 4),
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: [
                  _ProsTab(query: _searchController.text.trim()),
                  _PendingTab(query: _searchController.text.trim()),
                  const _TicketsTab(),
                  _ClientsTab(query: _searchController.text.trim()),
                  const _SettingsTab(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Global search bar (above tabs) ────────────────────────────────────────
  Widget _buildSearchBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
      child: TextField(
        controller: _searchController,
        style: const TextStyle(color: Colors.white),
        decoration: InputDecoration(
          hintText: tr(context,
              fr: 'Rechercher par nom ou ID (PRO-… / client)',
              ar: 'ابحث بالاسم أو المعرّف (PRO-… / كليان)'),
          hintStyle: const TextStyle(color: AppColors.slate400, fontSize: 13),
          prefixIcon:
              const Icon(Icons.search_rounded, color: AppColors.secondary),
          filled: true,
          fillColor: AppColors.slate800,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide.none,
          ),
        ),
      ),
    );
  }

  // ── KPI rows (live from ValueNotifiers) ───────────────────────────────────
  Widget _buildKpiRows() {
    return ValueListenableBuilder<List<PendingProModel>>(
      valueListenable: AdminStore.pendingPros,
      builder: (_, __, ___) {
        return ValueListenableBuilder<List<ServiceRequest>>(
          valueListenable: RequestStore.requests,
          builder: (_, ___, ____) {
            return ValueListenableBuilder<List<UserModel>>(
              valueListenable: UserStore.registeredClients,
              builder: (_, ___, _____) {
                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Column(
                    children: [
                      Row(
                        children: [
                          Expanded(child: _KpiCard(
                            label: tr(context, fr: 'Clients', ar: 'كليان'),
                            value: '${AdminStore.totalClients}',
                            icon: Icons.people_rounded,
                            color: const Color(0xFF3B82F6),
                          )),
                          const SizedBox(width: 8),
                          Expanded(child: _KpiCard(
                            label: tr(context, fr: 'Pros', ar: 'حرفيون'),
                            value: '${AdminStore.totalProsCount}',
                            icon: Icons.engineering_rounded,
                            color: AppColors.primary,
                          )),
                          const SizedBox(width: 8),
                          Expanded(child: _KpiCard(
                            label: tr(context,
                                fr: 'Acceptés (jour)', ar: 'مقبولة اليوم'),
                            value: '${AdminStore.acceptedOrdersToday}',
                            icon: Icons.check_circle_rounded,
                            color: AppColors.success,
                          )),
                          const SizedBox(width: 8),
                          Expanded(child: _KpiCard(
                            label: tr(context,
                                fr: 'Refusés (jour)', ar: 'مرفوضة اليوم'),
                            value: '${AdminStore.refusedOrdersToday}',
                            icon: Icons.cancel_rounded,
                            color: AppColors.error,
                          )),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                            child: _KpiCard(
                              label: tr(context,
                                  fr: 'Commandes acceptées (total)',
                                  ar: 'الطلبات المقبولة (الكل)'),
                              value: '${AdminStore.acceptedOrdersAllTime}',
                              icon: Icons.receipt_long_rounded,
                              color: AppColors.secondary,
                              large: true,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: _KpiCard(
                              label: tr(context,
                                  fr: '💰 Cash revenue', ar: '💰 مداخيل الكاش'),
                              value: '${AdminStore.cashRevenueTnd} DT',
                              icon: Icons.savings_rounded,
                              color: const Color(0xFFB8860B),
                              large: true,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                );
              },
            );
          },
        );
      },
    );
  }

  // ── Tab bar (scrollable — never overflows) ────────────────────────────────
  Widget _buildTabBar() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 20),
      decoration: BoxDecoration(
        color: AppColors.slate800,
        borderRadius: BorderRadius.circular(14),
      ),
      child: TabBar(
        controller: _tabController,
        isScrollable: true,
        tabAlignment: TabAlignment.start,
        padding: const EdgeInsets.symmetric(horizontal: 4),
        labelPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        indicator: BoxDecoration(
          color: AppColors.secondary,
          borderRadius: BorderRadius.circular(12),
        ),
        labelColor: Colors.white,
        unselectedLabelColor: AppColors.textSecondary,
        labelStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
        dividerColor: Colors.transparent,
        tabs: [
          Tab(text: tr(context, fr: 'Professionnels', ar: 'الحرفيون')),
          Tab(text: tr(context, fr: 'En attente', ar: 'قيد الانتظار')),
          Tab(text: tr(context, fr: 'Tickets', ar: 'التذاكر')),
          Tab(text: tr(context, fr: 'Clients', ar: 'العملاء')),
          Tab(text: tr(context, fr: 'Paramètres', ar: 'الإعدادات')),
        ],
      ),
    );
  }
}

/// Compact KPI tile used in both metric rows.
class _KpiCard extends StatelessWidget {
  const _KpiCard({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
    this.large = false,
  });

  final String label;
  final String value;
  final IconData icon;
  final Color color;
  final bool large;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(
          horizontal: large ? 16 : 10, vertical: large ? 14 : 10),
      decoration: BoxDecoration(
        color: AppColors.slate800,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: .35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: large ? 22 : 16),
          const SizedBox(height: 4),
          FittedBox(child: Text(
            value,
            style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w800,
                fontSize: large ? 20 : 15),
          )),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: AppColors.slate400, fontSize: 10.5),
          ),
        ],
      ),
    );
  }
}

class _ProsTab extends StatelessWidget {
  const _ProsTab({required this.query});

  final String query;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<List<PendingProModel>>(
      valueListenable: AdminStore.pendingPros,
      builder: (_, list, __) {
        final q = query.toLowerCase();
        final pros = list
            .where((p) =>
                p.status == 'approved' &&
                (q.isEmpty ||
                    p.name.toLowerCase().contains(q) ||
                    (p.proCode ?? '').toLowerCase().contains(q)))
            .toList();
        if (pros.isEmpty) {
          return _EmptyView(
            icon: Icons.engineering_rounded,
            message: tr(context, fr: 'Aucun professionnel', ar: 'لا يوجد حرفيون'),
          );
        }
        return ListView.separated(
          padding: const EdgeInsets.all(20),
          itemCount: pros.length,
          separatorBuilder: (_, __) => const SizedBox(height: 12),
          itemBuilder: (_, i) => _ProManageCard(pro: pros[i]),
        );
      },
    );
  }
}

class _ProManageCard extends StatelessWidget {
  const _ProManageCard({required this.pro});

  final PendingProModel pro;

  void _snack(BuildContext context, String fr, String ar) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(tr(context, fr: fr, ar: ar))));
  }

  void _showDocument(BuildContext context) {
    showDialog(
      context: context,
      builder: (_) => Dialog(
        backgroundColor: AppColors.slate900,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(tr(context, fr: 'Pièce d\'identité', ar: 'وثيقة الهوية'),
                  style: const TextStyle(
                      color: Colors.white, fontWeight: FontWeight.w800)),
              const SizedBox(height: 10),
              Container(
                height: 320,
                width: double.infinity,
                decoration: BoxDecoration(
                  color: Colors.black26,
                  borderRadius: BorderRadius.circular(12),
                ),
                clipBehavior: Clip.antiAlias,
                child: (pro.docImage == null)
                    ? Center(
                        child: Text(
                            tr(context, fr: 'Aucune preuve fournie',
                                ar: 'لا توجد وثيقة'),
                            style: const TextStyle(
                                color: AppColors.textSecondary)))
                    : InteractiveViewer(
                        maxScale: 4,
                        child: pro.docImage!.startsWith('assets/')
                            ? Image.asset(pro.docImage!, fit: BoxFit.contain)
                            : Image.file(File(pro.docImage!),
                                fit: BoxFit.contain,
                                errorBuilder: (_, __, ___) => const Center(
                                    child: Text('Preuve illisible',
                                        style: TextStyle(
                                            color:
                                                AppColors.textSecondary)))),
                      ),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text(tr(context, fr: 'Fermer', ar: 'إغلاق')),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── build ────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final proId = pro.proCode ?? pro.id;
    final orders = RequestStore.forProfessional(proId);
    const live = [
      RequestStatus.accepted,
      RequestStatus.enRoute,
      RequestStatus.arrived,
      RequestStatus.inProgress,
      RequestStatus.completed,
    ];
    final accepted = orders.where((r) => live.contains(r.status)).length;
    final refused =
        orders.where((r) => r.status == RequestStatus.refused).length;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 24,
                backgroundColor: AppColors.primarySurface,
                child: Text(
                  pro.name.isNotEmpty ? pro.name[0].toUpperCase() : '?',
                  style: const TextStyle(
                      color: AppColors.primary,
                      fontWeight: FontWeight.w800,
                      fontSize: 18),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(pro.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontWeight: FontWeight.w800, fontSize: 15)),
                    Text(
                      '${pro.proCode ?? '-'} • ${pro.phone}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          color: AppColors.textSecondary, fontSize: 12),
                    ),
                    Text(
                      '${pro.professionFr} • ${pro.city ?? '-'}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          color: AppColors.textSecondary, fontSize: 12),
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: tr(context, fr: 'Voir le document', ar: 'عرض الوثيقة'),
                onPressed: () => _showDocument(context),
                icon:
                    const Icon(Icons.badge_rounded, color: AppColors.primary),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: [
              _Chip(
                label: '⭐ ${ProProfileLookup.rating(pro)}/5',
                color: const Color(0xFFB8860B),
              ),
              _Chip(
                label: tr(context,
                    fr: 'Acceptées: $accepted', ar: 'مقبولة: $accepted'),
                color: AppColors.success,
              ),
              _Chip(
                label: tr(context,
                    fr: 'Refusées: $refused', ar: 'مرفوضة: $refused'),
                color: AppColors.error,
              ),
              _Chip(
                label: tr(context,
                    fr: 'Tokens: ${pro.tokens}', ar: 'توكنز: ${pro.tokens}'),
                color: AppColors.primary,
              ),
            ],
          ),
          // ── Lifecycle warnings (real-time from the registry) ──────────────
          // Instant visual cues so the admin spots pros needing a renewal:
          // expired/never-activated subscription · depleted token balance.
          if (!pro.isPaid || pro.tokens <= 0) ...[
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: [
                if (!pro.isPaid)
                  _Chip(
                    label: tr(context,
                        fr: 'Abonnement Expiré', ar: 'منتهي الاشتراك'),
                    color: AppColors.warning,
                  ),
                if (pro.tokens <= 0)
                  _Chip(
                    label: tr(context,
                        fr: 'Tokens Épuisés', ar: 'نفدت التوكينات'),
                    color: AppColors.error,
                  ),
              ],
            ),
          ],
          const SizedBox(height: 10),

          // ── Official badges (1-tap toggles — syncs Client & Pro views) ──
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: [
              for (final b in ProBadges.all)
                FilterChip(
                  label: Text(ProBadges.label(context, b)),
                  selected: pro.badges.contains(b),
                  onSelected: (_) {
                    if (pro.badges.contains(b)) {
                      AdminStore.removeBadge(pro.id, b);
                      _snack(context, 'Badge retiré à ${pro.name}',
                          'تم إزالة شارة ${pro.name}');
                    } else {
                      AdminStore.addBadge(pro.id, b);
                      _snack(context, 'Badge ajouté à ${pro.name}',
                          'تمت إضافة شارة ${pro.name}');
                    }
                  },
                  selectedColor: AppColors.secondary,
                  checkmarkColor: Colors.white,
                  labelStyle: TextStyle(
                    color: pro.badges.contains(b)
                        ? Colors.white
                        : AppColors.textSecondary,
                    fontWeight: FontWeight.w700,
                    fontSize: 11.5,
                  ),
                  backgroundColor: AppColors.background,
                ),
            ],
          ),
          const SizedBox(height: 10),

          // ── Subscription controls ──
          Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: () {
                    // +15 DT is logged on the target pro's own registry
                    // record: subscription flags + expiry live on the pro,
                    // the admin's global session store is never touched.
                    AdminStore.grantSubscription(pro.id);
                    _snack(context,
                        'Abonnement activé (+15 DT) pour ${pro.name}',
                        'تم تفعيل اشتراك ${pro.name} (+15 د.ت)');
                  },
                  icon:
                      const Icon(Icons.check_circle_rounded, size: 15),
                  label: FittedBox(child: Text(
                      tr(context, fr: 'Activer 30j (+15DT)',
                          ar: 'تفعيل 30ي (+15د.ت)'),
                      maxLines: 1,
                      style: const TextStyle(fontSize: 11.5))),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.success,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 8),
                  ),
                ),
              ),
              const SizedBox(width: 6),
              Expanded(child: ElevatedButton.icon(
                onPressed: () {
                  AdminStore.revokeSubscription(pro.id);
                  _snack(context, 'Abonnement expiré pour ${pro.name}',
                      'تم إنهاء اشتراك ${pro.name}');
                },
                icon: const Icon(Icons.block_rounded, size: 15),
                label: FittedBox(child: Text(tr(context, fr: 'Expirer', ar: 'إلغاء'),
                    style: const TextStyle(fontSize: 11.5))),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.error,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(
                      vertical: 8, horizontal: 8),
                ),
              )),
            ],
          ),
          const SizedBox(height: 8),

          // ── Suspension controls ──
          Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: pro.deactivated
                      ? null
                      : () {
                          // Suspends + notifies the pro ("تم تجميد حسابك").
                          AdminStore.suspendPro(pro.id);
                          _snack(context,
                              'Compte de ${pro.name} suspendu',
                              'تم تجميد حساب ${pro.name}');
                        },
                  icon: const Icon(Icons.ac_unit_rounded, size: 15),
                  label: Text(tr(context, fr: 'Suspendre', ar: 'تجميد'),
                      style: const TextStyle(fontSize: 11.5)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.error,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 8),
                  ),
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: !pro.deactivated
                      ? null
                      : () {
                          // Re-activates + notifies ("تم إعادة تفعيل حسابك").
                          AdminStore.reactivatePro(pro.id);
                          _snack(context,
                              'Compte de ${pro.name} réactivé',
                              'تم إعادة تفعيل حساب ${pro.name}');
                        },
                  icon: const Icon(Icons.restart_alt_rounded, size: 15),
                  label: Text(tr(context, fr: 'Réactiver', ar: 'إعادة تفعيل'),
                      style: const TextStyle(fontSize: 11.5)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.success,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 8),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Small helper resolving the display rating of a registry pro.
class ProProfileLookup {
  ProProfileLookup._();

  static double rating(PendingProModel pro) {
    final live = ProfessionalsRepository.byId(pro.proCode ?? '');
    return live?.rating ?? ProProfileStore.rating.value;
  }
}

// TAB 2 — EN ATTENTE (verification queue)
class _PendingTab extends StatelessWidget {
  const _PendingTab({required this.query});
  final String query;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<List<PendingProModel>>(
      valueListenable: AdminStore.pendingPros,
      builder: (_, list, __) {
        final q = query.toLowerCase();
        final pending = list
            .where((p) =>
                p.status == 'pending' &&
                (q.isEmpty ||
                    p.name.toLowerCase().contains(q) ||
                    (p.proCode ?? '').toLowerCase().contains(q)))
            .toList();
        if (pending.isEmpty) {
          return _EmptyView(
            icon: Icons.hourglass_empty_rounded,
            message: tr(context,
                fr: 'Aucune demande en attente 👌',
                ar: 'لا طلبات قيد الانتظار 👌'),
          );
        }
        return ListView.separated(
          padding: const EdgeInsets.all(20),
          itemCount: pending.length,
          separatorBuilder: (_, __) => const SizedBox(height: 12),
          itemBuilder: (_, i) => _PendingCard(pro: pending[i]),
        );
      },
    );
  }
}

class _PendingCard extends StatelessWidget {
  const _PendingCard({required this.pro});
  final PendingProModel pro;

  void _snack(BuildContext context, String fr, String ar) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(tr(context, fr: fr, ar: ar))));
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 22,
                backgroundColor: AppColors.secondarySurface,
                child: Text(
                  pro.name.isNotEmpty ? pro.name[0].toUpperCase() : '?',
                  style: const TextStyle(
                      color: AppColors.secondary,
                      fontWeight: FontWeight.w800,
                      fontSize: 16),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(pro.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontWeight: FontWeight.w800, fontSize: 14.5)),
                    Text(
                      '${pro.phone} • ${pro.professionFr} • ${pro.city ?? '-'}',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          color: AppColors.textSecondary, fontSize: 12),
                    ),
                  ],
                ),
              ),
              if (pro.docImage != null)
                IconButton(
                  tooltip: tr(context, fr: 'Voir le document', ar: 'الوثيقة'),
                  onPressed: () {
                    showDialog(
                      context: context,
                      builder: (_) => Dialog(
                        backgroundColor: AppColors.slate900,
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              InteractiveViewer(
                                maxScale: 4,
                                child: pro.docImage!.startsWith('assets/')
                                    ? Image.asset(pro.docImage!, fit: BoxFit.contain,
                                        errorBuilder: (_, __, ___) => const Center(
                                            child: Column(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                Icon(Icons.broken_image_rounded,
                                                    color: Colors.white70, size: 48),
                                                SizedBox(height: 8),
                                                Text('Image illisible',
                                                    style: TextStyle(
                                                        color: Colors.white70)),
                                              ],
                                            )))
                                    : Image.file(File(pro.docImage!),
                                        fit: BoxFit.contain,
                                        errorBuilder: (_, __, ___) => const Center(
                                            child: Column(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                Icon(Icons.broken_image_rounded,
                                                    color: Colors.white70, size: 48),
                                                SizedBox(height: 8),
                                                Text('Image illisible',
                                                    style: TextStyle(
                                                        color: Colors.white70)),
                                              ],
                                            ))),
                              ),
                              TextButton(
                                onPressed: () => Navigator.pop(context),
                                child: Text(tr(context, fr: 'Fermer', ar: 'إغلاق')),
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                  icon: const Icon(Icons.badge_rounded, color: AppColors.secondary),
                ),
            ],
          ),
          const SizedBox(height: 10),
// @@THREAD@@
          // ── Two-way verification thread (latest 3) ──
          if (pro.adminMessages.isNotEmpty) ...[
            for (final m in pro.adminMessages.reversed.take(3))
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      m.startsWith('AlloService|')
                          ? Icons.verified_user_rounded
                          : Icons.person_rounded,
                      size: 14,
                      color: m.startsWith('AlloService|')
                          ? AppColors.success
                          : AppColors.textSecondary,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        m.split('|').length > 1 ? m.split('|')[1] : m,
                        style: const TextStyle(
                            fontSize: 12, color: AppColors.slate800),
                      ),
                    ),
                  ],
                ),
              ),
            const SizedBox(height: 6),
          ],
          _ReplyField(proId: pro.id),
          const SizedBox(height: 10),

          // ── One-tap approval (auto-grants 'cin') ──
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: () {
                AdminStore.approvePro(pro.id);
                _snack(context,
                    '${pro.name} approuvé — badge CIN Vérifié attribué',
                    'تم قبول ${pro.name} — منح شارة الهوية المفعلة');
              },
              icon: const Icon(Icons.how_to_reg_rounded),
              label: FittedBox(child: Text(tr(context, fr: 'Approuver', ar: 'قبول الحساب'),
                  style: const TextStyle(
                      color: Colors.white, fontWeight: FontWeight.w800))),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.success,
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Admin → pro message composer (sender: AlloService).
class _ReplyField extends StatefulWidget {
  const _ReplyField({required this.proId});
  final String proId;

  @override
  State<_ReplyField> createState() => _ReplyFieldState();
}

class _ReplyFieldState extends State<_ReplyField> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: TextField(
            controller: _controller,
            style: const TextStyle(fontSize: 13),
            decoration: InputDecoration(
              isDense: true,
              hintText: tr(context,
                  fr: 'Message AlloService (ex: photo illisible…)',
                  ar: 'رسالة AlloService (مثال: الصورة غير واضحة…)'),
              border:
                  OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            ),
          ),
        ),
        IconButton(
          onPressed: () {
            AdminStore.sendVerificationMessage(widget.proId, _controller.text);
            _controller.clear();
          },
          icon: const Icon(Icons.send_rounded, color: AppColors.primary),
        ),
      ],
    );
  }
}

/// Reusable empty-state used across the admin tabs.
class _EmptyView extends StatelessWidget {
  const _EmptyView({required this.icon, required this.message});

  final IconData icon;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 48, color: AppColors.slate400),
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Text(message,
                textAlign: TextAlign.center,
                style: const TextStyle(color: AppColors.textSecondary)),
          ),
        ],
      ),
    );
  }
}

/// Small metric chip used in the pros cards.
class _Chip extends StatelessWidget {
  const _Chip({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: .4)),
      ),
      child: Text(
        label,
        style: TextStyle(
            color: color, fontSize: 11.5, fontWeight: FontWeight.w800),
      ),
    );
  }
}

// TAB 3 — TICKETS (support & complaints)
class _TicketsTab extends StatelessWidget {
  const _TicketsTab();

  void _showTicket(BuildContext context, SupportTicket ticket) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.slate900,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(
          left: 20,
          right: 20,
          top: 16,
          bottom: MediaQuery.of(ctx).viewInsets.bottom + 24,
        ),
        child: _TicketReplySheet(ticket: ticket),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<List<SupportTicket>>(
      valueListenable: SupportStore.tickets,
      builder: (_, tickets, __) {
        if (tickets.isEmpty) {
          return _EmptyView(
            icon: Icons.confirmation_number_outlined,
            message: tr(context,
                fr: 'Aucun ticket ouvert', ar: 'لا تذاكر مفتوحة'),
          );
        }
        return ListView.separated(
          padding: const EdgeInsets.all(20),
          itemCount: tickets.length,
          separatorBuilder: (_, __) => const SizedBox(height: 10),
          itemBuilder: (_, i) {
            final t = tickets[i];
            return Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(t.subject,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                fontWeight: FontWeight.w800, fontSize: 14)),
                      ),
                      _Chip(
                        label: t.status == 'resolved'
                            ? tr(context, fr: 'Fermé', ar: 'مغلق')
                            : tr(context, fr: 'Ouvert', ar: 'مفتوح'),
                        color: t.status == 'resolved'
                            ? AppColors.error
                            : AppColors.success,
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${t.senderName} • ${t.date}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        color: AppColors.textSecondary, fontSize: 12),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    t.message,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style:
                        const TextStyle(color: AppColors.slate800, fontSize: 13),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: t.status == 'resolved'
                              ? null
                              : () => _showTicket(context, t),
                          icon: const Icon(Icons.chat_rounded, size: 16),
                          label: Text(tr(context, fr: 'Répondre', ar: 'رد')),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(child: TextButton.icon(
                        onPressed: t.status == 'resolved'
                            ? null
                            : () {
                                SupportStore.resolve(t.id);
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text(tr(context,
                                        fr: 'Ticket fermé',
                                        ar: 'هذه التذكرة مغلقة')),
                                  ),
                                );
                              },
                        icon: const Icon(Icons.close_rounded, size: 16),
                        label: FittedBox(child: Text(tr(context,
                            fr: '[Fermer Ticket]', ar: '[إغلاق التذكرة]'))),
                      )),
                    ],
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }
}

class _TicketReplySheet extends StatefulWidget {
  const _TicketReplySheet({required this.ticket});
  final SupportTicket ticket;

  @override
  State<_TicketReplySheet> createState() => _TicketReplySheetState();
}

class _TicketReplySheetState extends State<_TicketReplySheet> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(widget.ticket.subject,
            style: const TextStyle(
                color: Colors.white, fontWeight: FontWeight.w800, fontSize: 16)),
        const SizedBox(height: 8),
        for (final m in widget.ticket.conversation)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  m.fromUser
                      ? Icons.person_rounded
                      : Icons.support_agent_rounded,
                  size: 14,
                  color:
                      m.fromUser ? AppColors.textSecondary : AppColors.success,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(m.text,
                      style: const TextStyle(color: Colors.white70, fontSize: 13)),
                ),
              ],
            ),
          ),
        const SizedBox(height: 10),
        if (widget.ticket.status == 'resolved')
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.error.withValues(alpha: .12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              tr(context, fr: 'Ticket fermé', ar: 'هذه التذكرة مغلقة'),
              style: const TextStyle(
                  color: AppColors.error, fontWeight: FontWeight.w800),
            ),
          )
        else
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _controller,
                  style: const TextStyle(color: Colors.white),
                  decoration: const InputDecoration(
                    hintText: 'AlloService',
                    hintStyle: TextStyle(color: AppColors.slate400),
                    filled: true,
                    fillColor: AppColors.slate800,
                  ),
                ),
              ),
              IconButton(
                onPressed: () {
                  final text = _controller.text.trim();
                  if (text.isEmpty) return; // reject blank/whitespace-only replies
                  SupportStore.addMessage(
                    widget.ticket.id,
                    ChatMsg(
                      text: text,
                      fromUser: false,
                      time: 'admin',
                    ),
                  );
                  _controller.clear();
                },
                icon: const Icon(Icons.send_rounded, color: AppColors.success),
              ),
            ],
          ),
      ],
    );
  }
}

// TAB 4 — CLIENTS (management + suspension)
class _ClientsTab extends StatelessWidget {
  const _ClientsTab({required this.query});
  final String query;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<List<UserModel>>(
      valueListenable: UserStore.registeredClients,
      builder: (_, clients, __) {
        final q = query.toLowerCase();
        final filtered = clients.where((c) {
          if (q.isEmpty) return true;
          return c.name.toLowerCase().contains(q) ||
              c.phone.contains(q) ||
              c.id.toLowerCase().contains(q);
        }).toList();
        if (filtered.isEmpty) {
          return _EmptyView(
            icon: Icons.people_outline_rounded,
            message: tr(context, fr: 'Aucun client', ar: 'لا عملاء'),
          );
        }
        return ValueListenableBuilder<List<String>>(
          // Reactive suspension: rebuilds the list the instant any client is
          // banned/unbanned, so the Suspendre/Réactiver toggles reflect the
          // new state immediately (no pull-to-refresh required).
          valueListenable: AdminStore.suspendedClients,
          builder: (_, suspended, __) => ListView.separated(
            padding: const EdgeInsets.all(20),
            itemCount: filtered.length,
            separatorBuilder: (_, __) => const SizedBox(height: 10),
            itemBuilder: (_, i) =>
                _ClientCard(client: filtered[i], suspendedIds: suspended),
          ),
        );
      },
    );
  }
}

class _ClientCard extends StatelessWidget {
  const _ClientCard({required this.client, required this.suspendedIds});
  final UserModel client;
  final List<String> suspendedIds;

  @override
  Widget build(BuildContext context) {
    final s = suspendedIds.contains(client.id);
    final orders = RequestStore.forCustomer(client.name).length;
    void snap(String fr, String ar) => ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(tr(context, fr: fr, ar: ar))));

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 18,
                backgroundColor: AppColors.primarySurface,
                child: Text(
                  client.name.isNotEmpty ? client.name[0].toUpperCase() : '?',
                  style: const TextStyle(
                      color: AppColors.primary, fontWeight: FontWeight.w800),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(client.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontWeight: FontWeight.w800, fontSize: 14)),
                    Text(
                      '${client.phone} • ${client.id}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          color: AppColors.textSecondary, fontSize: 12),
                    ),
                  ],
                ),
              ),
              _Chip(
                label: tr(context,
                    fr: 'Commandes: $orders', ar: 'طلبات: $orders'),
                color: AppColors.primary,
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: s
                      ? null
                      : () {
                          AdminStore.suspendClient(client.id);
                          snap('Client suspendu: ${client.name}',
                              'تم تجميد حساب ${client.name}');
                        },
                  icon: const Icon(Icons.ac_unit_rounded, size: 15),
                  label: Text(tr(context, fr: 'Suspendre', ar: 'تجميد'),
                      style: const TextStyle(fontSize: 11.5)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.error,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 8),
                  ),
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: !s
                      ? null
                      : () {
                          AdminStore.reactivateClient(client.id);
                          snap('Client réactivé: ${client.name}',
                              'تم إعادة تفعيل ${client.name}');
                        },
                  icon: const Icon(Icons.restart_alt_rounded, size: 15),
                  label: Text(tr(context, fr: 'Réactiver', ar: 'إعادة تفعيل'),
                      style: const TextStyle(fontSize: 11.5)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.success,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 8),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// TAB 5 — PARAMÈTRES & BROADCAST
class _SettingsTab extends StatefulWidget {
  const _SettingsTab();

  @override
  State<_SettingsTab> createState() => _SettingsTabState();
}

class _SettingsTabState extends State<_SettingsTab> {
  final _broadcastController = TextEditingController();
  String _broadcastTarget = 'clients';

  @override
  void dispose() {
    _broadcastController.dispose();
    super.dispose();
  }

  void _sendBroadcast() {
    final text = _broadcastController.text.trim();
    if (text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content:
            Text(tr(context, fr: 'Écrivez un message', ar: 'اكتب رسالة أولاً')),
      ));
      return;
    }
    final targetRole = _broadcastTarget == 'pros' ? 'professional' : 'client';
    NotificationStore.add(NotificationModel(
      id: '${DateTime.now().millisecondsSinceEpoch}_broadcast',
      title: tr(context, fr: '📣 AlloService', ar: '📣 AlloService'),
      message: text,
      type: 'system',
      recipientId: 'all',
      targetRole: targetRole,
      createdAt: DateTime.now(),
    ));
    _broadcastController.clear();
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(
          tr(context, fr: 'Notification envoyée 🚀', ar: 'تم إرسال الإشعار 🚀')),
    ));
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Text(tr(context, fr: '📢 Diffusion / Broadcast', ar: '📢 إشعار جماعي'),
            style: const TextStyle(
                color: Colors.white, fontWeight: FontWeight.w800)),
        const SizedBox(height: 6),
        Row(
          children: [
            ChoiceChip(
              label: Text(
                  tr(context, fr: 'Tous les Clients', ar: 'كل العملاء')),
              selected: _broadcastTarget == 'clients',
              onSelected: (_) => setState(() => _broadcastTarget = 'clients'),
              selectedColor: AppColors.secondary,
              labelStyle: TextStyle(
                  color: _broadcastTarget == 'clients'
                      ? Colors.white
                      : AppColors.slate400),
            ),
            const SizedBox(width: 8),
            ChoiceChip(
              label:
                  Text(tr(context, fr: 'Tous les Pros', ar: 'كل الحرفيين')),
              selected: _broadcastTarget == 'pros',
              onSelected: (_) => setState(() => _broadcastTarget = 'pros'),
              selectedColor: AppColors.secondary,
              labelStyle: TextStyle(
                  color: _broadcastTarget == 'pros'
                      ? Colors.white
                      : AppColors.slate400),
            ),
          ],
        ),
        const SizedBox(height: 10),
        TextField(
          controller: _broadcastController,
          maxLines: 3,
          style: const TextStyle(color: Colors.white),
          decoration: InputDecoration(
            hintText: tr(context, fr: 'Votre message…', ar: 'رسالتك…'),
            hintStyle: const TextStyle(color: AppColors.slate400),
            filled: true,
            fillColor: AppColors.slate800,
            border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none),
          ),
        ),
        const SizedBox(height: 8),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: _sendBroadcast,
            icon: const Icon(Icons.send_rounded),
            label: Text(tr(context, fr: 'Envoyer 🚀', ar: 'إرسال 🚀'),
                style: const TextStyle(fontWeight: FontWeight.w800)),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.secondary,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 12),
            ),
          ),
        ),
        const SizedBox(height: 20),
        _Card(
          title: tr(context,
              fr: '💰 Récapitulatif recettes cash', ar: '💰 ملخص مداخيل الكاش'),
          body: ValueListenableBuilder<List<PendingProModel>>(
            valueListenable: AdminStore.pendingPros,
            builder: (_, list, __) {
              final paid = list.where((p) => p.isPaid).length;
              return Text(
                '$paid ${tr(context, fr: 'abonnements actifs', ar: 'اشتراك نشط')}'
                ' × 15 DT = $paid×15 = ${paid * 15} DT',
                style: const TextStyle(color: Colors.white, fontSize: 14),
              );
            },
          ),
        ),
        const SizedBox(height: 12),
        _Card(
          title: tr(context,
              fr: '⏱ Fermeture auto des chats', ar: '⏱ إغلاق المحادثات'),
          body: Row(
            children: [48, 60, 72].map((h) {
              return Padding(
                padding: const EdgeInsetsDirectional.only(end: 8),
                child: ChoiceChip(
                  label: Text('${h}h'),
                  selected: ChatStore.expiryHours == h,
                  onSelected: (_) => setState(() => ChatStore.setExpiryHours(h)),
                  selectedColor: AppColors.primary,
                  labelStyle: TextStyle(
                      color: ChatStore.expiryHours == h
                          ? Colors.white
                          : AppColors.slate400),
                ),
              );
            }).toList(),
          ),
        ),
        const SizedBox(height: 20),
        const _Card(
          title: 'Session',
          body: Align(
            alignment: AlignmentDirectional.center,
            child: LogoutTile(),
          ),
        ),
      ],
    );
  }
}

/// Simple titled card used inside admin Settings.
class _Card extends StatelessWidget {
  const _Card({required this.title, required this.body});

  final String title;
  final Widget body;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.slate800,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
                color: Colors.white, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 8),
          body,
        ],
      ),
    );
  }
}