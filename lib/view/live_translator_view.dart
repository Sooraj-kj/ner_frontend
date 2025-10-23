import 'dart:async'; // Import async for StreamSubscription
import 'package:flutter/material.dart';
// Make sure this path matches your file structure
import 'package:nerfrontend/controller/soniox_controller.dart';

// 1. CONVERSATION ENTRY MODEL (Same as before)
class ConversationEntry {
  String original;
  String translation;
  String langCode;
  String speaker;
  int endMs;

  ConversationEntry({
    required this.original,
    required this.translation,
    required this.langCode,
    required this.speaker,
    required this.endMs,
  });
}

// 2. THE FLUTTER FRONTEND WIDGET
class LiveTranslatorView extends StatefulWidget {
  const LiveTranslatorView({super.key});

  @override
  State<LiveTranslatorView> createState() => _LiveTranslatorViewState();
}

class _LiveTranslatorViewState extends State<LiveTranslatorView> {
  // --- State ---
  late final SonioxController _controller;
  bool _isRecording = false;
  bool _isPaused = false;
  bool _enableDiarization = true;

  // List to accumulate all NER entities
  List<Map<String, dynamic>> _allNerEntities = [];
  // Subscription to manage the NER stream listener
  late StreamSubscription _nerSubscription;

  final Map<String, String> _sourceLanguages = {
    'es': 'Spanish',
    'fr': 'French',
    'de': 'German',
    'it': 'Italian',
    'pt': 'Portuguese',
    'hi': 'Hindi',
    'ml': 'Malayalam',
  };

  @override
  void initState() {
    super.initState();
    _controller = SonioxController();

    // More efficient listener (from previous step)
    _nerSubscription = _controller.nerStream.listen((newEntities) {
      if (newEntities.isNotEmpty) {
        final existingEntityTexts =
            _allNerEntities.map((e) => e['text']?.toString()).toSet();
        final trulyNewEntities = <Map<String, dynamic>>[];

        for (final entity in newEntities) {
          final key = entity['text']?.toString();
          if (key != null && !existingEntityTexts.contains(key)) {
            trulyNewEntities.add(entity);
            existingEntityTexts.add(key);
          }
        }

        if (trulyNewEntities.isNotEmpty) {
          setState(() {
            _allNerEntities.addAll(trulyNewEntities);
          });
        }
      }
    });
  }

  @override
  void dispose() {
    _nerSubscription.cancel(); // Cancel the subscription
    _controller.dispose();
    super.dispose();
  }

  // --- UI Action Methods (Same as before) ---
  void _onStart() {
    final langCodes = _sourceLanguages.keys.toList();
    _controller.start(
      sourceLanguages: langCodes,
      enableSpeakerDiarization: _enableDiarization,
    );
    setState(() {
      _isRecording = true;
      _isPaused = false;
      _allNerEntities.clear(); // Clear old entities on new session
    });
  }

  void _onStop() {
    _controller.stop();
    setState(() {
      _isRecording = false;
      _isPaused = false;
    });
  }

  void _onPause() {
    _controller.pause();
    setState(() => _isPaused = true);
  }

  void _onResume() {
    _controller.resume();
    setState(() => _isPaused = false);
  }

