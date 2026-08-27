// =============================================================================
// ai_assistant_screen.dart — Quantum Enterprise RGB AI Assistant (§10.1)
//
// Per §6.4.7 + §10.1:
//   - Top: greeting "Hi, I'm Shield AI" (display2, RGB gradient text).
//   - Middle: scrollable conversation (user right-aligned in bgSurface bubble,
//     AI left-aligned in bgElevated bubble with RGB accent border).
//   - Bottom: text input with mic icon (mic tap → speech_to_text).
//   - Suggested prompts chips above input:
//       "Why is my connection slow?",
//       "Which transport is best for MCI?",
//       "Run a DPI test",
//       "How long until my license expires?".
//   - Uses MethodChannel("com.unifiedshield/ai") + EventChannel for streaming
//     tokens.
// =============================================================================

import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/quantum_components.dart';
import '../theme/quantum_glassmorphism.dart';
import '../theme/quantum_theme.dart';

/// A self-contained full-screen AI Assistant (used by the home screen's FAB
/// when expanded to ~90% height — the FAB itself is the collapsed form).
///
/// Per §10.1 — uses MethodChannel `com.unifiedshield/ai` for request/response
/// + EventChannel `com.unifiedshield/ai/stream` for token streaming.
class AIAssistantScreen extends StatefulWidget {
  const AIAssistantScreen({
    super.key,
    this.locale = 'en',
    this.onClose,
  });

  final String locale;
  final VoidCallback? onClose;

  @override
  State<AIAssistantScreen> createState() => _AIAssistantScreenState();
}

