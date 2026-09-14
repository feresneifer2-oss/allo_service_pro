import 'package:flutter/material.dart';
import 'package:allo_service_pro/core/data/services_catalog.dart';
import 'package:allo_service_pro/core/location/location_service.dart';
import 'package:allo_service_pro/core/theme/app_colors.dart';

import 'package:allo_service_pro/shared/app_locale.dart';
import 'package:allo_service_pro/shared/widgets/section_title.dart';
import 'package:allo_service_pro/features/auth/application/user_store.dart';
import 'package:allo_service_pro/features/professionals/data/professionals_repository.dart';
import 'package:allo_service_pro/features/professionals/models/professional_model.dart';
import 'package:allo_service_pro/features/requests/application/request_store.dart';
import 'package:allo_service_pro/features/requests/models/service_request.dart';
import 'package:allo_service_pro/features/requests/presentation/request_sent_screen.dart';

/// Unified booking flow (Urban Company style): every confirmation creates a
/// real [ServiceRequest] in [RequestStore] so the professional receives the
/// order on their dashboard and can accept or decline it — exactly like the
/// `CreateRequestScreen` path.
class BookingScreen extends StatefulWidget {
  const BookingScreen({
    super.key,
    required this.serviceTitleFr,
    required this.serviceTitleAr,
    this.professionalId,
    this.professionalName = '',
  });

  final String serviceTitleFr;
  final String serviceTitleAr;

  /// Null → the best-rated available professional is auto-assigned.
  final String? professionalId;
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
  void initState() {
    super.initState();
    _autoFillAddress();
  }

  /// Whether the manual-entry SnackBar was already shown for this screen.
  bool _manualNoticeShown = false;

  /// GPS auto-fill: prefill the address from the resolved location and
  /// keep listening in case the startup detection completes while this
  /// screen is open. The user can always edit/overwrite manually.
  void _autoFillAddress() {
    final detected = LocationService.resolvedAddress.value;
    if (detected != null && _addressController.text.trim().isEmpty) {
      _addressController.text = detected;
    }
    LocationService.resolvedAddress.addListener(_onAddressResolved);
    LocationService.manualFallbackNotice.addListener(_onManualFallbackNotice);
    // Startup detection may not have run yet (permission dismissed) —
    // retry quietly so this screen still gets an address when possible.
    LocationService.instance.ensureDetected();
  }

