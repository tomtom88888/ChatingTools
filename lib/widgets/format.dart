/// Small formatting helpers shared by the screens.
library;

/// Thousands separators, so a five-figure count reads at a glance.
String grouped(int value) {
  final digits = value.abs().toString();
  final out = StringBuffer(value < 0 ? '-' : '');
  for (var i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) out.write(',');
    out.write(digits[i]);
  }
  return out.toString();
}

/// Token counts run to millions, where the exact figure is noise.
String compactTokens(int tokens) => tokens >= 100000
    ? '${(tokens / 1000000).toStringAsFixed(1)}M'
    : grouped(tokens);

/// A whole percentage.
String percent(double share) => '${(share * 100).round()}%';

const List<String> _months = [
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'May',
  'Jun',
  'Jul',
  'Aug',
  'Sep',
  'Oct',
  'Nov',
  'Dec',
];

/// `20 Sep`.
String dayMonth(DateTime at) => '${at.day} ${_months[at.month - 1]}';

/// `20 Sep, 9:48 am`.
String dayMonthTime(DateTime at) {
  final hour12 = at.hour % 12 == 0 ? 12 : at.hour % 12;
  final suffix = at.hour < 12 ? 'am' : 'pm';
  final minute = at.minute.toString().padLeft(2, '0');
  return '${dayMonth(at)}, $hour12:$minute $suffix';
}

/// `September 2026` from a `yyyy-mm` key.
String monthName(String key) {
  const full = [
    'January',
    'February',
    'March',
    'April',
    'May',
    'June',
    'July',
    'August',
    'September',
    'October',
    'November',
    'December',
  ];
  final parts = key.split('-');
  final month = parts.length == 2 ? int.tryParse(parts[1]) : null;
  if (month == null || month < 1 || month > 12) return key;
  return '${full[month - 1]} ${parts[0]}';
}

/// "Maya", "Maya & Sam", "Maya, Sam & 2 more".
String nameList(List<String> names) {
  final shown = names.where((n) => n.isNotEmpty).toList();
  if (shown.isEmpty) return 'them';
  if (shown.length == 1) return shown.first;
  if (shown.length == 2) return '${shown[0]} & ${shown[1]}';
  return '${shown[0]}, ${shown[1]} & ${shown.length - 2} more';
}

/// A reply time in words: "under a minute", "4 min", "1 h 20 min", "2 days".
String replyTime(int? seconds) {
  if (seconds == null) return '—';
  if (seconds < 60) return 'under a minute';
  final minutes = seconds ~/ 60;
  if (minutes < 60) return '$minutes min';
  final hours = minutes ~/ 60;
  final rest = minutes % 60;
  if (hours < 24) return rest == 0 ? '$hours h' : '$hours h $rest min';
  final days = hours ~/ 24;
  return days == 1 ? '1 day' : '$days days';
}

/// `20 Sep 2026`.
String dayMonthYear(DateTime at) => '${dayMonth(at)} ${at.year}';
