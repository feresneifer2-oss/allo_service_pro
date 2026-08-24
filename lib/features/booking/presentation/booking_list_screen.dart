import 'package:flutter/material.dart';

import 'package:allo_service_pro/shared/app_locale.dart';
import 'package:allo_service_pro/features/booking/application/booking_store.dart';
import 'package:allo_service_pro/features/booking/models/booking_model.dart';

class BookingListScreen extends StatelessWidget {
  const BookingListScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        title: Text(tr(context, fr: "Bookings", ar: "الحجوزات")),
        actions: [
          IconButton(
            onPressed: () {
              BookingStore.clear();
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                    tr(context, fr: "Bookings cleared.", ar: "تم حذف كل الحجوزات."),
                  ),
                ),
              );
            },
            icon: const Icon(Icons.delete_outline_rounded),
            tooltip: "Clear",
          ),
        ],
      ),
      body: SafeArea(
        child: ValueListenableBuilder<List<BookingModel>>(
          valueListenable: BookingStore.bookings,
          builder: (context, items, _) {
            if (items.isEmpty) {
              return Center(
                child: Text(
                  tr(context, fr: "No bookings yet.", ar: "لا توجد حجوزات بعد."),
                  style: const TextStyle(color: Color(0xFF64748B)),
                ),
              );
            }

            return ListView.builder(
              padding: const EdgeInsets.all(20),
              itemCount: items.length,
              itemBuilder: (_, i) {
                final b = items[i];
                return _BookingTile(booking: b);
              },
            );
          },
        ),
      ),
    );
  }
}

class _BookingTile extends StatelessWidget {
  const _BookingTile({required this.booking});

  final BookingModel booking;

  @override
  Widget build(BuildContext context) {
    final dt = booking.dateTime;
    final dateText = "${dt.day}/${dt.month}/${dt.year}";
    final timeText =
        "${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}";

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(.04),
            blurRadius: 12,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: const Color(0xFFEFF6FF),
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Icon(
              Icons.receipt_long_rounded,
              color: Color(0xFF2563EB),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  booking.serviceTitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF1E293B),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  booking.professionalName,
                  style: const TextStyle(color: Color(0xFF64748B)),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 6),
                Text(
                  "$dateText • $timeText",
                  style: const TextStyle(color: Color(0xFF64748B)),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          IconButton(
            onPressed: () {
              BookingStore.removeById(booking.id);
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                    tr(context, fr: "Booking removed.", ar: "تم حذف الحجز."),
                  ),
                ),
              );
            },
            icon: const Icon(Icons.close_rounded),
            tooltip: "Remove",
          ),
        ],
      ),
    );
  }
}