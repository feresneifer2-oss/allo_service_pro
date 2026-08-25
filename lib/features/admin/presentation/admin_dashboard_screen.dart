import 'dart:io';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:allo_service_pro/core/theme/app_colors.dart';
import 'package:allo_service_pro/features/admin/application/admin_store.dart';
import 'package:allo_service_pro/features/admin/domain/pending_pro_model.dart';
import 'package:allo_service_pro/features/requests/application/request_store.dart';
import 'package:allo_service_pro/features/requests/models/service_request.dart';
import 'package:allo_service_pro/core/models/request_status.dart';
import 'package:allo_service_pro/features/admin/presentation/detailed_statistics_screen.dart';
import 'package:allo_service_pro/features/chat/application/chat_store.dart';
import 'package:allo_service_pro/features/chat/models/chat_session.dart';
import 'package:allo_service_pro/features/pro_dashboard/application/subscription_store.dart';

class AdminDashboardScreen extends StatefulWidget {
  const AdminDashboardScreen({super.key});

  @override
  State<AdminDashboardScreen> createState() => _AdminDashboardScreenState();
}

class _AdminDashboardScreenState extends State<AdminDashboardScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F172A),
      body: SafeArea(
        child: Column(
          children: [
            // ── Header ────────────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
              child: Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [AppColors.secondary, AppColors.secondaryLight],
                      ),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(Icons.admin_panel_settings_rounded,
                        color: Colors.white, size: 24),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: const [
                        Text(
                          'Allo Service Pro',
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w800,
                            fontSize: 18,
                          ),
                        ),
                        Text(
                          'Panneau d\'administration',
                          style:
                              TextStyle(color: Color(0xFF94A3B8), fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                  // Badges counter (pending + reports)
                  ValueListenableBuilder<List<PendingProModel>>(
                    valueListenable: AdminStore.pendingPros,
                    builder: (_, __, ___) {
                      return ValueListenableBuilder<List<ReportModel>>(
                        valueListenable: AdminStore.reports,
                        builder: (_, __, ___) {
                          final total = AdminStore.pendingCount +
                              AdminStore.openReportsCount;
                          return total == 0
                              ? const SizedBox.shrink()
                              : Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 10, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: AppColors.error,
                                    borderRadius: BorderRadius.circular(20),
                                  ),
                                  child: Text(
                                    '$total en attente',
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 11,
                                    ),
                                  ),
                                );
                        },
                      );
                    },
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),

            // ── Stats Row ─────────────────────────────────────────────────────
            SizedBox(
              height: 106,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 20),
                children: [
                  ValueListenableBuilder<int>(
                    valueListenable: AdminStore.totalUsers,
                    builder: (_, v, __) => _StatCard(
                        label: 'Utilisateurs',
                        value: '$v',
                        icon: Icons.people_rounded,
                        gradient: const LinearGradient(
                            colors: [Color(0xFF1D4ED8), Color(0xFF3B82F6)])),
                  ),
                  const SizedBox(width: 12),
                  ValueListenableBuilder<int>(
                    valueListenable: AdminStore.totalPros,
                    builder: (_, v, __) => _StatCard(
                        label: 'Professionnels',
                        value: '$v',
                        icon: Icons.engineering_rounded,
                        gradient: const LinearGradient(
                            colors: [Color(0xFF7C3AED), Color(0xFFA78BFA)])),
                  ),
                  const SizedBox(width: 12),
                  ValueListenableBuilder<int>(
                    valueListenable: AdminStore.totalRequests,
                    builder: (_, v, __) => _StatCard(
                        label: 'Demandes',
                        value: '$v',
                        icon: Icons.receipt_long_rounded,
                        gradient: const LinearGradient(
                            colors: [Color(0xFF0EA5E9), Color(0xFF38BDF8)])),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // ── TabBar ────────────────────────────────────────────────────
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 20),
              decoration: BoxDecoration(
                color: const Color(0xFF1E293B),
                borderRadius: BorderRadius.circular(14),
              ),
              child: TabBar(
                controller: _tabController,
                indicator: BoxDecoration(
                  color: AppColors.secondary,
                  borderRadius: BorderRadius.circular(12),
                ),
                labelColor: Colors.white,
                unselectedLabelColor: const Color(0xFF64748B),
                labelStyle:
                    const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                dividerColor: Colors.transparent,
                tabs: const [
                  Tab(text: 'Professionnels'),
                  Tab(text: 'Réclamations'),
                  Tab(text: 'Demandes'),
                  Tab(text: 'Paramètres'),
                ],
              ),
            ),
            const SizedBox(height: 12),

            // ── Tab views ─────────────────────────────────────────────────
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: [
                  _PendingProsTab(),
                  _ReportsTab(),
                  _RequestsTab(),
                  _SettingsTab(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// TAB 1 — Pending Professionals
// ═══════════════════════════════════════════════════════════════════════════
class _PendingProsTab extends StatefulWidget {
  @override
  State<_PendingProsTab> createState() => _PendingProsTabState();
}

class _PendingProsTabState extends State<_PendingProsTab> {
  String _filter = 'all';
  final _queryController = TextEditingController();

  @override
  void dispose() {
    _queryController.dispose();
    super.dispose();
  }

  /// Account lifecycle bucket derived from registry fields.
  String _accountState(PendingProModel p) {
    switch (p.status) {
      case 'pending':
      case 'rejected':
        return 'pending';
      case 'approved':
        if (p.isPaid) return 'paid';
        return p.tokens <= 0 ? 'expired' : 'active';
    }
    return 'pending';
  }

  bool _matchesQuery(PendingProModel p, String q) {
    if (q.isEmpty) return true;
    final needle = q.toLowerCase();
    return (p.proCode ?? '').toLowerCase().contains(needle) ||
        p.name.toLowerCase().contains(needle) ||
        p.phone.toLowerCase().contains(needle);
  }

  /// Full admin detail modal for a single Pro.
  void _showProDetail(BuildContext context, PendingProModel pro) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF0F172A),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.92,
        minChildSize: 0.5,
        maxChildSize: 0.95,
        builder: (_, controller) =>
            ValueListenableBuilder<List<PendingProModel>>(
          valueListenable: AdminStore.pendingPros,
          builder: (_, list, ___) {
            final p =
                list.firstWhere((e) => e.id == pro.id, orElse: () => pro);
            return ListView(
              controller: controller,
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(p.name,
                          style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w800,
                              fontSize: 20)),
                    ),
                    IconButton(
                      onPressed: () => Navigator.pop(context),
                      icon:
                          const Icon(Icons.close_rounded, color: Colors.white),
                    ),
                  ],
                ),
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  children: [
                    if (p.proCode != null)
                      _codeChip(p.proCode!, success: p.isPaid),
                    _stateChip(p),
                    for (final b in p.badges) _badgeChip(b),
                  ],
                ),
                const SizedBox(height: 16),
                Text('${p.professionFr} • ${p.city ?? '-'} • ${p.phone}',
                    style: const TextStyle(color: Color(0xFF94A3B8))),
                const SizedBox(height: 16),
                Text('Preuve de travail',
                    style: TextStyle(
                        color: Colors.white.withValues(alpha: .9),
                        fontWeight: FontWeight.w700)),
                const SizedBox(height: 8),
                Container(
                  height: 260,
                  width: double.infinity,
                  decoration: BoxDecoration(
                    color: Colors.black26,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: p.docImage == null
                      ? const Center(
                          child: Text('Aucune preuve fournie',
                              style: TextStyle(color: Color(0xFF64748B))))
                      : InteractiveViewer(
                          maxScale: 4,
                          child: p.docImage!.startsWith('assets/')
                              ? Image.asset(p.docImage!,
                                  fit: BoxFit.contain)
                              : Image.file(File(p.docImage!),
                                  fit: BoxFit.contain, errorBuilder:
                                      (_, __, ___) => const Center(
                                          child: Text('Preuve illisible',
                                              style: TextStyle(
                                                  color: Color(0xFF64748B)))),
                                  ),
                        ),
                ),
                const SizedBox(height: 20),
                // ── Tokens ──
                Row(
                  children: [
                    const Icon(Icons.toll_rounded,
                        color: AppColors.secondary, size: 20),
                    const SizedBox(width: 8),
                    const Text('Tokens',
                        style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w700)),
                    const Spacer(),
                    IconButton.filledTonal(
                      onPressed: () =>
                          AdminStore.adjustTokens(p.id, -10),
                      icon: const Icon(Icons.remove_rounded,
                          color: Colors.white),
                    ),
                    Padding(
                      padding:
                          const EdgeInsets.symmetric(horizontal: 12),
                      child: Text('${p.tokens}',
                          style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w800,
                              fontSize: 18)),
                    ),
                    IconButton.filledTonal(
                      onPressed: () =>
                          AdminStore.adjustTokens(p.id, 10),
                      icon: const Icon(Icons.add_rounded,
                          color: Colors.white),
                    ),
                  ],
                ),
                const Divider(color: Color(0xFF1E293B), height: 28),

                // ── Unlimited plan ──
                SwitchListTile(
                  value: p.isPaid,
                  onChanged: (v) => AdminStore.setPaid(p.id, isPaid: v),
                  title: const Text('Abonnement illimité (30 jours)',
                      style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w700)),
                  subtitle: const Text(
                      'Confirme sans consommer de tokens',
                      style:
                          TextStyle(color: Color(0xFF94A3B8), fontSize: 12)),
                ),
                const Divider(color: Color(0xFF1E293B), height: 28),

                // ── Badges manuels ──
                Text('Badges manuels',
                    style: TextStyle(
                        color: Colors.white.withValues(alpha: .9),
                        fontWeight: FontWeight.w700)),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  children: [
                    for (final entry in const [
                      ('verified', 'موثّق'),
                      ('master', 'خبير'),
                      ('top_rated', 'الأعلى تقييمًا'),
                    ])
                      FilterChip(
                        selected: p.badges.contains(entry.$1),
                        onSelected: (_) =>
                            AdminStore.toggleBadge(p.id, entry.$1),
                        label: Text(entry.$2),
                        labelStyle: const TextStyle(
                            color: Colors.white, fontSize: 12),
                        backgroundColor: const Color(0xFF1E293B),
                        selectedColor:
                            AppColors.primary.withValues(alpha: .35),
                      ),
                  ],
                ),
                const SizedBox(height: 22),
                // ── Decisions ──
                if (p.status == 'pending' || p.status == 'rejected') ...[
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: () {
                        AdminStore.approvePro(p.id);
                        Navigator.pop(context);
                      },
                      icon: const Icon(Icons.verified_rounded),
                      label: const Text('Approuver le compte'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.success,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: () async {
                        final reasonCtrl = TextEditingController();
                        final reason = await showDialog<String>(
                          context: context,
                          builder: (dlgCtx) => AlertDialog(
                            backgroundColor: const Color(0xFF1E293B),
                            title: const Text('Motif du refus',
                                style: TextStyle(color: Colors.white)),
                            content: TextField(
                              controller: reasonCtrl,
                              maxLines: 3,
                              autofocus: true,
                              style:
                                  const TextStyle(color: Colors.white),
                              decoration: const InputDecoration(
                                hintText: 'Expliquez la raison du refus…',
                                hintStyle: TextStyle(
                                    color: Color(0xFF64748B)),
                              ),
                            ),
                            actions: [
                              TextButton(
                                onPressed: () =>
                                    Navigator.pop(dlgCtx),
                                child: const Text('Annuler'),
                              ),
                              ElevatedButton(
                                onPressed: () => Navigator.pop(
                                    dlgCtx, reasonCtrl.text.trim()),
                                child: const Text('Confirmer'),
                              ),
                            ],
                          ),
                        );
                        if (reason != null && reason.isNotEmpty) {
                          AdminStore.rejectPro(p.id, reason: reason);
                        }
                      },
                      icon: const Icon(Icons.cancel_outlined),
                      label: const Text('Refuser avec motif'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.error,
                        side: BorderSide(
                            color:
                                AppColors.error.withValues(alpha: .5)),
                        padding: const EdgeInsets.symmetric(
                            vertical: 14),
                      ),
                    ),
                  ),
                ] else ...[
                  Center(
                    child: Text(
                      p.status == 'approved'
                          ? 'Compte approuvé ✓ — accès actif'
                          : 'Compte refusé',
                      style: const TextStyle(color: Color(0xFF94A3B8)),
                    ),
                  ),
                ],
                const SizedBox(height: 16),

                // ── Direct WhatsApp ──
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: () {
                      final msg = AdminStore.whatsappMessage(
                        name: p.name,
                        profession: p.professionFr,
                        proCode: p.proCode ?? '-',
                      );
                      final uri = Uri.parse(
                          'https://wa.me/${SubscriptionStore.whatsappNumber}'
                          '?text=${Uri.encodeComponent(msg)}');
                      launchUrl(uri,
                          mode: LaunchMode.externalApplication);
                    },
                    icon: const Icon(Icons.chat_rounded),
                    label: const Text('Contacter via WhatsApp'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.success,
                      side: BorderSide(
                          color:
                              AppColors.success.withValues(alpha: .4)),
                      padding:
                          const EdgeInsets.symmetric(vertical: 12),
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // ── Search ───────────────────────────────────────────────────────
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
          child: TextField(
            controller: _queryController,
            onChanged: (_) => setState(() {}),
            style: const TextStyle(color: Colors.white),
            decoration: InputDecoration(
              hintText: 'PRO-00001 · Nom · Téléphone',
              hintStyle: const TextStyle(color: Color(0xFF64748B)),
              prefixIcon:
                  const Icon(Icons.search_rounded, color: Color(0xFF94A3B8)),
              filled: true,
              fillColor: const Color(0xFF1E293B),
              isDense: true,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide.none,
              ),
            ),
          ),
        ),
        // ── Filter chips ─────────────────────────────────────────────────
        SizedBox(
          height: 40,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 20),
            children: [
              for (final f in ['all', 'pending', 'active', 'paid', 'expired'])
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    label: Text(_filterLabel(f)),
                    selected: _filter == f,
                    selectedColor: AppColors.secondary,
                    labelStyle: TextStyle(
                      color: _filter == f
                          ? Colors.white
                          : const Color(0xFF94A3B8),
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                    ),
                    backgroundColor: const Color(0xFF1E293B),
                    onSelected: (_) => setState(() => _filter = f),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 8),

        // List
        Expanded(
          child: ValueListenableBuilder<List<PendingProModel>>(
            valueListenable: AdminStore.pendingPros,
            builder: (context, list, _) {
              final query = _queryController.text.trim().toLowerCase();
              final filtered = list.where((p) {
                if (_filter != 'all' && _accountState(p) != _filter) {
                  return false;
                }
                return _matchesQuery(p, query);
              }).toList();

              if (filtered.isEmpty) {
                return Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.check_circle_outline_rounded,
                          color: Color(0xFF22C55E), size: 48),
                      const SizedBox(height: 12),
                      Text(
                        _filter == 'pending'
                            ? 'Aucune demande en attente 👌'
                            : 'Aucun résultat',
                        style: const TextStyle(color: Color(0xFF64748B)),
                      ),
                    ],
                  ),
                );
              }

              return ListView.builder(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                itemCount: filtered.length,
                itemBuilder: (_, i) => _ProCard(
                  pro: filtered[i],
                  onOpenDetails: () => _showProDetail(context, filtered[i]),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  String _filterLabel(String f) {
    switch (f) {
      case 'pending':
        return '⏳ En attente';
      case 'active':
        return '🟢 Actifs';
      case 'paid':
        return '💎 Payés';
      case 'expired':
        return '⛔ Expirés';
      default:
        return '📋 Tous';
    }
  }
  Widget _codeChip(String text, {bool success = false}) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: (success ? AppColors.success : AppColors.primary)
              .withValues(alpha: .15),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(
          text,
          style: TextStyle(
            color: success ? AppColors.success : AppColors.primaryLight,
            fontWeight: FontWeight.w700,
            fontSize: 11,
          ),
        ),
      );

  Widget _badgeChip(String b) {
    final label = switch (b) {
      'verified' => 'موثّق',
      'master' => 'خبير',
      'top_rated' => 'الأعلى تقييمًا',
      _ => b,
    };
    return Chip(
      visualDensity: VisualDensity.compact,
      backgroundColor: AppColors.secondary.withValues(alpha: .15),
      side: BorderSide.none,
      label: Text(label,
          style: const TextStyle(color: Colors.white, fontSize: 11)),
    );
  }

  Widget _stateChip(PendingProModel p) {
    final state = _accountState(p);
    final (label, color) = switch (state) {
      'paid' => ('اشتراك مدفوع 💎', AppColors.success),
      'active' => ('نشط 🟢', AppColors.success),
      'expired' => ('منتهي ⛔', AppColors.error),
      _ => p.status == 'rejected'
          ? ('مرفوض ❌', AppColors.error)
          : ('في انتظار التفعيل ⏳', AppColors.warning),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .15),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(label,
          style: TextStyle(
              color: color, fontWeight: FontWeight.bold, fontSize: 11)),
    );
  }
}

