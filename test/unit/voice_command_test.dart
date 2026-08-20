import 'package:daytrace/core/voice/voice_command.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('start command prepares an editable immediate activity', () {
    final VoiceCommand command = VoiceCommand.parse('Start machine inspection');

    expect(command.title, 'machine inspection');
    expect(command.intent, VoiceCommandIntent.startTask);
  });

  test('add command remains a normal task draft', () {
    final VoiceCommand command = VoiceCommand.parse('Add production report for tomorrow');

    expect(command.title, 'production report for tomorrow');
    expect(command.intent, VoiceCommandIntent.saveTask);
  });

  test('unrecognized speech remains an editable normal task draft', () {
    final VoiceCommand command = VoiceCommand.parse('Review timeline after lunch');

    expect(command.title, 'Review timeline after lunch');
    expect(command.intent, VoiceCommandIntent.saveTask);
  });
}
