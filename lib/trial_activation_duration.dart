String formatTrialDuration(Duration duration) {
  if (duration.inDays > 0) {
    final remainingHours = duration.inHours % Duration.hoursPerDay;
    final remainingMinutes = duration.inMinutes % Duration.minutesPerHour;
    return [
      '${duration.inDays} ${duration.inDays == 1 ? 'day' : 'days'}',
      if (remainingHours > 0)
        '$remainingHours ${remainingHours == 1 ? 'hour' : 'hours'}',
      if (remainingMinutes > 0)
        '$remainingMinutes ${remainingMinutes == 1 ? 'minute' : 'minutes'}',
    ].join(' ');
  }
  if (duration.inHours > 0) {
    final remainingMinutes = duration.inMinutes % Duration.minutesPerHour;
    return [
      '${duration.inHours} ${duration.inHours == 1 ? 'hour' : 'hours'}',
      if (remainingMinutes > 0)
        '$remainingMinutes ${remainingMinutes == 1 ? 'minute' : 'minutes'}',
    ].join(' ');
  }
  return '${duration.inMinutes} ${duration.inMinutes == 1 ? 'minute' : 'minutes'}';
}

Duration parseTrialDuration(String input) {
  final match = RegExp(
    r'^([1-9][0-9]*)([mhd]?)$',
    caseSensitive: false,
  ).firstMatch(input);
  if (match == null) {
    throw const FormatException(
      'Trial duration must be a positive number followed by m, h, or d (for example 30m, 2h, or 14d).',
    );
  }

  final amount = int.tryParse(match.group(1)!);
  final unit = match.group(2)!.toLowerCase();
  if (amount == null) {
    throw const FormatException('Trial duration is too large.');
  }
  final duration = switch (unit) {
    'm' => Duration(minutes: amount),
    'h' => Duration(hours: amount),
    _ => Duration(days: amount),
  };
  if (duration.inMinutes < 1 || duration > const Duration(days: 365)) {
    throw const FormatException(
      'Trial duration must be at least 1 minute and no longer than 365 days.',
    );
  }
  return duration;
}