class _ProCard extends StatelessWidget {
  const _ProCard({required this.pro, this.onOpenDetails});
  final PendingProModel pro;
  final VoidCallback? onOpenDetails;

  @override
  Widget build(BuildContext context) {
    final statusColor = switch (pro.status) {
      'approved' => const Color(0xFF22C55E),
      'rejected' => const Color(0xFFEF4444),
      _ => const Color(0xFFF59E0B),
    };

    final statusLabel = switch (pro.status) {
      'approved' => 'Approuvé',
      'rejected' => 'Refusé',
      _ => 'En attente',
    };

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: statusColor.withValues(alpha: 0.25)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  radius: 24,
                  backgroundColor: AppColors.primary.withValues(alpha: 0.2),
                  child: Text(
                    pro.name.substring(0, 1).toUpperCase(),
                    style: const TextStyle(
                        color: AppColors.primaryLight,
                        fontWeight: FontWeight.bold,
                        fontSize: 18),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        pro.name,
                        style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 16),
                      ),
                      Text(
                        '${pro.professionFr} • ${pro.city}',
                        style: const TextStyle(
                            color: Color(0xFF94A3B8), fontSize: 13),
                      ),
                    ],
                  ),
                ),
                Row(
                  children: [
                    Container(
                      padding:
                          const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: statusColor.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        statusLabel,
                        style: TextStyle(
                            color: statusColor,
                            fontWeight: FontWeight.bold,
                            fontSize: 11),
                      ),
                    ),
                    const Spacer(),
                    IconButton(
                      onPressed: onOpenDetails,
                      tooltip: 'Détails & gestion',
                      icon: const Icon(Icons.manage_accounts_rounded,
                          size: 20, color: Color(0xFF38BDF8)),
                    ),
                    IconButton(
                      tooltip: 'WhatsApp',
                      onPressed: () {
                        final msg = AdminStore.whatsappMessage(
                          name: pro.name,
                          profession: pro.professionFr,
                          proCode: pro.proCode ?? '-',
                        );
                        final uri = Uri.parse(
                            'https://wa.me/${SubscriptionStore.whatsappNumber}'
                            '?text=${Uri.encodeComponent(msg)}');
                        launchUrl(uri,
                            mode: LaunchMode.externalApplication);
                      },
                      icon: const Icon(Icons.chat_rounded,
                          size: 20, color: AppColors.success),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                if (pro.proCode != null) ...[
                  const Icon(Icons.badge_outlined,
                      size: 14, color: Color(0xFF64748B)),
                  const SizedBox(width: 4),
                  Text(pro.proCode!,
                      style: const TextStyle(
                          color: Color(0xFF94A3B8),
                          fontSize: 12,
                          fontWeight: FontWeight.w700)),
                  const SizedBox(width: 10),
                ],
                const Icon(Icons.phone_outlined,
                    size: 14, color: Color(0xFF64748B)),
                const SizedBox(width: 4),
                Text(pro.phone,
                    style: const TextStyle(
                        color: Color(0xFF94A3B8), fontSize: 12)),
                const Spacer(),
                const Icon(Icons.calendar_today_outlined,
                    size: 14, color: Color(0xFF64748B)),
                const SizedBox(width: 4),
                Text(pro.submittedAt,
                    style: const TextStyle(
                        color: Color(0xFF94A3B8), fontSize: 12)),
              ],
            ),
            if (pro.badges.isNotEmpty) ...[
              const SizedBox(height: 10),
              Wrap(
                spacing: 6,
                children: [
                  for (final b in pro.badges)
                    Chip(
                      visualDensity: VisualDensity.compact,
                      backgroundColor:
                          AppColors.secondary.withValues(alpha: .15),
                      side: BorderSide.none,
                      label: Text(
                        switch (b) {
                          'verified' => 'موثّق',
                          'master' => 'خبير',
                          'top_rated' => 'الأعلى تقييمًا',
                          _ => b,
                        },
                        style: const TextStyle(
                            color: Colors.white, fontSize: 11),
                      ),
                    ),
                ],
              ),
            ],
            if (pro.status == 'pending') ...[
              const SizedBox(height: 14),
              if (pro.docImage != null) ...[
                OutlinedButton.icon(
                  onPressed: () {
                    showDialog(
                      context: context,
                      builder: (_) => AlertDialog(
                        backgroundColor: const Color(0xFF1E293B),
                        title: const Text('Document de vérification',
                            style: TextStyle(color: Colors.white)),
                        content: Container(
                          width: double.maxFinite,
                          height: 300,
                          decoration: BoxDecoration(
                            color: Colors.black26,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Center(
                            child: Icon(Icons.description_rounded,
                                color: AppColors.secondary, size: 64),
                          ),
                        ),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(context),
                            child: const Text('Fermer'),
                          ),
                        ],
                      ),
                    );
                  },
                  icon: const Icon(Icons.visibility_rounded, size: 18),
                  label: const Text('Voir Document'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.secondary,
                    side: const BorderSide(color: AppColors.secondary),
                    minimumSize: const Size(double.infinity, 44),
                  ),
                ),
                const SizedBox(height: 12),
              ],
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () {
                        AdminStore.rejectPro(pro.id);
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                              content: Text('Professionnel refusé.'),
                              backgroundColor: Color(0xFFEF4444)),
                        );
                      },
                      icon: const Icon(Icons.close_rounded,
                          color: Color(0xFFEF4444), size: 18),
                      label: const Text('Refuser',
                          style: TextStyle(color: Color(0xFFEF4444))),
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(color: Color(0xFFEF4444)),
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10)),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: () {
                        _showBadgeSelection(context, pro.id);
                      },
                      icon: const Icon(Icons.check_rounded,
                          color: Colors.white, size: 18),
                      label: const Text('Approuver',
                          style: TextStyle(color: Colors.white)),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF22C55E),
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10)),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  void _showBadgeSelection(BuildContext context, String proId) {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1E293B),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Attribuer un badge',
              style: TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 20),
            _badgeOption(context, proId, 'verified', 'Vérifié', Icons.verified,
                Colors.blue),
            _badgeOption(context, proId, 'expert', 'Expert', Icons.star_rounded,
                Colors.orange),
            _badgeOption(context, proId, 'premium', 'Premium',
                Icons.workspace_premium, Colors.purple),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  Widget _badgeOption(BuildContext context, String proId, String badge,
      String label, IconData icon, Color color) {
    return ListTile(
      leading: Icon(icon, color: color),
      title: Text(label, style: const TextStyle(color: Colors.white)),
      onTap: () {
        AdminStore.approvePro(proId, badge: badge);
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('✅ Professionnel approuvé avec badge $label !'),
            backgroundColor: const Color(0xFF22C55E),
          ),
        );
      },
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// TAB 2 — Reports / Réclamations
// ═══════════════════════════════════════════════════════════════════════════
class _ReportsTab extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<List<ReportModel>>(
      valueListenable: AdminStore.reports,
      builder: (context, list, _) {
        return ListView.builder(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          itemCount: list.length,
          itemBuilder: (_, i) {
            final r = list[i];
            return Container(
              margin: const EdgeInsets.only(bottom: 12),
              decoration: BoxDecoration(
                color: const Color(0xFF1E293B),
                borderRadius: BorderRadius.circular(18),
                border: Border.all(
                  color: r.resolved
                      ? Colors.green.withValues(alpha: 0.2)
                      : Colors.red.withValues(alpha: 0.2),
                ),
              ),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.flag_rounded,
                            color: Color(0xFFEF4444), size: 20),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            r.about,
                            style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold),
                          ),
                        ),
                        if (r.resolved)
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: Colors.green.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: const Text('Résolu',
                                style: TextStyle(
                                    color: Color(0xFF22C55E),
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold)),
                          ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Par: ${r.reportedBy}',
                      style: const TextStyle(
                          color: Color(0xFF64748B), fontSize: 12),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      r.reason,
                      style: const TextStyle(
                          color: Color(0xFF94A3B8), fontSize: 13, height: 1.4),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      r.date,
                      style: const TextStyle(
                          color: Color(0xFF475569), fontSize: 11),
                    ),
                    if (!r.resolved) ...[
                      const SizedBox(height: 12),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          onPressed: () => AdminStore.resolveReport(r.id),
                          icon: const Icon(Icons.done_all_rounded,
                              size: 18, color: Colors.white),
                          label: const Text('Marquer comme résolu',
                              style: TextStyle(color: Colors.white)),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.primary,
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10)),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// TAB 3 — Requests Management
// ═══════════════════════════════════════════════════════════════════════════
class _RequestsTab extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<List<ServiceRequest>>(
      valueListenable: RequestStore.requests,
      builder: (context, requests, _) {
        // Every order carrying (or eligible for) a chat room falls under
        // admin supervision here.
        final chatOrders = requests
            .where(
              (r) =>
                  r.status == RequestStatus.accepted ||
                  r.status == RequestStatus.enRoute ||
                  r.status == RequestStatus.arrived ||
                  r.status == RequestStatus.inProgress,
            )
            .toList();

        if (chatOrders.isEmpty) {
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.receipt_long_rounded,
                    color: Color(0xFF64748B), size: 48),
                const SizedBox(height: 12),
                const Text(
                  'Aucune demande acceptée',
                  style: TextStyle(color: Color(0xFF64748B)),
                ),
              ],
            ),
          );
        }

        return ListView.builder(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          itemCount: chatOrders.length,
          itemBuilder: (_, i) {
            final request = chatOrders[i];
            return Container(
              margin: const EdgeInsets.only(bottom: 12),
              decoration: BoxDecoration(
                color: const Color(0xFF1E293B),
                borderRadius: BorderRadius.circular(18),
                border:
                    Border.all(color: AppColors.primary.withValues(alpha: 0.2)),
              ),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.receipt_long_rounded,
                            color: AppColors.primary, size: 20),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            request.serviceTitleFr,
                            style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold),
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: Colors.green.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Text('Acceptée',
                              style: TextStyle(
                                  color: Color(0xFF22C55E),
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold)),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Client: ${request.customerName}',
                      style: const TextStyle(
                          color: Color(0xFF94A3B8), fontSize: 13),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Pro: ${request.professionalName}',
                      style: const TextStyle(
                          color: Color(0xFF94A3B8), fontSize: 13),
                    ),
                    const SizedBox(height: 12),
                    // ── Admin chat supervision ──
                    ValueListenableBuilder<Map<String, ChatSession>>(
                      valueListenable: ChatStore.sessions,
                      builder: (_, sessions, __) {
                        final session = sessions[request.id];
                        final chatActive = session != null &&
                            session.active &&
                            !session.isExpired;
                        return Row(
                          children: [
                            Icon(
                              chatActive
                                  ? Icons.lock_open_rounded
                                  : Icons.lock_rounded,
                              size: 16,
                              color: chatActive
                                  ? const Color(0xFF22C55E)
                                  : const Color(0xFF64748B),
                            ),
                            const SizedBox(width: 6),
                            Text(
                              chatActive
                                  ? 'Chat actif • fenêtre ${session.expiryHours}h'
                                  : 'Chat clôturé',
                              style: const TextStyle(
                                  color: Color(0xFF94A3B8), fontSize: 12),
                            ),
                            const Spacer(),
                            if (chatActive)
                              TextButton.icon(
                                onPressed: () =>
                                    _confirmCloseChat(context, request.id),
                                icon: const Icon(Icons.block_rounded,
                                    size: 16, color: AppColors.error),
                                label: const Text('Clôturer',
                                    style: TextStyle(
                                        color: AppColors.error,
                                        fontSize: 12,
                                        fontWeight: FontWeight.bold)),
                              ),
                          ],
                        );
                      },
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: () {
                              _showResetDialog(context, request.id);
                            },
                            icon: const Icon(Icons.refresh_rounded, size: 18),
                            label: const Text('Réinitialiser'),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: AppColors.secondary,
                              side:
                                  const BorderSide(color: AppColors.secondary),
                              padding: const EdgeInsets.symmetric(vertical: 10),
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(10)),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  void _showResetDialog(BuildContext context, String requestId) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF1E293B),
        title: const Text('Réinitialiser l\'acceptation',
            style: TextStyle(color: Colors.white)),
        content: const Text(
          'Cela remettra le statut de la demande en attente et déduira 10 tokens supplémentaires du professionnel.',
          style: TextStyle(color: Color(0xFF94A3B8)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Annuler'),
          ),
          ElevatedButton(
            onPressed: () {
              AdminStore.resetRequestAcceptance(requestId);
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Demande réinitialisée avec succès'),
                  backgroundColor: AppColors.success,
                ),
              );
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.secondary,
            ),
            child: const Text('Confirmer'),
          ),
        ],
      ),
    );
  }

  void _confirmCloseChat(BuildContext context, String requestId) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        scrollable: true,
        backgroundColor: const Color(0xFF1E293B),
        title: const Text('Clôturer le chat',
            style: TextStyle(color: Colors.white)),
        content: const Text(
          'Le client et le professionnel ne pourront plus échanger sur cette demande sans une nouvelle confirmation (10 tokens).',
          style: TextStyle(color: Color(0xFF94A3B8)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Annuler'),
          ),
          ElevatedButton(
            onPressed: () {
              ChatStore.closeByAdmin(requestId);
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Chat clôturé'),
                  backgroundColor: AppColors.error,
                ),
              );
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.error,
            ),
            child: const Text('Clôturer'),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// TAB 4 — Settings
