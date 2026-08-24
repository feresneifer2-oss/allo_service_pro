import 'package:flutter/material.dart';
import 'package:allo_service_pro/core/theme/app_colors.dart';
import 'package:allo_service_pro/core/catalog/services_catalog.dart';
import 'package:allo_service_pro/features/admin/application/category_management_store.dart';
import 'package:allo_service_pro/shared/app_locale.dart';

class CategoryManagementScreen extends StatefulWidget {
  const CategoryManagementScreen({super.key});

  @override
  State<CategoryManagementScreen> createState() =>
      _CategoryManagementScreenState();
}

class _CategoryManagementScreenState extends State<CategoryManagementScreen> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F172A),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0F172A),
        title: Text(
          tr(context, fr: 'Gestion des catégories', ar: 'إدارة الفئات'),
          style: const TextStyle(color: Colors.white),
        ),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: ValueListenableBuilder<List<CatalogCategory>>(
        valueListenable: CategoryManagementStore.categories,
        builder: (context, categories, _) {
          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: categories.length,
            itemBuilder: (context, index) {
              final category = categories[index];
              return _CategoryCard(
                category: category,
                onEdit: () => _showEditCategoryDialog(category),
                onDelete: () => _showDeleteCategoryDialog(category.id),
                onAddType: () => _showAddTypeDialog(category.id),
              );
            },
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showAddCategoryDialog(),
        backgroundColor: AppColors.secondary,
        child: const Icon(Icons.add, color: Colors.white),
      ),
    );
  }

  void _showAddCategoryDialog() {
    final frController = TextEditingController();
    final arController = TextEditingController();
    IconData? selectedIcon;

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        scrollable: true,
        backgroundColor: const Color(0xFF1E293B),
        title: const Text('Ajouter une catégorie',
            style: TextStyle(color: Colors.white)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: frController,
              decoration: const InputDecoration(
                labelText: 'Nom (Français)',
                labelStyle: TextStyle(color: Color(0xFF94A3B8)),
              ),
              style: const TextStyle(color: Colors.white),
            ),
            TextField(
              controller: arController,
              decoration: const InputDecoration(
                labelText: 'Nom (Arabe)',
                labelStyle: TextStyle(color: Color(0xFF94A3B8)),
              ),
              style: const TextStyle(color: Colors.white),
            ),
            const SizedBox(height: 16),
            const Text('Choisir une icône:',
                style: TextStyle(color: Color(0xFF94A3B8))),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: [
                Icons.home_rounded,
                Icons.directions_car_rounded,
                Icons.health_and_safety_rounded,
                Icons.brush_rounded,
                Icons.school_rounded,
                Icons.computer_rounded,
                Icons.restaurant_rounded,
                Icons.construction_rounded,
                Icons.pets_rounded,
                Icons.business_rounded,
              ].map((icon) {
                return IconButton(
                  icon: Icon(icon),
                  color:
                      selectedIcon == icon ? AppColors.secondary : Colors.grey,
                  onPressed: () {
                    setState(() => selectedIcon = icon);
                    Navigator.pop(context);
                    _showAddCategoryDialog();
                  },
                );
              }).toList(),
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
              if (frController.text.isNotEmpty &&
                  arController.text.isNotEmpty &&
                  selectedIcon != null) {
                CategoryManagementStore.addCategory(
                  CatalogCategory(
                    id: DateTime.now().millisecondsSinceEpoch.toString(),
                    icon: selectedIcon!,
                    fr: frController.text,
                    ar: arController.text,
                    types: [],
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

  void _showEditCategoryDialog(CatalogCategory category) {
    final frController = TextEditingController(text: category.fr);
    final arController = TextEditingController(text: category.ar);

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        scrollable: true,
        backgroundColor: const Color(0xFF1E293B),
        title: const Text('Modifier la catégorie',
            style: TextStyle(color: Colors.white)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: frController,
              decoration: const InputDecoration(
                labelText: 'Nom (Français)',
                labelStyle: TextStyle(color: Color(0xFF94A3B8)),
              ),
              style: const TextStyle(color: Colors.white),
            ),
            TextField(
              controller: arController,
              decoration: const InputDecoration(
                labelText: 'Nom (Arabe)',
                labelStyle: TextStyle(color: Color(0xFF94A3B8)),
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
              if (frController.text.isNotEmpty &&
                  arController.text.isNotEmpty) {
                CategoryManagementStore.updateCategory(
                  category.id,
                  CatalogCategory(
                    id: category.id,
                    icon: category.icon,
                    fr: frController.text,
                    ar: arController.text,
                    types: category.types,
                  ),
                );
                Navigator.pop(context);
              }
            },
            style:
                ElevatedButton.styleFrom(backgroundColor: AppColors.secondary),
            child: const Text('Modifier'),
          ),
        ],
      ),
    );
  }

  void _showDeleteCategoryDialog(String categoryId) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        scrollable: true,
        backgroundColor: const Color(0xFF1E293B),
        title: const Text('Supprimer la catégorie',
            style: TextStyle(color: Colors.white)),
        content: const Text(
          'Êtes-vous sûr de vouloir supprimer cette catégorie?',
          style: TextStyle(color: Color(0xFF94A3B8)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Annuler'),
          ),
          ElevatedButton(
            onPressed: () {
              CategoryManagementStore.deleteCategory(categoryId);
              Navigator.pop(context);
            },
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.error),
            child: const Text('Supprimer'),
          ),
        ],
      ),
    );
  }

  void _showAddTypeDialog(String categoryId) {
    final frController = TextEditingController();
    final arController = TextEditingController();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        scrollable: true,
        backgroundColor: const Color(0xFF1E293B),
        title: const Text('Ajouter un type de service',
            style: TextStyle(color: Colors.white)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: frController,
              decoration: const InputDecoration(
                labelText: 'Nom (Français)',
                labelStyle: TextStyle(color: Color(0xFF94A3B8)),
              ),
              style: const TextStyle(color: Colors.white),
            ),
            TextField(
              controller: arController,
              decoration: const InputDecoration(
                labelText: 'Nom (Arabe)',
                labelStyle: TextStyle(color: Color(0xFF94A3B8)),
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
              if (frController.text.isNotEmpty &&
                  arController.text.isNotEmpty) {
                CategoryManagementStore.addTypeToCategory(
                  categoryId,
                  CatalogType(
                    id: DateTime.now().millisecondsSinceEpoch.toString(),
                    fr: frController.text,
                    ar: arController.text,
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
}

class _CategoryCard extends StatelessWidget {
  final CatalogCategory category;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final VoidCallback onAddType;

  const _CategoryCard({
    required this.category,
    required this.onEdit,
    required this.onDelete,
    required this.onAddType,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.secondary.withValues(alpha: 0.2)),
      ),
      child: ExpansionTile(
        iconColor: AppColors.secondary,
        collapsedIconColor: AppColors.secondary,
        leading: Icon(category.icon, color: AppColors.secondary),
        title: Text(
          category.fr,
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
          ),
        ),
        subtitle: Text(
          category.ar,
          style: const TextStyle(color: Color(0xFF94A3B8)),
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            InkWell(
              onTap: onEdit,
              child: Container(
                padding: const EdgeInsets.all(8),
                child: const Icon(Icons.edit,
                    size: 20, color: AppColors.secondary),
              ),
            ),
            InkWell(
              onTap: onDelete,
              child: Container(
                padding: const EdgeInsets.all(8),
                child:
                    const Icon(Icons.delete, size: 20, color: AppColors.error),
              ),
            ),
          ],
        ),
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'Types de services:',
                      style: TextStyle(
                        color: Color(0xFF94A3B8),
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    TextButton.icon(
                      onPressed: onAddType,
                      icon: const Icon(Icons.add, size: 16),
                      label: const Text('Ajouter'),
                      style: TextButton.styleFrom(
                        foregroundColor: AppColors.secondary,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                if (category.types.isEmpty)
                  const Text(
                    'Aucun type de service',
                    style: TextStyle(color: Color(0xFF64748B)),
                  )
                else
                  ...category.types.map((type) => Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: Row(
                          children: [
                            const Icon(Icons.circle,
                                size: 8, color: AppColors.secondary),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                '${type.fr} / ${type.ar}',
                                style:
                                    const TextStyle(color: Color(0xFF94A3B8)),
                              ),
                            ),
                            IconButton(
                              icon: const Icon(Icons.close, size: 16),
                              color: AppColors.error,
                              onPressed: () {
                                CategoryManagementStore.removeTypeFromCategory(
                                  category.id,
                                  type.id,
                                );
                              },
                            ),
                          ],
                        ),
                      )),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
