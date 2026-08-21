DateTime? parseDateSafely(dynamic value) {
  if (value == null) return null;
  if (value is DateTime) {
    return (value.year >= 1000 && value.year <= 3000) ? value : null;
  }
  if (value is int) {
    if (value >= 1000 && value <= 3000) {
      return DateTime(value);
    }
    final str = value.toString();
    if (str.length == 8) {
      final y = int.tryParse(str.substring(0, 4));
      final m = int.tryParse(str.substring(4, 6));
      final d = int.tryParse(str.substring(6, 8));
      if (y != null &&
          m != null &&
          d != null &&
          y >= 1000 &&
          y <= 3000 &&
          m >= 1 &&
          m <= 12 &&
          d >= 1 &&
          d <= 31) {
        try {
          return DateTime(y, m, d);
        } catch (_) {}
      }
    }
    return null;
  }

  final str = value.toString().trim();
  if (str.isEmpty) return null;

  if (str.length == 4) {
    final y = int.tryParse(str);
    if (y != null && y >= 1000 && y <= 3000) {
      return DateTime(y);
    }
  }

  if (str.length == 8 && RegExp(r'^\d{8}$').hasMatch(str)) {
    final y = int.tryParse(str.substring(0, 4));
    final m = int.tryParse(str.substring(4, 6));
    final d = int.tryParse(str.substring(6, 8));
    if (y != null &&
        m != null &&
        d != null &&
        y >= 1000 &&
        y <= 3000 &&
        m >= 1 &&
        m <= 12 &&
        d >= 1 &&
        d <= 31) {
      try {
        return DateTime(y, m, d);
      } catch (_) {}
    }
  }

  if (str.contains('/') || str.contains('-') || str.contains('.')) {
    final dt = DateTime.tryParse(str);
    if (dt != null && dt.year >= 1000 && dt.year <= 3000) {
      return dt;
    }

    final delimiter = str.contains('/')
        ? '/'
        : (str.contains('-') ? '-' : '.');
    final parts = str.split(delimiter);
    if (parts.length >= 3) {
      final p0 = int.tryParse(parts[0]);
      final p1 = int.tryParse(parts[1]);
      final p2 = int.tryParse(parts[2]);
      if (p0 != null && p1 != null && p2 != null) {
        if (p0 >= 1000 &&
            p0 <= 3000 &&
            p1 >= 1 &&
            p1 <= 12 &&
            p2 >= 1 &&
            p2 <= 31) {
          try {
            return DateTime(p0, p1, p2);
          } catch (_) {}
        } else if (p2 >= 1000 &&
            p2 <= 3000 &&
            p0 >= 1 &&
            p0 <= 12 &&
            p1 >= 1 &&
            p1 <= 31) {
          try {
            return DateTime(p2, p0, p1);
          } catch (_) {}
        }
      }
    } else if (parts.isNotEmpty) {
      final y = int.tryParse(parts.first);
      if (y != null && y >= 1000 && y <= 3000) {
        return DateTime(y);
      }
    }
  }

  final dt = DateTime.tryParse(str);
  if (dt != null && dt.year >= 1000 && dt.year <= 3000) {
    return dt;
  }

  final match = RegExp(r'(\d{4})').firstMatch(str);
  if (match != null) {
    final y = int.tryParse(match.group(1)!);
    if (y != null && y >= 1000 && y <= 3000) {
      return DateTime(y);
    }
  }

  return null;
}
