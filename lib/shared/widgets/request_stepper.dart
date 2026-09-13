import 'package:flutter/material.dart';

import 'package:allo_service_pro/core/models/request_status.dart';
import 'package:allo_service_pro/core/theme/app_colors.dart';
import 'package:allo_service_pro/shared/app_locale.dart';

/// Uber-style horizontal progress stepper:
/// Pending ➔ Accepted ➔ En Route ➔ Arrived ➔ In Progress ➔ Completed.
/// Cancelled/refused fall back to showing the current stage in red.
class RequestStepper extends StatelessWidget {
  const RequestStepper({super.key, required this.status});

  final RequestStatus status;

  static const _stages = <RequestStatus, ({IconData icon, String fr, String ar})>{
    RequestStatus.pending: (
      icon: Icons.schedule_rounded,
      fr: 'En attente',
      ar: 'قيد الانتظار',
    ),
    RequestStatus.accepted: (
      icon: Icons.check_circle_outline_rounded,
      fr: 'Acceptée',
      ar: 'مقبول',
    ),
    RequestStatus.enRoute: (
      icon: Icons.directions_car_rounded,
      fr: 'En route',
      ar: 'في الطريق',
    ),
    RequestStatus.arrived: (
      icon: Icons.where_to_vote_rounded,
      fr: 'Arrivé',
      ar: 'وصل',
    ),
    RequestStatus.inProgress: (
      icon: Icons.construction_rounded,
      fr: 'En cours',
      ar: 'جاري العمل',
    ),
    RequestStatus.completed: (
      icon: Icons.task_alt_rounded,
      fr: 'Terminée',
      ar: 'مكتمل',
    ),
  };

  static const _order = [
    RequestStatus.pending,
    RequestStatus.accepted,
    RequestStatus.enRoute,
    RequestStatus.arrived,
    RequestStatus.inProgress,
    RequestStatus.completed,
  ];

  int get _currentIndex {
    if (_order.contains(status)) return _order.indexOf(status);
    // Cancelled / refused → stay visually at the pending stage, shown red.
    return 0;
  }

  bool get _isFailed =>
      status == RequestStatus.cancelled || status == RequestStatus.refused;

  @override
  Widget build(BuildContext context) {
    final stageColor = _isFailed ? AppColors.error : AppColors.primary;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: .06),
            blurRadius: 12,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Row(
        children: [
          for (var i = 0; i < _order.length; i++) ...[
            if (i > 0)
              Expanded(
                child: Container(
                  height: 2.5,
                  margin: const EdgeInsets.only(bottom: 22),
                  decoration: BoxDecoration(
                    color: i <= _currentIndex
                        ? stageColor
                        : AppColors.slate400,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
            _StepNode(
              icon: _stages[_order[i]]!.icon,
              label: tr(context,
                  fr: _stages[_order[i]]!.fr, ar: _stages[_order[i]]!.ar),
              state: i < _currentIndex
                  ? _StepState.done
                  : i == _currentIndex
                      ? (_isFailed ? _StepState.failed : _StepState.current)
                      : _StepState.upcoming,
            ),
          ],
        ],
      ),
    );
  }
}

enum _StepState { upcoming, current, done, failed }

class _StepNode extends StatelessWidget {
  const _StepNode({
    required this.icon,
    required this.label,
    required this.state,
  });

  final IconData icon;
  final String label;
  final _StepState state;

  Color get _color {
    switch (state) {
      case _StepState.done:
      case _StepState.current:
        return AppColors.primary;
      case _StepState.failed:
        return AppColors.error;
      case _StepState.upcoming:
        return AppColors.slate400;
    }
  }

  @override
  Widget build(BuildContext context) {
    final isCurrent = state == _StepState.current || state == _StepState.failed;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: isCurrent ? 38 : 30,
          height: isCurrent ? 38 : 30,
          decoration: BoxDecoration(
            color: state == _StepState.upcoming
                ? AppColors.slate400.withValues(alpha: 0.25)
                : _color.withValues(alpha: state == _StepState.done ? 0.15 : 1),
            shape: BoxShape.circle,
            border: Border.all(color: _color, width: 2),
          ),
          child: Icon(
            state == _StepState.done ? Icons.check_rounded : icon,
            size: isCurrent ? 20 : 16,
            color: state == _StepState.upcoming
                ? AppColors.slate400
                : (state == _StepState.done ? _color : Colors.white),
          ),
        ),
        const SizedBox(height: 6),
        Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 10,
            fontWeight: isCurrent ? FontWeight.w800 : FontWeight.w600,
            color: isCurrent ? _color : AppColors.textSecondary,
          ),
        ),
      ],
    );
  }
}
