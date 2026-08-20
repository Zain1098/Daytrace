enum VoiceCommandIntent { saveTask, startTask }

/// Conservative local parser for spoken quick-capture phrases.
///
/// It only infers whether the user asked to start immediately. Every parsed
/// title remains in the editable Quick Add field and needs an explicit save.
class VoiceCommand {
  const VoiceCommand({required this.title, required this.intent});

  final String title;
  final VoiceCommandIntent intent;

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

    final RegExpMatch? addMatch =
        RegExp(r'^(?:add|create)\s+(.+)$', caseSensitive: false)
            .firstMatch(cleaned);
    return VoiceCommand(
      title: addMatch?.group(1)?.trim() ?? cleaned,
      intent: VoiceCommandIntent.saveTask,
    );
  }
}