  /// Real GPS fetch for the "Utiliser ma position" action: full
  /// permission pipeline + reverse geocoding. On failure the field stays
  /// EMPTY for manual typing and the fallback SnackBar appears — NEVER a
  /// hardcoded address.
  Future<void> _useCurrentLocation() async {
    final address = await LocationService.instance.requestFreshLocation();
    if (!mounted) return;
    if (address != null && address.isNotEmpty) {
      setState(() {
        _addressController.text = address;
        LocationService.resolvedAddress.value = address;
      });
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(tr(
            context,
            fr: 'Localisation indisponible — vous pouvez saisir votre adresse manuellement.',
            ar: 'الموقع غير متاح — يمكنك كتابة العنوان يدوياً.',
          )),
        ),
      );
    }
  }

  void _onAddressResolved() {
    final value = LocationService.resolvedAddress.value;
    if (value == null || !mounted) return;
    if (_addressController.text.trim().isEmpty) {
      setState(() => _addressController.text = value);
    }
  }

  /// Denial fallback UX: when location is unavailable (permission denied
  /// or GPS off) show one clean SnackBar and leave the field open for
  /// manual typing — never block or crash.
  void _onManualFallbackNotice() {
    if (_manualNoticeShown || !mounted) return;
    if (!LocationService.manualFallbackNotice.value) return;
    if (LocationService.resolvedAddress.value != null) return;
    _manualNoticeShown = true;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(tr(
          context,
          fr: 'Localisation indisponible — vous pouvez saisir votre adresse manuellement.',
          ar: 'الموقع غير متاح — يمكنك كتابة العنوان يدوياً.',
        )),
      ),
    );
  }

  @override
  void dispose() {
    LocationService.resolvedAddress.removeListener(_onAddressResolved);
    LocationService.manualFallbackNotice
        .removeListener(_onManualFallbackNotice);
    _addressController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  ProfessionalModel? _assignedPro;

  /// Resolves the professional for this booking ONCE and caches the result,
  /// so the pro shown in the summary card is EXACTLY the pro stored on the
  /// created [ServiceRequest] — the assigned identity can never drift or
  /// end up empty between the preview and the confirm tap.
  ///
  /// Assignment rules (strict by specialty):
  /// 1. An explicitly chosen pro (user tapped a card) is always preserved.
  /// 2. Otherwise the requested service is mapped back to its catalog entry
  ///    and ONLY pros actually offering that exact specialty are eligible
  ///    (serviceIds match / profession label matches the catalog) — never a
  ///    cross-specialty mismatch (e.g. an electrician sent for a plumber).
  /// 3. Safety net: any available pro, then any pro at all.
  ProfessionalModel get _resolvedPro => _assignedPro ??= _pickProfessional();

  ProfessionalModel _pickProfessional() {
    final explicit = widget.professionalId;
    if (explicit != null && explicit.isNotEmpty) {
      final byId = ProfessionalsRepository.byId(explicit);
      if (byId != null) return byId;
    }

    final wanted = _catalogItemFor(
        widget.serviceTitleFr, widget.serviceTitleAr);
    if (wanted != null) {
      final matching = ProfessionalsRepository.forService(wanted.id)
          .where((p) => p.availableNow)
          .toList()
        ..sort((a, b) => b.rating.compareTo(a.rating));
      if (matching.isNotEmpty) return matching.first;
    }

    final available = ProfessionalsRepository.all
        .where((p) => p.availableNow)
        .toList()
      ..sort((a, b) => b.rating.compareTo(a.rating));
    return available.isNotEmpty ? available.first : ProfessionalsRepository.all.first;
  }

  /// Matches the requested service titles to a catalog entry (FR compared
  /// case/whitespace-insensitively, AR exact). Returns null for free-form
  /// labels that have no catalog item — assignment then falls back to the
  /// generic available pool.
  ServiceItem? _catalogItemFor(String titleFr, String titleAr) {
    final fr = titleFr.trim().toLowerCase();
    final ar = titleAr.trim();
    if (fr.isEmpty && ar.isEmpty) return null;

    for (final s in AppServicesCatalog.services) {
      if ((fr.isNotEmpty && s.nameFr.trim().toLowerCase() == fr) ||
          (ar.isNotEmpty && s.nameAr.trim() == ar)) {
        return s;
      }
    }
    // Fuzzy FR fallback: the requested words must ALL be contained in one
    // catalog name (avoids matching unrelated services).
    final words = fr.split(RegExp(r'\s+')).where((w) => w.length >= 3).toList();
    for (final s in AppServicesCatalog.services) {
      final name = s.nameFr.toLowerCase();
      if (words.isNotEmpty && words.every(name.contains)) {
        return s;
      }
    }
    return null;
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

    final pro = _resolvedPro;
    // The resolved assignment is stored RIGHT NOW on the request: the id is
    // never null/empty and is the SAME pro shown in the summary card above
    // (cached in _resolvedPro), so the order can always be traced back to
    // the intended professional even after a rebuild or navigation change.
    // Strict guard: an explicitly-passed-but-EMPTY id (e.g. from a stale
    // widget reconstruction) must never win over the cached resolution.
    final resolvedProId =
        (widget.professionalId != null && widget.professionalId!.isNotEmpty)
            ? widget.professionalId!
            : pro.id;
    final proName = widget.professionalName.isNotEmpty
        ? widget.professionalName
        : pro.name;

    final request = ServiceRequest(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      serviceTitleFr: widget.serviceTitleFr,
      serviceTitleAr: widget.serviceTitleAr,
      professionalId: resolvedProId,
      professionalName: proName,
      customerName: UserStore.displayName,
      customerId: UserStore.user.value?.id ?? '',
      dateTime: dt,
      address: _addressController.text.trim(),
      message: _noteController.text.trim(),
      createdAt: DateTime.now(),
    );

    // Real request → the pro dashboard can accept / decline it and the
    // chat + notification flows light up exactly like the profile path.
    RequestStore.add(request);

    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (_) => RequestSentScreen(requestId: request.id)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final dateText = _selectedDate == null
        ? tr(context, fr: "Choisir une date", ar: "اختر تاريخا")
        : "${_selectedDate!.day}/${_selectedDate!.month}/${_selectedDate!.year}";

    final timeText = _selectedTime == null
        ? tr(context, fr: "Choisir une heure", ar: "اختر وقتا")
        : _selectedTime!.format(context);

    final pro = _resolvedPro;
    final proLabel = widget.professionalName.isNotEmpty
        ? widget.professionalName
        : '${pro.name} · ⭐ ${pro.rating.toStringAsFixed(1)}';

    return Scaffold(
      resizeToAvoidBottomInset: true,
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text(tr(context, fr: "Réservation", ar: "الحجز")),
      ),
      body: SafeArea(
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          padding: const EdgeInsets.all(20),
          children: [
            SectionTitle(title: tr(context, fr: "Détails", ar: "التفاصيل")),
            const SizedBox(height: 12),
            _InfoRow(
              label: tr(context, fr: "Service", ar: "الخدمة"),
              value: tr(
                context,
                fr: widget.serviceTitleFr,
                ar: widget.serviceTitleAr,
              ),
            ),
            const SizedBox(height: 8),
            _InfoRow(
              label: tr(context, fr: "Professionnel", ar: "المحترف"),
              value: proLabel,
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
            // Real GPS fetch with explicit permission handling — empty
            // field + SnackBar fallback when denied, never a fake address.
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: TextButton.icon(
                onPressed: _useCurrentLocation,
                icon: const Icon(Icons.my_location_rounded, size: 18),
                label: Text(
                  tr(context,
                      fr: 'Utiliser ma position actuelle',
                      ar: 'استعمل موقعي الحالي'),
                ),
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
