class Helpers {
  static String formatElapsed(DateTime date) {
    final diff = DateTime.now().difference(date);

    if (diff.inSeconds < 60) {
      return '${diff.inSeconds}s ago';
    } else if (diff.inMinutes < 60) {
      return '${diff.inMinutes}m ago';
    } else if (diff.inHours < 24) {
      return '${diff.inHours}h ago';
    } else {
      return '${diff.inDays}d ago';
    }
  }

  static String formatTime(DateTime date) {
    return '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}:${date.second.toString().padLeft(2, '0')}';
  }

  static String getStatusColor(String status) {
    switch (status) {
      case 'active':
        return '#22C55E';
      case 'stale':
        return '#F59E0B';
      case 'offline':
        return '#EF4444';
      default:
        return '#94A3B8';
    }
  }

  static String getFlagColor(String flag) {
    switch (flag) {
      case 'safe':
        return '#22C55E';
      case 'trouble':
        return '#F59E0B';
      case 'help':
        return '#EF4444';
      default:
        return '#94A3B8';
    }
  }

  static String getRoleBadge(String role) {
    switch (role) {
      case 'lead':
        return '★';
      case 'medic':
        return '✚';
      case 'scout':
        return '👁';
      case 'support':
        return '⚙';
      case 'sniper':
        return '⌖';
      default:
        return '';
    }
  }
}
