import '../../requests/application/request_store.dart';
import '../../requests/models/service_request.dart';
import '../../../core/models/request_status.dart';

class StatisticsStore {
  StatisticsStore._();

  static Map<String, int> getRequestsByCategory() {
    final Map<String, int> categoryStats = {};

    for (final request in RequestStore.requests.value) {
      final category = request.serviceTitleFr;
      categoryStats[category] = (categoryStats[category] ?? 0) + 1;
    }

    return categoryStats;
  }

  static Map<String, int> getRequestsByRegion() {
    final Map<String, int> regionStats = {};

    for (final request in RequestStore.requests.value) {
      // Extract region from address (simplified logic)
      final address = request.address.toLowerCase();
      String region = 'Autre';

      if (address.contains('tunis')) {
        region = 'Tunis';
      } else if (address.contains('ariana')) {
        region = 'Ariana';
      } else if (address.contains('ben arous')) {
        region = 'Ben Arous';
      } else if (address.contains('manouba')) {
        region = 'Manouba';
      } else if (address.contains('nabeul')) {
        region = 'Nabeul';
      } else if (address.contains('bizerte')) {
        region = 'Bizerte';
      } else if (address.contains('sousse')) {
        region = 'Sousse';
      } else if (address.contains('sfax')) {
        region = 'Sfax';
      } else if (address.contains('gabès')) {
        region = 'Gabès';
      }

      regionStats[region] = (regionStats[region] ?? 0) + 1;
    }

    return regionStats;
  }

  static Map<String, int> getRequestsByStatus() {
    final Map<String, int> statusStats = {};

    for (final request in RequestStore.requests.value) {
      final status = request.status.labelFr(request.status);
      statusStats[status] = (statusStats[status] ?? 0) + 1;
    }

    return statusStats;
  }

  static double getAverageRating() {
    final ratedRequests =
        RequestStore.requests.value.where((r) => r.rating != null).toList();

    if (ratedRequests.isEmpty) return 0.0;

    final totalRating = ratedRequests.fold<double>(
      0.0,
      (sum, r) => sum + (r.rating ?? 0.0),
    );

    return totalRating / ratedRequests.length;
  }

  static int getTotalRevenue() {
    // Simplified revenue calculation (10 tokens per accepted request)
    final acceptedRequests = RequestStore.requests.value
        .where((r) => r.status == RequestStatus.accepted)
        .length;

    return acceptedRequests * 10; // Assuming 10 DT per request
  }

  static List<ServiceRequest> getRecentRequests(int limit) {
    return RequestStore.requests.value.take(limit).toList();
  }

  static Map<String, dynamic> getMonthlyStats() {
    final Map<String, dynamic> monthlyStats = {};
    final now = DateTime.now();

    for (int i = 0; i < 6; i++) {
      final month = DateTime(now.year, now.month - i, 1);
      final monthKey = '${month.month}/${month.year}';

      final monthRequests = RequestStore.requests.value.where((r) {
        return r.createdAt.month == month.month &&
            r.createdAt.year == month.year;
      }).length;

      monthlyStats[monthKey] = monthRequests;
    }

    return monthlyStats;
  }
}