  // --- ✨ MODIFIED Build Method ---
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Live Medical Translator'),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 1,
      ),
      backgroundColor: const Color(0xFFF0F2F5),
      body: Center(
        child: ConstrainedBox(
          // ✨ CHANGED: Wider constraint for side-by-side layout
          constraints: const BoxConstraints(maxWidth: 1200),
          child: Column(
            children: [
              _buildConfigPanel(),
              _buildControls(),
              // ✨ CHANGED: Wrapped the two main sections in an Expanded Row
              Expanded(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      flex: 2, // Conversation log takes 2/3 of the space
                      child: _buildConversationLog(),
                    ),
                    Expanded(
                      flex: 1, // NER results take 1/3 of the space
                      child: _buildNerResults(),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildConfigPanel() {
    // ... (This widget is unchanged)
    return Container(
      padding: const EdgeInsets.all(16.0),
      margin: const EdgeInsets.all(16.0),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Translating to English from:',
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8.0,
            runSpacing: 4.0,
            children: _sourceLanguages.values.map((langName) {
              return Chip(
                label: Text(langName),
                backgroundColor: Colors.blue.shade50,
                labelStyle: TextStyle(color: Colors.blue.shade800),
              );
            }).toList(),
          ),
          const SizedBox(height: 12),
          SwitchListTile(
            title: const Text('Enable Speaker Diarization'),
            value: _enableDiarization,
            onChanged: _isRecording
                ? null
                : (val) => setState(() => _enableDiarization = val),
            activeThumbColor: Colors.blue.shade700,
          ),
        ],
      ),
    );
  }

  Widget _buildControls() {
    // ... (This widget is unchanged)
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          ElevatedButton.icon(
            icon: Icon(_isRecording ? Icons.stop_rounded : Icons.mic_rounded),
            label: Text(_isRecording ? 'Stop' : 'Start'),
            onPressed: _isRecording ? _onStop : _onStart,
            style: ElevatedButton.styleFrom(
              backgroundColor:
                  _isRecording ? Colors.red.shade700 : Colors.blue.shade700,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              textStyle:
                  const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
          ),
          ElevatedButton.icon(
            icon:
                Icon(_isPaused ? Icons.play_arrow_rounded : Icons.pause_rounded),
            label: Text(_isPaused ? 'Resume' : 'Pause'),
            onPressed: _isRecording ? (_isPaused ? _onResume : _onPause) : null,
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.grey.shade700,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              textStyle:
                  const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
  }

  // ✨ MODIFIED Widget
  Widget _buildConversationLog() {
    return Container(
      padding: const EdgeInsets.all(16.0),
      // ✨ CHANGED: Adjusted margin for side-by-side layout
      margin: const EdgeInsets.fromLTRB(16, 0, 8, 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: StreamBuilder<List<ConversationEntry>>(
        stream: _controller.conversationStream,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting &&
              !_isRecording) {
            return const Center(
              child: Text(
                'Press "Start" to begin...',
                style: TextStyle(fontSize: 16, color: Colors.grey),
              ),
            );
          }
          if (!snapshot.hasData || snapshot.data!.isEmpty) {
            return const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 16),
                  Text(
                    'Listening...',
                    style: TextStyle(fontSize: 16, color: Colors.grey),
                  ),
                ],
              ),
            );
          }
          final log = snapshot.data!;
          return ListView.builder(
            itemCount: log.length,
            itemBuilder: (context, index) {
              return _buildConversationBubble(log[index]);
            },
          );
        },
      ),
    );
  }

  // ✨ MODIFIED Widget
  Widget _buildNerResults() {
    return Container(
      padding: const EdgeInsets.all(16.0),
      // ✨ CHANGED: Adjusted margin for side-by-side layout
      margin: const EdgeInsets.fromLTRB(8, 0, 16, 16),
      width: double.infinity,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Medical Entities (NER)',
            style: Theme.of(context)
                .textTheme
                .titleMedium
                ?.copyWith(fontWeight: FontWeight.bold),
          ),
          const Divider(),
          Expanded(
            child: _allNerEntities.isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.translate_rounded,
                            color: Colors.grey.shade400, size: 30),
                        const SizedBox(height: 8),
                        Text(
                          _isRecording
                              ? 'Listening for entities...'
                              : 'Waiting for translated text...',
                          style: TextStyle(color: Colors.grey.shade600),
                        ),
                      ],
                    ),
                  )
                : SingleChildScrollView(
                    child: Wrap(
                      spacing: 8.0,
                      runSpacing: 4.0,
                      children: _allNerEntities.map((entity) {
                        return Tooltip(
                          message:
                              "Label: ${entity['label']}\nSource: ${entity['source']}",
                          child: Chip(
                            label: Text("${entity['text']}"),
                            backgroundColor: _getColorForLabel(entity['label']),
                            labelStyle: const TextStyle(
                                color: Colors.black,
                                fontWeight: FontWeight.w500),
                            side: BorderSide.none,
                          ),
                        );
                      }).toList(),
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  // --- (This function is unchanged) ---
  Color _getColorForLabel(String label) {
    switch (label) {
      // --- Med7 Labels (Prescription) ---
      case 'DRUG':
      case 'Medication': // From d4data model
        return Colors.blue.shade100;
      case 'DOSAGE':
      case 'Dosage': // From d4data model
        return Colors.green.shade100;
      case 'STRENGTH':
        return Colors.orange.shade100;
      case 'FORM':
        return Colors.purple.shade100;
      case 'ROUTE':
        return Colors.red.shade100;
      case 'FREQUENCY':
      case 'Frequency': // From d4data model
        return Colors.teal.shade100;
      case 'DURATION':
      case 'Duration': // From d4data model
        return Colors.indigo.shade100;

      // --- d4data/biomedical-ner-all Labels (Symptoms/Diagnosis) ---
      case 'Disease_disorder':
        return Colors.red.shade200;
      case 'Diagnostic_procedure':
        return Colors.yellow.shade200;
      case 'Lab_value':
        return Colors.cyan.shade100;
      case 'Biological_structure':
        return Colors.lime.shade200;
      case 'Clinical_event':
        return Colors.pink.shade100;

      // --- Other d4data labels ---
      case 'Age':
        return Colors.brown.shade100;
      case 'Date':
        return Colors.grey.shade300;

      // Default fallback
      default:
        return Colors.grey.shade200;
    }
  }

  // --- (This widget is unchanged) ---
  Widget _buildConversationBubble(ConversationEntry entry) {
    final isSpeakerA = (entry.speaker == '1');
    final alignment =
        isSpeakerA ? CrossAxisAlignment.start : CrossAxisAlignment.end;
    final bubbleColor =
        isSpeakerA ? Colors.blue.shade50 : Colors.green.shade50;
    final margin = isSpeakerA
        ? const EdgeInsets.only(right: 40.0)
        : const EdgeInsets.only(left: 40.0);
    final bool isPending = (entry.translation == '...');

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      margin: margin,
      child: Column(
        crossAxisAlignment: alignment,
        children: [
          Text(
            'Speaker ${entry.speaker} (${entry.langCode})',
            style: const TextStyle(fontSize: 12, color: Colors.grey),
          ),
          const SizedBox(height: 4),
          Container(
            padding: const EdgeInsets.all(12.0),
            decoration: BoxDecoration(
              color: bubbleColor,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  entry.original,
                  style: const TextStyle(fontSize: 16, color: Colors.black87),
                ),
                const Divider(height: 16, thickness: 1),
                if (isPending)
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SizedBox(
                        width: 12,
                        height: 12,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.grey.shade600),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'Translating...',
                        style: TextStyle(
                          fontSize: 16,
                          color: Colors.grey.shade600,
                          fontStyle: FontStyle.italic,
                        ),
                      ),
                    ],
                  )
                else
                  Text(
                    entry.translation,
                    style: TextStyle(
                      fontSize: 16,
                      color: Colors.black.withOpacity(0.7),
                      fontStyle: FontStyle.italic,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}