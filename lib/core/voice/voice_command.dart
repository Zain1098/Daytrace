enum VoiceCommandIntent { saveTask, startTask, scheduleReminder }

/// Conservative local parser for spoken quick-capture phrases.
///
/// It only infers high-confidence start or reminder details. Every parsed
/// title and due time remains editable and needs an explicit save.
class VoiceCommand {
  const VoiceCommand({
    required this.title,
    required this.intent,
    this.reminderTime,
  });

  final String title;
  final VoiceCommandIntent intent;
  final VoiceReminderTime? reminderTime;

  static VoiceCommand parse(String transcript) {
    final String cleaned = transcript.trim().replaceAll(RegExp(r'\s+'), ' ');
    final RegExpMatch? startMatch =
        RegExp(r'^(?:start|begin)\s+(.+)$', caseSensitive: false)
            .firstMatch(cleaned);
    if (startMatch != null) {
      return VoiceCommand(
        title: startMatch.group(1)!.trim(),
        intent: VoiceCommandIntent.startTask,
      );
    }

    final RegExpMatch? reminderMatch = RegExp(
      r'^remind me to\s+(.+?)\s+at\s+(\d{1,2})(?::(\d{2}))?\s*(am|pm)$',
      caseSensitive: false,
    ).firstMatch(cleaned);
    if (reminderMatch != null) {
      final int spokenHour = int.parse(reminderMatch.group(2)!);
      final int minute = int.tryParse(reminderMatch.group(3) ?? '0') ?? 0;
      if (spokenHour >= 1 && spokenHour <= 12 && minute <= 59) {
        final bool afternoon = reminderMatch.group(4)!.toLowerCase() == 'pm';
        final int hour = (spokenHour % 12) + (afternoon ? 12 : 0);
        return VoiceCommand(
          title: reminderMatch.group(1)!.trim(),
          intent: VoiceCommandIntent.scheduleReminder,
          reminderTime: VoiceReminderTime(hour: hour, minute: minute),
        );
      }
    }

    final RegExpMatch? addMatch =
        RegExp(r'^(?:add|create)\s+(.+)$', caseSensitive: false)
            .firstMatch(cleaned);
    return VoiceCommand(
      title: addMatch?.group(1)?.trim() ?? cleaned,
      intent: VoiceCommandIntent.saveTask,
    );
  }
}

class VoiceReminderTime {
  const VoiceReminderTime({required this.hour, required this.minute});

  final int hour;
  final int minute;
}
