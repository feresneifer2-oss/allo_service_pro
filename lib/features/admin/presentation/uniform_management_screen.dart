import 'package:flutter/material.dart';
import 'package:allo_service_pro/core/theme/app_colors.dart';
import 'package:allo_service_pro/features/admin/application/uniform_management_store.dart';
import 'package:allo_service_pro/shared/app_locale.dart';

class UniformManagementScreen extends StatefulWidget {
  const UniformManagementScreen({super.key});

  @override
  State<UniformManagementScreen> createState() =>
      _UniformManagementScreenState();
}

class _UniformManagementScreenState extends State<UniformManagementScreen> {
  String _filter = 'all'; // 'all', 'pending', 'shipped', 'delivered'

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.slate900,
      appBar: AppBar(
        backgroundColor: AppColors.slate800,
        title: Text(
          tr(context, fr: 'Attribution des uniformes', ar: 'توزيع الزي الرسمي'),
          style: const TextStyle(color: Colors.white, fontSize: 18),
        ),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: Column(
        children: [
          // Filter chips
          Container(
            height: 50,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: [
                _FilterChip(
                  label: tr(context, fr: 'Tous', ar: 'الكل'),
                  isSelected: _filter == 'all',
                  onTap: () => setState(() => _filter = 'all'),
                ),
                _FilterChip(
                  label: tr(context, fr: 'En attente', ar: 'في الانتظار'),
                  isSelected: _filter == 'pending',
                  onTap: () => setState(() => _filter = 'pending'),
                ),
                _FilterChip(
                  label: tr(context, fr: 'Expédié', ar: 'مرسل'),
                  isSelected: _filter == 'shipped',
                  onTap: () => setState(() => _filter = 'shipped'),
                ),
                _FilterChip(
                  label: tr(context, fr: 'Livré', ar: 'مستلم'),
                  isSelected: _filter == 'delivered',
                  onTap: () => setState(() => _filter = 'delivered'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          // List
          Expanded(
            child: ValueListenableBuilder<List<UniformRequest>>(
              valueListenable: UniformManagementStore.uniformRequests,
              builder: (context, requests, _) {
                List<UniformRequest> filteredRequests;
                switch (_filter) {
                  case 'pending':
                    filteredRequests = UniformManagementStore.pendingRequests;
                    break;
                  case 'shipped':
                    filteredRequests = UniformManagementStore.shippedRequests;
                    break;
                  case 'delivered':
                    filteredRequests = UniformManagementStore.deliveredRequests;
                    break;
                  default:
                    filteredRequests = requests;
                }

                if (filteredRequests.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.workspace_premium_rounded,
                          color: AppColors.textSecondary,
                          size: 48,
                        ),
                        const SizedBox(height: 12),
                        Text(
                          tr(context, fr: 'Aucune demande', ar: 'لا طلبات'),
                          style: const TextStyle(color: AppColors.textSecondary),
                        ),
                      ],
                    ),
                  );
                }

                return ListView.builder(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 80),
                  itemCount: filteredRequests.length,
                  itemBuilder: (context, index) {
                    final request = filteredRequests[index];
                    return _UniformRequestCard(
                      request: request,
                      onStatusChange: (status) {
                        UniformManagementStore.updateStatus(request.id, status);
                      },
                      onDelete: () {
                        _showDeleteDialog(request.id);
                      },
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showAddUniformDialog(),
        backgroundColor: AppColors.secondary,
        child: const Icon(Icons.add, color: Colors.white),
      ),
    );
  }

  void _showAddUniformDialog() {
    final proNameController = TextEditingController();
    final addressController = TextEditingController();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        scrollable: true,
        backgroundColor: AppColors.slate800,
        title: const Text('Nouvelle demande d\'uniforme',
            style: TextStyle(color: Colors.white)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: proNameController,
              decoration: const InputDecoration(
                labelText: 'Nom du professionnel',
                labelStyle: TextStyle(color: AppColors.slate400),
              ),
              style: const TextStyle(color: Colors.white),
            ),
            TextField(
              controller: addressController,
              decoration: const InputDecoration(
                labelText: 'Adresse de livraison',
                labelStyle: TextStyle(color: AppColors.slate400),
              ),
              style: const TextStyle(color: Colors.white),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Annuler'),
          ),
          ElevatedButton(
            onPressed: () {
              if (proNameController.text.isNotEmpty &&
                  addressController.text.isNotEmpty) {
                UniformManagementStore.addUniformRequest(
                  UniformRequest(
                    id: DateTime.now().millisecondsSinceEpoch.toString(),
                    proName: proNameController.text,
                    proId: 'pro_${DateTime.now().millisecondsSinceEpoch}',
                    address: addressController.text,
                    status: 'pending',
                    requestedAt: DateTime.now(),
                  ),
                );
                Navigator.pop(context);
              }
            },
            style:
                ElevatedButton.styleFrom(backgroundColor: AppColors.secondary),
            child: const Text('Ajouter'),
          ),
        ],
      ),
    );
  }

  void _showDeleteDialog(String requestId) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.slate800,
        title: const Text('Supprimer la demande',
            style: TextStyle(color: Colors.white)),
        content: const Text(
          'Êtes-vous sûr de vouloir supprimer cette demande?',
          style: TextStyle(color: AppColors.slate400),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Annuler'),
          ),
          ElevatedButton(
            onPressed: () {
              UniformManagementStore.deleteRequest(requestId);
              Navigator.pop(context);
            },
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.error),
            child: const Text('Supprimer'),
          ),
        ],
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  const _FilterChip({
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: FilterChip(
        label: Text(label),
        selected: isSelected,
        onSelected: (_) => onTap(),
        selectedColor: AppColors.secondary,
        labelStyle: TextStyle(
          color: isSelected ? Colors.white : AppColors.slate400,
          fontWeight: FontWeight.bold,
          fontSize: 14,
        ),
        backgroundColor: AppColors.slate800,
        checkmarkColor: Colors.white,
      ),
    );
  }
}

