import 'package:flutter/material.dart';
import 'package:allo_service_pro/core/theme/app_colors.dart';

import 'package:allo_service_pro/shared/app_locale.dart';
import 'package:allo_service_pro/shared/widgets/section_title.dart';

import 'package:allo_service_pro/features/booking/application/booking_store.dart';
import 'package:allo_service_pro/features/booking/models/booking_model.dart';

class BookingScreen extends StatefulWidget {
  const BookingScreen({
    super.key,
    required this.serviceTitle,
    required this.professionalName,
  });

  final String serviceTitle;
  final String professionalName;

  @override
  State<BookingScreen> createState() => _BookingScreenState();
}

class _BookingScreenState extends State<BookingScreen> {
  final _addressController = TextEditingController();
  final _noteController = TextEditingController();

  DateTime? _selectedDate;
  TimeOfDay? _selectedTime;

  @override
  void dispose() {
    _addressController.dispose();
    _noteController.dispose();
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
    if (result == null) return;
    setState(() => _selectedDate = result);
  }

  Future<void> _pickTime() async {
    final result = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.now(),
    );
    if (result == null) return;
    setState(() => _selectedTime = result);
  }

  void _confirm() {
    if (_addressController.text.trim().isEmpty ||
        _selectedDate == null ||
        _selectedTime == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            tr(
              context,
              fr: "Veuillez remplir tous les champs requis.",
              ar: "يرجى ملء جميع الحقول المطلوبة.",
            ),
          ),
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

    final booking = BookingModel(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      serviceTitle: widget.serviceTitle,
      professionalName: widget.professionalName,
      address: _addressController.text.trim(),
      dateTime: dt,
      note: _noteController.text.trim(),
    );

    BookingStore.add(booking);

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
            tr(context, fr: "Réservation effectuée.", ar: "تم إنشاء الحجز.")),
      ),
    );

    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final dateText = _selectedDate == null
        ? tr(context, fr: "Choisir une date", ar: "اختر تاريخا")
        : "${_selectedDate!.day}/${_selectedDate!.month}/${_selectedDate!.year}";

    final timeText = _selectedTime == null
        ? tr(context, fr: "Choisir une heure", ar: "اختر وقتا")
        : _selectedTime!.format(context);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text(tr(context, fr: "Réservation", ar: "الحجز")),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            SectionTitle(title: tr(context, fr: "Détails", ar: "التفاصيل")),
            const SizedBox(height: 12),
            _InfoRow(
              label: tr(context, fr: "Service", ar: "الخدمة"),
              value: widget.serviceTitle,
            ),
            const SizedBox(height: 8),
            _InfoRow(
              label: tr(context, fr: "Professionnel", ar: "المحترف"),
              value: widget.professionalName,
            ),
            const SizedBox(height: 24),
            SectionTitle(title: tr(context, fr: "Adresse", ar: "العنوان")),
            const SizedBox(height: 12),
            TextField(
              controller: _addressController,
              decoration: InputDecoration(
                hintText: tr(context, fr: "Votre adresse", ar: "عنوانك"),
                prefixIcon: const Icon(Icons.location_on_rounded),
              ),
            ),
            const SizedBox(height: 24),
            SectionTitle(title: tr(context, fr: "Rendez-vous", ar: "الموعد")),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _PickCard(
                    title: tr(context, fr: "Date", ar: "التاريخ"),
                    value: dateText,
                    icon: Icons.calendar_month_rounded,
                    onTap: _pickDate,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _PickCard(
                    title: tr(context, fr: "Heure", ar: "الوقت"),
                    value: timeText,
                    icon: Icons.access_time_rounded,
                    onTap: _pickTime,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),
            SectionTitle(
              title:
                  tr(context, fr: "Note (optionnelle)", ar: "ملاحظة (اختياري)"),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _noteController,
              maxLines: 3,
              decoration: InputDecoration(
                hintText: tr(
                  context,
                  fr: "Ajouter une note pour le professionnel...",
                  ar: "اكتب ملاحظة للمحترف...",
                ),
              ),
            ),
            const SizedBox(height: 28),
            SizedBox(
              height: 56,
              child: ElevatedButton(
                onPressed: _confirm,
                child: Text(tr(context,
                    fr: "Confirmer la réservation", ar: "تأكيد الحجز")),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Text(
            "$label: ",
            style: const TextStyle(
              fontWeight: FontWeight.w800,
              color: AppColors.slate800,
            ),
          ),
          Expanded(
            child: Text(
              value,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: AppColors.textSecondary),
            ),
          ),
        ],
      ),
    );
  }
}

class _PickCard extends StatelessWidget {
  const _PickCard({
    required this.title,
    required this.value,
    required this.icon,
    required this.onTap,
  });

  final String title;
  final String value;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          children: [
            Icon(icon, color: AppColors.blue600),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      color: AppColors.slate800,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    value,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 12.5,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