class _AIAssistantScreenState extends State<AIAssistantScreen>
    with TickerProviderStateMixin {
  static const _methodChannel = MethodChannel('com.unifiedshield/ai');
  static const _eventChannel = EventChannel('com.unifiedshield/ai/stream');

  final TextEditingController _input = TextEditingController();
  final ScrollController _scroll = ScrollController();
  final List<QuantumAIMessage> _messages = [];

  late final AnimationController _in;
  StreamSubscription<dynamic>? _streamSub;
  bool _isStreaming = false;
  bool _isListening = false;
  // §10.2: "Use Gemini (cloud)" toggle — default OFF. When ON, the daemon
  // routes the prompt through Gemini 2.5 Pro (if internet is reachable) and
  // merges the cloud-side reasoning into the on-device LLM reply.
  bool _useCloud = false;

  @override
  void initState() {
    super.initState();
    _in = AnimationController(
      vsync: this,
      duration: QuantumDurations.medium,
    )..forward();
    _streamSub = _eventChannel.receiveBroadcastStream().listen(_onToken);
    // Seed with an initial greeting message from the AI.
    _messages.add(QuantumAIMessage(
      role: 'ai',
      text: widget.locale == 'fa'
          ? 'سلام! من Shield AI هستم. چطور می‌تونم کمک کنم؟'
          : "Hi! I'm Shield AI. How can I help you with your VPN?",
    ));
  }

  @override
  void dispose() {
    _streamSub?.cancel();
    _input.dispose();
    _scroll.dispose();
    _in.dispose();
    super.dispose();
  }

  void _onToken(dynamic event) {
    if (!mounted) return;
    String token = '';
    if (event is String) {
      token = event;
    } else if (event is Map) {
      // Could be `{token: 'x', done: false}` or `{token: 'x', error: 'msg'}`.
      final m = Map<String, dynamic>.from(event);
      token = (m['token'] ?? m['text'] ?? '').toString();
      if (m['error'] != null) {
        setState(() => _isStreaming = false);
        return;
      }
      if (m['done'] == true) {
        setState(() => _isStreaming = false);
        return;
      }
    }
    if (token.isEmpty) return;
    setState(() {
      final last = _messages.lastOrNull;
      if (last != null && last.role == 'ai' && last.isStreaming) {
        _messages[_messages.length - 1] =
            QuantumAIMessage(role: 'ai', text: last.text + token, isStreaming: true);
      } else {
        _messages.add(QuantumAIMessage(role: 'ai', text: token, isStreaming: true));
      }
    });
    _scrollToBottom();
  }

  void _scrollToBottom() {
    if (!_scroll.hasClients) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.animateTo(
          _scroll.position.maxScrollExtent,
          duration: const Duration(milliseconds: 120),
          curve: QuantumCurves.easeInOutCubicEmphasized,
        );
      }
    });
  }

  Future<void> _send(String text) async {
    if (text.trim().isEmpty) return;
    setState(() {
      _messages.add(QuantumAIMessage(role: 'user', text: text));
      _isStreaming = true;
      // Reserve a slot for the AI reply so the stream can extend it.
      _messages.add(const QuantumAIMessage(role: 'ai', text: '', isStreaming: true));
    });
    _input.clear();
    _scrollToBottom();
    try {
      // The daemon picks up the request via the method channel + streams
      // tokens back via the event channel subscription in initState.
      //
      // Method contract: `query(prompt, locale, use_cloud) -> Future<String>`
      // (the platform side dispatches to FFI `ai_query(prompt, use_cloud)`
      // and returns the final reply). Streaming tokens flow back via the
      // EventChannel before the Future resolves.
      await _methodChannel.invokeMethod<String>('query', {
        'prompt': text,
        'locale': widget.locale,
        'use_cloud': _useCloud,
      });
    } on PlatformException catch (e) {
      if (mounted) {
        setState(() {
          _messages.add(QuantumAIMessage(
            role: 'ai',
            text: widget.locale == 'fa'
                ? 'خطا: ${e.message ?? 'ارتباط با AI ناموفق بود'}'
                : 'Error: ${e.message ?? 'failed to reach AI'}',
          ));
          _isStreaming = false;
        });
        _scrollToBottom();
      }
    }
  }

  Future<void> _toggleMic() async {
    if (_isListening) {
      try {
        await _methodChannel.invokeMethod<void>('stopListening');
      } catch (_) {}
      setState(() => _isListening = false);
      return;
    }
    setState(() => _isListening = true);
    try {
      // The platform side streams partial transcripts to the same event
      // channel; we'll route them through _onToken by prefixing.
      await _methodChannel.invokeMethod<void>('startListening', {
        'locale': widget.locale,
      });
    } on PlatformException catch (e) {
      if (mounted) {
        setState(() => _isListening = false);
        QuantumToast.show(
          context,
          message: widget.locale == 'fa'
              ? 'تشخیص گفتار در دسترس نیست: ${e.message ?? 'unknown error'}'
              : 'Speech recognition unavailable: ${e.message ?? 'unknown error'}',
          accentColor: QuantumPalette.statusWarning,
          icon: Icons.mic_off,
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final locale = widget.locale;
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Stack(
        children: [
          // Aurora background per §6.10
          const QuantumAuroraBackground(),
          SafeArea(
            child: AnimatedBuilder(
              animation: _in,
              builder: (context, child) {
                return FadeTransition(
                  opacity: QuantumTransitions.fadeIn(_in),
                  child: SlideTransition(
                    position: QuantumTransitions.slideUp(_in),
                    child: child,
                  ),
                );
              },
              child: Column(
                children: [
                  // Header: greeting + close
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: QuantumPalette.spaceLg,
                      vertical: QuantumPalette.spaceMd,
                    ),
                    child: Row(
                      children: [
                        if (widget.onClose != null)
                          GestureDetector(
                            onTap: widget.onClose,
                            child: const Icon(
                              Icons.chevron_left,
                              color: QuantumPalette.textPrimary,
                              size: 28,
                            ),
                          ),
                        if (widget.onClose != null)
                          const SizedBox(width: QuantumPalette.spaceSm),
                        Expanded(
                          child: ShaderMask(
                            shaderCallback: (rect) =>
                                QuantumGradients.animatedRgbRing().createShader(rect),
                            child: Text(
                              locale == 'fa'
                                  ? 'سلام، من Shield AI هستم'
                                  : "Hi, I'm Shield AI",
                              style: QuantumTypography.display2For(locale)
                                  .copyWith(color: Colors.white),
                            ),
                          ),
                        ),
                        if (_isStreaming)
                          const Padding(
                            padding: EdgeInsets.only(left: 8),
                            child: QuantumSpinner(size: 18, strokeWidth: 2),
                          ),
                      ],
                    ),
                  ),
                  // Conversation list
                  Expanded(
                    child: ListView.builder(
                      controller: _scroll,
                      padding: const EdgeInsets.symmetric(
                        horizontal: QuantumPalette.spaceLg,
                        vertical: QuantumPalette.spaceSm,
                      ),
                      itemCount: _messages.length,
                      itemBuilder: (context, i) {
                        final m = _messages[i];
                        final isUser = m.role == 'user';
                        return Align(
                          alignment: isUser
                              ? Alignment.centerRight
                              : Alignment.centerLeft,
                          child: Container(
                            margin: const EdgeInsets.symmetric(vertical: 4),
                            padding: const EdgeInsets.symmetric(
                              horizontal: QuantumPalette.spaceMd,
                              vertical: QuantumPalette.spaceSm,
                            ),
                            constraints: BoxConstraints(
                              maxWidth:
                                  MediaQuery.of(context).size.width * 0.75,
                            ),
                            decoration: BoxDecoration(
                              color: isUser
                                  ? QuantumPalette.bgSurface
                                  : QuantumPalette.bgElevated,
                              borderRadius: BorderRadius.only(
                                topLeft: const Radius.circular(
                                    QuantumPalette.radiusCard),
                                topRight: const Radius.circular(
                                    QuantumPalette.radiusCard),
                                bottomLeft: Radius.circular(isUser
                                    ? QuantumPalette.radiusCard
                                    : 4),
                                bottomRight: Radius.circular(isUser
                                    ? 4
                                    : QuantumPalette.radiusCard),
                              ),
                              border: isUser
                                  ? null
                                  : Border.fromBorderSide(
                                      BorderSide(
                                        color: QuantumPalette.rgbAccent3[0]
                                            .withValues(alpha: 0.3),
                                        width: 1,
                                      ),
                                    ),
                            ),
                            child: Text(
                              m.text + (m.isStreaming ? '▌' : ''),
                              style: const TextStyle(
                                fontFamily: 'Inter',
                                fontSize: 14,
                                color: QuantumPalette.textPrimary,
                                height: 1.4,
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                  // Suggested prompts
                  SizedBox(
                    height: 38,
                    child: ListView(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.symmetric(
                          horizontal: QuantumPalette.spaceLg),
                      children: [
                        'Why is my connection slow?',
                        'Which transport is best for MCI?',
                        'Run a DPI test',
                        'How long until my license expires?',
                      ]
                          .map((p) => Padding(
                                padding: const EdgeInsets.only(right: 8),
                                child: ActionChip(
                                  label: Text(
                                    p,
                                    style: const TextStyle(
                                      fontFamily: 'Inter',
                                      fontSize: 12,
                                      color: QuantumPalette.textPrimary,
                                    ),
                                  ),
                                  backgroundColor: QuantumPalette.bgSurface,
                                  side: const BorderSide(
                                      color: QuantumPalette.borderSubtle),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(
                                        QuantumPalette.radiusButton),
                                  ),
                                  onPressed: () => _send(p),
                                ),
                              ))
                          .toList(),
                    ),
                  ),
                  const SizedBox(height: QuantumPalette.spaceSm),
                  // §10.2: "Use Gemini (cloud)" toggle — default OFF.
                  Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: QuantumPalette.spaceLg),
                    child: Row(
                      children: [
                        Icon(
                          Icons.cloud_outlined,
                          size: 16,
                          color: _useCloud
                              ? QuantumPalette.rgbAccent3[0]
                              : QuantumPalette.textTertiary,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            locale == 'fa'
                                ? 'استفاده از Gemini (ابر)'
                                : 'Use Gemini (cloud)',
                            style: const TextStyle(
                              fontFamily: 'Inter',
                              fontSize: 12,
                              color: QuantumPalette.textSecondary,
                            ),
                          ),
                        ),
                        Switch(
                          value: _useCloud,
                          activeThumbColor: QuantumPalette.rgbAccent3[0],
                          activeTrackColor:
                              QuantumPalette.rgbAccent3[0].withValues(alpha: 0.3),
                          onChanged: (val) {
                            setState(() => _useCloud = val);
                          },
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: QuantumPalette.spaceSm),
                  // Input + mic
                  Padding(
                    padding: const EdgeInsets.fromLTRB(
                      QuantumPalette.spaceLg,
                      0,
                      QuantumPalette.spaceLg,
                      QuantumPalette.spaceMd,
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: QuantumGlassPill(
                            padding: const EdgeInsets.symmetric(
                              horizontal: QuantumPalette.spaceMd,
                            ),
                            child: TextField(
                              controller: _input,
                              style: const TextStyle(
                                fontFamily: 'Inter',
                                fontSize: 14,
                                color: QuantumPalette.textPrimary,
                              ),
                              decoration: InputDecoration(
                                hintText: locale == 'fa'
                                    ? 'پیام بنویسید…'
                                    : 'Type a message…',
                                hintStyle: const TextStyle(
                                  color: QuantumPalette.textTertiary,
                                ),
                                border: InputBorder.none,
                                contentPadding: const EdgeInsets.symmetric(
                                  vertical: QuantumPalette.spaceSm,
                                ),
                              ),
                              onSubmitted: (_) {
                                final text = _input.text.trim();
                                if (text.isNotEmpty) _send(text);
                              },
                            ),
                          ),
                        ),
                        const SizedBox(width: QuantumPalette.spaceXs),
                        // Mic button
                        GestureDetector(
                          onTap: _toggleMic,
                          child: Container(
                            width: 48,
                            height: 48,
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                colors: _isListening
                                    ? [
                                        QuantumPalette.statusConnected,
                                        QuantumPalette.statusConnecting,
                                      ]
                                    : QuantumPalette.rgbAccent3,
                              ),
                              shape: BoxShape.circle,
                              boxShadow: [
                                BoxShadow(
                                  color: (_isListening
                                          ? QuantumPalette.statusConnected
                                          : QuantumPalette.rgbAccent3[0])
                                      .withValues(alpha: 0.4),
                                  blurRadius: 12,
                                  spreadRadius: 1,
                                ),
                              ],
                            ),
                            child: Icon(
                              _isListening ? Icons.stop : Icons.mic,
                              color: Colors.white,
                              size: 22,
                            ),
                          ),
                        ),
                        const SizedBox(width: QuantumPalette.spaceXs),
                        // Send button
                        GestureDetector(
                          onTap: () {
                            final text = _input.text.trim();
                            if (text.isNotEmpty) _send(text);
                          },
                          child: Container(
                            width: 48,
                            height: 48,
                            decoration: BoxDecoration(
                              color: QuantumPalette.bgElevated,
                              shape: BoxShape.circle,
                              border: Border.fromBorderSide(
                                const BorderSide(
                                    color: QuantumPalette.borderSubtle),
                              ),
                            ),
                            child: const Icon(
                              Icons.send,
                              color: QuantumPalette.textSecondary,
                              size: 20,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// Stub helper — kept here so the file is self-contained even before the
// daemon-side channel is fully wired (the platform side falls through to
// a friendly "I'm still loading" message).
// ignore: unused_element
class _AIStub {
  static const _greetingFa = 'سلام! من Shield AI هستم. چطور می‌تونم کمک کنم؟';
  static const _greetingEn = "Hi! I'm Shield AI. How can I help you with your VPN?";

  // ignore: unused_element
  static String greetingFor(String locale) =>
      locale == 'fa' ? _greetingFa : _greetingEn;

  static Map<String, dynamic> _wrap(String s) => {'text': s};

  // ignore: unused_element
  static String encode(String s) => jsonEncode(_wrap(s));
}
