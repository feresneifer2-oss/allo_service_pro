enum RequestStatus {
  pending,
  accepted,
  refused,
  enRoute,
  arrived,
  inProgress,
  completed,
  cancelled,
}

extension RequestStatusX on RequestStatus {
  String labelFr(RequestStatus s) {
    switch (s) {
      case RequestStatus.pending:
        return 'En attente';
      case RequestStatus.accepted:
        return 'Acceptée';
      case RequestStatus.refused:
        return 'Refusée';
      case RequestStatus.enRoute:
        return 'En route';
      case RequestStatus.arrived:
        return 'Arrivé';
      case RequestStatus.inProgress:
        return 'En cours';
      case RequestStatus.completed:
        return 'Terminée';
      case RequestStatus.cancelled:
        return 'Annulée';
    }
  }

  String labelAr(RequestStatus s) {
    switch (s) {
      case RequestStatus.pending:
        return 'في الانتظار';
      case RequestStatus.accepted:
        return 'مقبولة';
      case RequestStatus.refused:
        return 'مرفوضة';
      case RequestStatus.enRoute:
        return 'في الطريق';
      case RequestStatus.arrived:
        return 'وصل';
      case RequestStatus.inProgress:
        return 'جارية';
      case RequestStatus.completed:
        return 'مكتملة';
      case RequestStatus.cancelled:
        return 'ملغاة';
    }
  }

  bool get isActive =>
      this == RequestStatus.pending ||
      this == RequestStatus.accepted ||
      this == RequestStatus.enRoute ||
      this == RequestStatus.arrived ||
      this == RequestStatus.inProgress;

  bool get isDone =>
      this == RequestStatus.completed ||
      this == RequestStatus.refused ||
      this == RequestStatus.cancelled;
}