// ═══════════════════════════════════════════════════════════════════════════
class _SettingsTab extends StatefulWidget {
  @override
  State<_SettingsTab> createState() => _SettingsTabState();
}

class _SettingsTabState extends State<_SettingsTab> {
  bool _requestsEnabled = true;
  bool _newProEnabled = true;
  bool _maintenanceMode = false;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      children: [
        _SectionHeader(label: 'Contrôle de la plateforme'),
        _ToggleTile(
          icon: Icons.receipt_long_rounded,
          label: 'Réception des demandes',
          subtitle: 'Activer / désactiver les nouvelles demandes',
          value: _requestsEnabled,
          color: AppColors.success,
          onChanged: (v) => setState(() => _requestsEnabled = v),
        ),
        _ToggleTile(
          icon: Icons.person_add_rounded,
          label: 'Inscription des professionnels',
          subtitle: 'Bloquer les nouvelles inscriptions pro',
          value: _newProEnabled,
          color: AppColors.secondary,
          onChanged: (v) => setState(() => _newProEnabled = v),
        ),
        _ToggleTile(
          icon: Icons.construction_rounded,
          label: 'Mode maintenance',
          subtitle: 'Affiche un écran de maintenance aux utilisateurs',
          value: _maintenanceMode,
          color: AppColors.error,
          onChanged: (v) => setState(() => _maintenanceMode = v),
        ),
        const SizedBox(height: 16),
        _SectionHeader(label: 'Chats'),
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Text(
            'Fermeture automatique des conversations après confirmation :',
            style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 13),
          ),
        ),
        ValueListenableBuilder<Map<String, ChatSession>>(
          valueListenable: ChatStore.sessions,
          builder: (_, __, ___) => Row(
            children: [48, 60, 72]
                .map((h) => Expanded(
                      child: Padding(
                        padding: EdgeInsets.only(right: h == 72 ? 0 : 8),
                        child: ChoiceChip(
                          label: Center(
                            child: Text(
                              '${h}h',
                              style: TextStyle(
                                color: ChatStore.expiryHours == h
                                    ? Colors.white
                                    : const Color(0xFF94A3B8),
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          selected: ChatStore.expiryHours == h,
                          selectedColor: AppColors.primary,
                          backgroundColor: const Color(0xFF1E293B),
                          showCheckmark: false,
                          onSelected: (_) =>
                              setState(() => ChatStore.setExpiryHours(h)),
                        ),
                      ),
                    ))
                .toList(),
          ),
        ),
        const SizedBox(height: 16),
        _SectionHeader(label: 'Abonnements'),
        Row(
          children: [
            Expanded(
              child: ElevatedButton.icon(
                onPressed: () {
                  SubscriptionStore.renew();
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Abonnement activé (1 mois illimité)'),
                      backgroundColor: AppColors.success,
                    ),
                  );
                },
                icon: const Icon(Icons.check_circle_rounded, size: 18),
                label: const Text('Activer',
                    style: TextStyle(color: Colors.white)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.success,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10)),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: ElevatedButton.icon(
                onPressed: () {
                  SubscriptionStore.expire();
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Abonnement marqué comme expiré'),
                      backgroundColor: AppColors.error,
                    ),
                  );
                },
                icon: const Icon(Icons.block_rounded, size: 18),
                label: const Text('Expirer',
                    style: TextStyle(color: Colors.white)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.error,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10)),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        _SectionHeader(label: 'Gestion des données'),
        _ActionTile(
          icon: Icons.bar_chart_rounded,
          label: 'Voir les statistiques détaillées',
          subtitle: 'Rapports complets par région / catégorie',
          color: const Color(0xFF0EA5E9),
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => const DetailedStatisticsScreen(),
              ),
            );
          },
        ),
        const SizedBox(height: 16),
        _SectionHeader(label: 'Session'),
        _ActionTile(
          icon: Icons.logout_rounded,
          label: 'Se déconnecter',
          subtitle: 'Quitter la session administrateur',
          color: AppColors.error,
          onTap: () => Navigator.of(context).pop(),
        ),
        const SizedBox(height: 24),
      ],
    );
  }
}

