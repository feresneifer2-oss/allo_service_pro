class BookingModel {
  final String id;
  final String serviceTitle;
  final String professionalName;
  final String address;
  final DateTime dateTime;
  final String note;
  final String status;

  const BookingModel({
    required this.id,
    required this.serviceTitle,
    required this.professionalName,
    required this.address,
    required this.dateTime,
    required this.note,
    this.status = 'pending',
  });
}