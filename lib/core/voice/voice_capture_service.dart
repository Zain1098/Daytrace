import 'package:permission_handler/permission_handler.dart';
import 'package:speech_to_text/speech_to_text.dart';

class VoiceCaptureService {
  VoiceCaptureService({SpeechToText? speech}) : _speech = speech ?? SpeechToText();
  final SpeechToText _speech;

  Future<bool> start({required void Function(String transcript, bool isFinal) onResult}) async {
    final PermissionStatus permission = await Permission.microphone.request();
    if (!permission.isGranted) return false;
    final bool available = await _speech.initialize();
    if (!available) return false;
    await _speech.listen(onResult: (result) => onResult(result.recognizedWords, result.finalResult));
    return true;
  }

  Future<void> stop() => _speech.stop();
  bool get isListening => _speech.isListening;
}
