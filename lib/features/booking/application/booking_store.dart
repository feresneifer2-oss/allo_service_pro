import 'package:flutter/material.dart';
import '../models/booking_model.dart';

class BookingStore {
  BookingStore._();

  static final bookings = ValueNotifier<List<BookingModel>>([]);

  static void add(BookingModel booking) {
    final current = List<BookingModel>.from(bookings.value);
    current.insert(0, booking);
    bookings.value = current;
  }

  static void removeById(String id) {
    bookings.value = bookings.value.where((b) => b.id != id).toList();
  }

  static void clear() {
    bookings.value = [];
  }
}