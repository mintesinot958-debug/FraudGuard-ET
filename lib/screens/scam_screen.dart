import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:speech_to_text/speech_to_text.dart';
import 'package:flutter_tts/flutter_tts.dart';
import '../l10n.dart';
import '../services/backend_api.dart';
import '../services/fraud_engine.dart';
import '../widgets/result_card.dart';

class ScamScreen extends StatefulWidget {
  const ScamScreen({super.key});
  @override
  State<ScamScreen> createState() => _ScamScreenState();
}

class _ScamScreenState extends State<ScamScreen> {
  final TextEditingController _controller = TextEditingController();
  final SpeechToText _stt = SpeechToText();
  final FlutterTts _tts = FlutterTts();

  ScamResult? res;
  String? aiResponse;
  bool _busy = false;
  bool _listening = false;
  bool _isChatMode = true;

  @override
  void initState() {
    super.initState();
    _initVoice();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _initVoice() async {
    try {
      await _stt.initialize();
      if (!kIsWeb) {
        await _tts.setLanguage("en-US");
        await _tts.setSpeechRate(0.5);
      }
    } catch (_) {}
  }

  void _clear() {
    setState(() {
      _controller.clear();
      res = null;
      aiResponse = null;
      _busy = false;
    });
  }

  Future<void> _analyzeOrChat() async {
    final text = _controller.text.trim();
    if (text.isEmpty) return;

    setState(() {
      _busy = true;
      aiResponse = null;
      res = null;
    });

    try {
      if (_isChatMode) {
        final response = await BackendApi.instance.aiChat(text);
        if (mounted) {
          setState(() => aiResponse = response);
          if (!kIsWeb) await _tts.speak(response);
        }
      } else {
        final out = FraudEngine.checkMessage(text);
        setState(() => res = out);
      }
    } on ApiException catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(error.message),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 8),
          ),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: const Text('Connection Error: Is the Backend terminal running?'),
              backgroundColor: Colors.red,
              duration: const Duration(seconds: 8)),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _listen() async {
    if (!_listening) {
      bool available = await _stt.initialize();
      if (available) {
        setState(() => _listening = true);
        _stt.listen(onResult: (val) {
          setState(() => _controller.text = val.recognizedWords);
        });
      }
    } else {
      setState(() => _listening = false);
      await _stt.stop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                _isChatMode ? 'AI Voice Assistant' : 'Message Analyzer',
                style: theme.textTheme.headlineSmall
                    ?.copyWith(fontWeight: FontWeight.bold),
              ),
              Switch(
                activeThumbColor: theme.colorScheme.primary,
                value: _isChatMode,
                onChanged: (v) => setState(() {
                  _isChatMode = v;
                  _clear();
                }),
              ),
            ],
          ),
          const SizedBox(height: 24),
          Stack(
            children: [
              TextField(
                controller: _controller,
                maxLines: _isChatMode ? 3 : 8,
                decoration: InputDecoration(
                  hintText: _isChatMode
                      ? 'Ask about fraud safety...'
                      : L.t('paste_msg'),
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(20)),
                  filled: true,
                  fillColor: theme.colorScheme.surfaceContainerHighest
                      .withValues(alpha: 0.3),
                ),
              ),
              Positioned(
                right: 8,
                bottom: 8,
                child: Row(
                  children: [
                    if (!kIsWeb)
                      IconButton(
                        onPressed: _listen,
                        icon: Icon(_listening ? Icons.mic : Icons.mic_none,
                            color: _listening ? Colors.red : null),
                      ),
                    if (_controller.text.isNotEmpty)
                      IconButton(
                          onPressed: _clear,
                          icon: const Icon(Icons.close_rounded)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          ValueListenableBuilder<TextEditingValue>(
            valueListenable: _controller,
            builder: (context, value, child) {
              final bool hasText = value.text.trim().isNotEmpty;
              return FilledButton.icon(
                onPressed: (_busy || !hasText) ? null : _analyzeOrChat,
                icon: _busy
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white))
                    : Icon(_isChatMode
                        ? Icons.auto_awesome
                        : Icons.analytics_outlined),
                label: Text(_busy
                    ? 'THINKING...'
                    : (_isChatMode ? 'ASK FRAUDGUARD AI' : L.t('check'))
                        .toUpperCase()),
              );
            },
          ),
          const SizedBox(height: 32),
          if (aiResponse != null)
            Card(
              elevation: 0,
              color: theme.colorScheme.primaryContainer.withValues(alpha: 0.2),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(24),
                  side: BorderSide(
                      color: theme.colorScheme.primary.withValues(alpha: 0.1))),
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.bolt, color: Colors.amber),
                        const SizedBox(width: 8),
                        Text('AI RESPONSE',
                            style: theme.textTheme.labelLarge
                                ?.copyWith(fontWeight: FontWeight.bold)),
                        const Spacer(),
                        IconButton(
                            onPressed: () => _tts.speak(aiResponse!),
                            icon: const Icon(Icons.volume_up, size: 20)),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Text(aiResponse!,
                        style: const TextStyle(fontSize: 16, height: 1.5)),
                  ],
                ),
              ),
            ),
          if (!_isChatMode && res != null) ...[
            ResultCard(
              title: res!.label.name.toUpperCase(),
              color: res!.label == ScamLabel.safe
                  ? Colors.green
                  : (res!.label == ScamLabel.scam ? Colors.red : Colors.orange),
              score: res!.score,
              reasons:
                  res!.reasons.isEmpty ? ['No red flags found.'] : res!.reasons,
              footer: 'Detection performed by local rules engine.',
            ),
          ],
          const SizedBox(height: 40),
        ],
      ),
    );
  }
}
