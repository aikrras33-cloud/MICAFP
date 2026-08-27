// =============================================================================
// voice_command_service.dart — §10.3 Voice Commands
//
// Wraps the `speech_to_text` Flutter plugin (already declared in
// pubspec.yaml as `speech_to_text: ^6.6.0`) with three modes:
//
//   1. init()                       — request microphone permission + boot
//                                      the recognizer. Returns `true` on
//                                      permission granted + recognizer
//                                      initialized.
//   2. listenOnce() -> Future<String> — single-shot listen; returns the
//                                      recognized text when the user
//                                      pauses or stops.
//   3. listenContinuous() -> Stream<String> — continuous listening mode
//                                      (when the AI sheet is open);
//                                      emits partial + final transcripts.
//
// Wake-word: "Shield, ..." (lightweight on-device prefix match). When a
// transcript begins with "shield" (case-insensitive) the wake-word is
// stripped and the remainder is forwarded to the consumer. Tap-to-speak
// is the fallback when the platform doesn't expose a recognizer (e.g.
// desktop without a mic permission UI) — consumers should call
// `listenOnce()` on a button tap instead of `listenContinuous()`.
// =============================================================================

import 'dart:async';

import 'package:speech_to_text/speech_recognition_error.dart';
import 'package:speech_to_text/speech_to_text.dart';

/// Wraps the speech_to_text plugin with the three modes required by §10.3.
///
/// The wake word is the case-insensitive prefix `"shield"` (English) or
/// `"شیلد"` (Persian). When a transcript starts with either, the prefix
/// is stripped before the rest of the transcript is forwarded to the
/// consumer.
class VoiceCommandService {
  final SpeechToText _stt = SpeechToText();

  bool _available = false;
  bool _initialized = false;
  bool _listening = false;

  // Stream controller for `listenContinuous`.
  StreamController<String>? _controller;

  /// Whether the recognizer is initialized and has mic permission.
  bool get isInitialized => _initialized;

  /// Whether a recognition session is currently active.
  bool get isListening => _listening;

  /// Request microphone permission and boot the recognizer. Returns
  /// `true` on success. Safe to call multiple times — subsequent calls
  /// are no-ops once initialized.
  Future<bool> init() async {
    if (_initialized) return _available;
    _available = await _stt.initialize(
      onError: _onError,
      onStatus: _onStatus,
    );
    _initialized = true;
    return _available;
  }

  /// Single-shot listen. Returns the recognized text once the user pauses
  /// or stops. Returns an empty string if recognition fails or is
  /// unavailable. The wake word is stripped if present.
  Future<String> listenOnce({String localeId = 'en_US'}) async {
    if (!_initialized) {
      final ok = await init();
      if (!ok) return '';
    }
    if (!_available) return '';

    final completer = Completer<String>();
    String accumulated = '';

    await _stt.listen(
      onResult: (result) {
        // Only finalize on `finalResult=true`. The speech_to_text plugin
        // fires partial results during the listen session; we accumulate
        // the last partial as the best-effort transcript if the session
        // never reaches a final state.
        accumulated = result.recognizedWords;
        if (result.finalResult) {
          if (!completer.isCompleted) {
            completer.complete(_stripWakeWord(accumulated));
          }
        }
      },
      listenFor: const Duration(seconds: 30),
      pauseFor: const Duration(seconds: 3),
      partialResults: true,
      localeId: localeId,
      cancelOnError: true,
    );
    _listening = true;

    // Fallback in case the session ends without a `finalResult=true`
    // (e.g. user taps stop, timeout, or platform quirk).
    Timer(const Duration(seconds: 31), () {
      if (!completer.isCompleted) {
        completer.complete(_stripWakeWord(accumulated));
      }
    });

    final result = await completer.future;
    _listening = false;
    return result;
  }

  /// Continuous listening mode. Emits every partial + final transcript
  /// as a separate stream event (wake-word already stripped). Consumers
  /// should keep listening while the AI assistant sheet is open and stop
  /// listening when the sheet is dismissed.
  Stream<String> listenContinuous({String localeId = 'en_US'}) async* {
    if (!_initialized) {
      final ok = await init();
      if (!ok) {
        yield '';
        return;
      }
    }
    if (!_available) {
      yield '';
      return;
    }

    _controller = StreamController<String>.broadcast(
      onCancel: () {
        stop();
      },
    );

    await _stt.listen(
      onResult: (result) {
        final text = _stripWakeWord(result.recognizedWords);
        if (text.isNotEmpty) {
          _controller?.add(text);
        }
      },
      listenFor: const Duration(minutes: 5),
      pauseFor: const Duration(seconds: 2),
      partialResults: true,
      localeId: localeId,
      cancelOnError: false,
    );
    _listening = true;

    yield* _controller!.stream;
  }

  /// Stop an active recognition session.
  Future<void> stop() async {
    if (_listening) {
      await _stt.stop();
      _listening = false;
    }
    await _controller?.close();
    _controller = null;
  }

  /// Release the recognizer + cancel any pending streams.
  Future<void> dispose() async {
    await stop();
    await _stt.cancel();
  }

  // ── Internals ─────────────────────────────────────────────────────────

  void _onError(SpeechRecognitionError error) {
    // Forward the error to the stream controller if a continuous
    // listening session is active. Otherwise, log it.
    if (_controller != null && !_controller!.isClosed) {
      _controller!.addError(error.errorMsg);
    }
  }

  void _onStatus(String status) {
    // `notListening` indicates the session ended (either by user pause,
    // stop, or timeout). Close the controller so the stream consumer
    // receives onDone.
    if (status == 'notListening' || status == 'done') {
      _listening = false;
      _controller?.close();
      _controller = null;
    }
  }

  /// Strip the wake word from the start of the transcript. The wake
  /// word is `"shield"` (English, case-insensitive) or `"شیلد"` (Persian).
  /// A comma after the wake word is also stripped (e.g.
  /// `"Shield, connect"` → `"connect"`).
  String _stripWakeWord(String transcript) {
    if (transcript.isEmpty) return transcript;
    final lower = transcript.toLowerCase();
    const wakeEn = 'shield';
    const wakeFa = 'شیلد';
    if (lower.startsWith(wakeEn)) {
      return _stripLeadingPunct(transcript.substring(wakeEn.length));
    }
    if (transcript.startsWith(wakeFa)) {
      return _stripLeadingPunct(transcript.substring(wakeFa.length));
    }
    return transcript;
  }

  String _stripLeadingPunct(String s) {
    var out = s.trim();
    while (out.isNotEmpty &&
        (out.startsWith(',') ||
            out.startsWith('،') ||
            out.startsWith('.') ||
            out.startsWith('!') ||
            out.startsWith('?'))) {
      out = out.substring(1).trim();
    }
    return out;
  }
}