class _UniformRequestCard extends StatelessWidget {
  final UniformRequest request;
  final Function(String) onStatusChange;
  final VoidCallback onDelete;

  const _UniformRequestCard({
    required this.request,
    required this.onStatusChange,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final statusColor = switch (request.status) {
      'pending' => AppColors.warning,
      'shipped' => const Color(0xFF3B82F6),
      'delivered' => AppColors.success,
      _ => AppColors.textSecondary,
    };

    final statusLabel = switch (request.status) {
      'pending' => 'En attente',
      'shipped' => 'Expédié',
      'delivered' => 'Livré',
      _ => 'Inconnu',
    };

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: AppColors.slate800,
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
                const Icon(Icons.workspace_premium_rounded,
                    color: AppColors.secondary, size: 24),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        request.proName,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 18,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        request.address,
                        style: const TextStyle(
                          color: AppColors.slate400,
                          fontSize: 14,
                        ),
                      ),
                    ],
                  ),
                ),
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
                      fontSize: 11,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.calendar_today_outlined,
                        size: 16, color: AppColors.textSecondary),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        'Demandé le: ${request.requestedAt.day}/${request.requestedAt.month}/${request.requestedAt.year}',
                        style: const TextStyle(
                            color: AppColors.slate400, fontSize: 13),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
                if (request.shippedAt != null) ...[
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      const Icon(Icons.local_shipping_outlined,
                          size: 16, color: AppColors.textSecondary),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          'Expédié le: ${request.shippedAt!.day}/${request.shippedAt!.month}/${request.shippedAt!.year}',
                          style: const TextStyle(
                              color: AppColors.slate400, fontSize: 13),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
            const SizedBox(height: 12),
            if (request.status == 'pending')
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: () => onStatusChange('shipped'),
                      icon: const Icon(Icons.local_shipping, size: 16),
                      label: const Text('Expédier'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF3B82F6),
                        padding: const EdgeInsets.symmetric(vertical: 10),
                      ),
                    ),
                  ),
                ],
              )
            else if (request.status == 'shipped')
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: () => onStatusChange('delivered'),
                      icon: const Icon(Icons.check_circle, size: 16),
                      label: const Text('Marquer livré'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.success,
                        padding: const EdgeInsets.symmetric(vertical: 10),
                      ),
                    ),
                  ),
                ],
              ),
            Row(
              children: [
                Expanded(
                  child: TextButton.icon(
                    onPressed: onDelete,
                    icon: const Icon(Icons.delete, size: 16),
                    label: const Text('Supprimer'),
                    style: TextButton.styleFrom(
                      foregroundColor: AppColors.error,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
