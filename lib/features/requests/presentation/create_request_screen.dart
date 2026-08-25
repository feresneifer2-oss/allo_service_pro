import 'package:flutter/material.dart';

import 'package:allo_service_pro/core/theme/app_colors.dart';
import 'package:allo_service_pro/features/auth/application/user_store.dart';
import 'package:allo_service_pro/features/requests/models/service_request.dart';
import 'package:allo_service_pro/features/requests/presentation/confirm_request_screen.dart';
import 'package:allo_service_pro/shared/app_locale.dart';
import 'package:allo_service_pro/shared/widgets/section_title.dart';

class CreateRequestScreen extends StatefulWidget {
  const CreateRequestScreen({
    super.key,
    required this.serviceTitleFr,
    required this.serviceTitleAr,
    required this.professionalId,
    required this.professionalName,
  });

  final String serviceTitleFr;
  final String serviceTitleAr;
  final String professionalId;
  final String professionalName;

  @override
  State<CreateRequestScreen> createState() => _CreateRequestScreenState();
}

class _CreateRequestScreenState extends State<CreateRequestScreen> {
  final _addressController = TextEditingController();
  final _messageController = TextEditingController();
  DateTime? _selectedDate;
  TimeOfDay? _selectedTime;
  final List<String> _photos = [];

  @override
  void dispose() {
    _addressController.dispose();
    _messageController.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final result = await showDatePicker(
      context: context,
      initialDate: now,
      firstDate: now,
      lastDate: now.add(const Duration(days: 60)),
    );
    if (result != null) setState(() => _selectedDate = result);
  }

  Future<void> _pickTime() async {
    final result =
        await showTimePicker(context: context, initialTime: TimeOfDay.now());
    if (result != null) setState(() => _selectedTime = result);
  }

  void _addPhoto() {
    setState(() => _photos.add('photo_${_photos.length + 1}'));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(tr(context,
            fr: 'Photo ajoutée (simulation)', ar: 'تمت إضافة صورة (محاكاة)')),
      ),
    );
  }

  void _continue() {
    if (_selectedDate == null ||
        _selectedTime == null ||
        _addressController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(tr(context,
              fr: 'Remplissez les champs obligatoires',
              ar: 'املأ الحقول المطلوبة')),
        ),
      );
      return;
    }

    final dt = DateTime(
      _selectedDate!.year,
      _selectedDate!.month,
      _selectedDate!.day,
      _selectedTime!.hour,
      _selectedTime!.minute,
    );

    final draft = ServiceRequest(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      serviceTitleFr: widget.serviceTitleFr,
      serviceTitleAr: widget.serviceTitleAr,
      professionalId: widget.professionalId,
      professionalName: widget.professionalName,
      customerName: UserStore.displayName,
      customerId: UserStore.user.value?.id ?? '',
      dateTime: dt,
      address: _addressController.text.trim(),
      message: _messageController.text.trim(),
      photoPaths: List.from(_photos),
      createdAt: DateTime.now(),
    );

    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => ConfirmRequestScreen(request: draft)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final dateText = _selectedDate == null
        ? tr(context, fr: 'Choisir une date', ar: 'اختر تاريخ')
        : '${_selectedDate!.day}/${_selectedDate!.month}/${_selectedDate!.year}';
    final timeText = _selectedTime == null
        ? tr(context, fr: 'Choisir une heure', ar: 'اختر وقت')
        : _selectedTime!.format(context);

    return Scaffold(
      backgroundColor: AppColors.slate900,
      appBar: AppBar(
        backgroundColor: AppColors.slate800,
        title: Text(tr(context, fr: 'Votre demande', ar: 'طلبك'),
            style: const TextStyle(color: Colors.white)),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SectionTitle(
                  title: tr(context, fr: '1. Horaire', ar: '1. الموعد')),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: _PickTile(
                      icon: Icons.calendar_month_rounded,
                      label: tr(context, fr: 'Date', ar: 'التاريخ'),
                      value: dateText,
                      onTap: _pickDate,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _PickTile(
                      icon: Icons.access_time_rounded,
                      label: tr(context, fr: 'Heure', ar: 'الوقت'),
                      value: timeText,
                      onTap: _pickTime,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              SectionTitle(title: tr(context, fr: '2. Lieu', ar: '2. المكان')),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: () => _addressController.text = 'Ariana, Tunisie',
                icon: const Icon(Icons.my_location_rounded,
                    color: AppColors.secondary),
                label: Text(
                    tr(context, fr: 'Position actuelle', ar: 'الموقع الحالي'),
                    style: const TextStyle(color: Colors.white)),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.secondary,
                  side: const BorderSide(color: AppColors.secondary),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _addressController,
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  hintText: tr(context,
                      fr: 'Où se fera le service ?', ar: 'أين ستتم الخدمة؟'),
                  hintStyle: const TextStyle(color: AppColors.slate400),
                  prefixIcon: const Icon(Icons.location_on_rounded,
                      color: AppColors.primary),
                  filled: true,
                  fillColor: AppColors.slate800,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
              const SizedBox(height: 24),
              SectionTitle(
                  title: tr(context, fr: '3. Message', ar: '3. رسالة')),
              const SizedBox(height: 12),
              TextField(
                controller: _messageController,
                maxLines: 4,
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  hintText: tr(
                    context,
                    fr: 'Décrivez brièvement votre besoin…',
                    ar: 'صف احتياجك باختصار…',
                  ),
                  hintStyle: const TextStyle(color: AppColors.slate400),
                  filled: true,
                  fillColor: AppColors.slate800,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
              const SizedBox(height: 24),
              SectionTitle(
                  title: tr(context,
                      fr: '6. Photos (optionnel)', ar: '6. صور (اختياري)')),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: _addPhoto,
                icon: const Icon(Icons.add_a_photo_rounded),
                label: Text(
                    tr(context, fr: 'Ajouter des photos', ar: 'إضافة صور')),
              ),
              if (_photos.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(
                  '${_photos.length} ${tr(context, fr: 'photo(s)', ar: 'صورة')}',
                  style: const TextStyle(color: AppColors.slate400),
                ),
              ],
              const SizedBox(height: 32),
              SizedBox(
                height: 56,
                child: ElevatedButton(
                  onPressed: _continue,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.secondary,
                  ),
                  child: Text(tr(context, fr: 'Continuer', ar: 'متابعة')),
                ),
              ),
              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }
}

class _PickTile extends StatelessWidget {
  const _PickTile({
    required this.icon,
    required this.label,
    required this.value,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final String value;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.slate800,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.primary.withValues(alpha: 0.3)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: AppColors.primary, size: 20),
                const SizedBox(width: 6),
                Text(label,
                    style: const TextStyle(
                        color: Colors.white, fontWeight: FontWeight.w700)),
              ],
            ),
            const SizedBox(height: 6),
            Text(value,
                style: const TextStyle(color: AppColors.slate400, fontSize: 13)),
          ],
        ),
      ),
    );
  }
}
