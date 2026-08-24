import 'package:flutter/material.dart';

import 'package:allo_service_pro/core/models/request_status.dart';
import 'package:allo_service_pro/core/theme/app_colors.dart';
import 'package:allo_service_pro/shared/app_locale.dart';

class StatusBadge extends StatelessWidget {
  const StatusBadge({super.key, required this.status});

  final RequestStatus status;

  Color get _color {
    switch (status) {
      case RequestStatus.pending:
        return AppColors.warning;
      case RequestStatus.accepted:
      case RequestStatus.enRoute:
      case RequestStatus.arrived:
      case RequestStatus.inProgress:
        return AppColors.primary;
      case RequestStatus.completed:
        return AppColors.success;
      case RequestStatus.refused:
      case RequestStatus.cancelled:
        return AppColors.error;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: _color.withValues(alpha: .12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        tr(context, fr: status.labelFr(status), ar: status.labelAr(status)),
        style: TextStyle(
          color: _color,
          fontWeight: FontWeight.w700,
          fontSize: 12,
        ),
      ),
    );
  }
}