// ─── Shared widgets ──────────────────────────────────────────────────────────

class _StatCard extends StatelessWidget {
  const _StatCard({
    required this.label,
    required this.value,
    required this.icon,
    required this.gradient,
  });

  final String label;
  final String value;
  final IconData icon;
  final LinearGradient gradient;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 140,
      constraints: const BoxConstraints(minHeight: 100),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        gradient: gradient,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: gradient.colors.first.withValues(alpha: 0.3),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: Colors.white, size: 22),
          const Spacer(),
          Text(
            value,
            style: const TextStyle(
                color: Colors.white, fontWeight: FontWeight.w800, fontSize: 18),
          ),
          Text(
            label,
            style: const TextStyle(color: Colors.white70, fontSize: 11),
          ),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10, top: 4),
      child: Text(
        label.toUpperCase(),
        style: const TextStyle(
          color: Color(0xFF64748B),
          fontSize: 11,
          fontWeight: FontWeight.bold,
          letterSpacing: 1.2,
        ),
      ),
    );
  }
}

class _ToggleTile extends StatelessWidget {
  const _ToggleTile({
    required this.icon,
    required this.label,
    required this.subtitle,
    required this.value,
    required this.color,
    required this.onChanged,
  });

  final IconData icon;
  final String label;
  final String subtitle;
  final bool value;
  final Color color;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: color, size: 20),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label,
                    style: const TextStyle(
                        color: Colors.white, fontWeight: FontWeight.w600)),
                Text(subtitle,
                    style: const TextStyle(
                        color: Color(0xFF64748B), fontSize: 11)),
              ],
            ),
          ),
          Switch(
            value: value,
            onChanged: onChanged,
            activeThumbColor: color,
            trackColor: WidgetStateProperty.resolveWith(
              (s) => s.contains(WidgetState.selected)
                  ? color.withValues(alpha: 0.3)
                  : const Color(0xFF334155),
            ),
          ),
        ],
      ),
    );
  }
}

class _ActionTile extends StatelessWidget {
  const _ActionTile({
    required this.icon,
    required this.label,
    required this.subtitle,
    required this.color,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final String subtitle;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: const Color(0xFF1E293B),
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(icon, color: color, size: 20),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(label,
                          style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w600)),
                      Text(subtitle,
                          style: const TextStyle(
                              color: Color(0xFF64748B), fontSize: 11)),
                    ],
                  ),
                ),
                const Icon(Icons.chevron_right_rounded,
                    color: Color(0xFF64748B)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
