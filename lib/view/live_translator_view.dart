import 'dart:async';
import 'dart:convert'; // Keep for ner summary parsing
import 'package:flutter/material.dart';
// import 'package:http/http.dart' as http; // No longer needed
import 'package:nerfrontend/controller/soniox_controller.dart'; // Assuming this path

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
  late SonioxController _translationController;
  bool _isRecording = false;
  bool _isPaused = false;
  bool _enableDiarization = true;

  Map<String, dynamic> _structuredNerSummary = {
    'prescriptions': [],
    'symptoms': [],
    'scans': [],
    'follow_ups': [],
    'other': [],
  };

  late StreamSubscription _nerSubscription;

  // --- Language Config (Kept for logic, removed from UI) ---
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
    _initializeControllers();
  }

  void _initializeControllers() {
    // --- 1. Init Translation Controller ---
    _translationController = SonioxController();

    _nerSubscription = _translationController.nerStream.listen((newSummaryData) {
      // The existing merging listener logic is correct
      setState(() {
        final newParsedSummary = _parseStructuredSummary(newSummaryData);

        // A. Get existing data, but use Maps for deduplication/merging
        Map<String, Map<String, dynamic>> prescriptionMap = {
          for (var p in _structuredNerSummary['prescriptions']!)
            (p['medication'] as String): p
        };
        // USE 'symptom' AS THE KEY
        Map<String, Map<String, dynamic>> symptomMap = {
          for (var s in _structuredNerSummary['symptoms']!)
            (s['symptom'] as String): s
        };
        // USE 'text' AS THE KEY
        Map<String, Map<String, dynamic>> followUpMap = {
          for (var f in _structuredNerSummary['follow_ups']!)
            (f['text'] as String): f
        };
        // USE 'text' AS THE KEY
        List<Map<String, dynamic>> scans =
            List<Map<String, dynamic>>.from(_structuredNerSummary['scans']!);
        List<Map<String, dynamic>> other =
            List<Map<String, dynamic>>.from(_structuredNerSummary['other']!);
        Set<String> scanKeys = scans.map((s) => s['text'].toString()).toSet();
        Set<String> otherKeys =
            other.map((o) => o['text'].toString()).toSet();

        // B. Get new lists from the *parsed* incoming data
        final newPrescriptions =
            newParsedSummary['prescriptions'] as List<Map<String, dynamic>>;
        final newSymptoms =
            newParsedSummary['symptoms'] as List<Map<String, dynamic>>;
        final newScans =
            newParsedSummary['scans'] as List<Map<String, dynamic>>;
        final newFollowUps =
            newParsedSummary['follow_ups'] as List<Map<String, dynamic>>;
        final newOther =
            newParsedSummary['other'] as List<Map<String, dynamic>>;

        // C. Merge new, unique, or *better* items
        for (final newP in newPrescriptions) {
          final key = newP['medication']?.toString();
          if (key == null) continue;
          if (!prescriptionMap.containsKey(key)) {
            prescriptionMap[key] = newP;
          } else {
            final oldP = prescriptionMap[key]!;
            final oldDetails = oldP.values.where((v) => v != null).length;
            final newDetails = newP.values.where((v) => v != null).length;
            if (newDetails > oldDetails) {
              prescriptionMap[key] = newP;
            }
          }
        }
        for (final newS in newSymptoms) {
          // USE 'symptom' KEY
          final key = newS['symptom']?.toString();
          if (key == null) continue;
          if (!symptomMap.containsKey(key)) {
            symptomMap[key] = newS;
          } else {
            final oldS = symptomMap[key]!;
            if (oldS['duration'] == null && newS['duration'] != null) {
              symptomMap[key] = newS;
            }
          }
        }
        for (final newF in newFollowUps) {
          // USE 'text' KEY
          final key = newF['text']?.toString();
          if (key == null) continue;
          if (!followUpMap.containsKey(key)) {
            followUpMap[key] = newF;
          } else {
            final oldF = followUpMap[key]!;
            if (oldF['timeframe'] == null && newF['timeframe'] != null) {
              followUpMap[key] = newF;
            }
          }
        }
        for (final newS in newScans) {
          // USE 'text' KEY
          final key = newS['text']?.toString();
          if (key != null && scanKeys.add(key)) {
            scans.add(newS);
          }
        }
        for (final newO in newOther) {
          final key = newO['text']?.toString();
          if (key != null && otherKeys.add(key)) {
            other.add(newO);
          }
        }

        // D. Update the state from the maps
        _structuredNerSummary = {
          'prescriptions': prescriptionMap.values.toList(),
          'symptoms': symptomMap.values.toList(),
          'scans': scans,
          'follow_ups': followUpMap.values.toList(),
          'other': other,
        };
      });
    });
  }

  @override
  void dispose() {
    _translationController.dispose();
    _nerSubscription.cancel();
    super.dispose();
  }

  // --- PARSER (WITH FIXES) ---
  Map<String, dynamic> _parseStructuredSummary(Map<String, dynamic> data) {
    try {
      final prescriptions = (data['prescriptions'] as List? ?? [])
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();

      final symptoms = (data['symptoms'] as List? ?? [])
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();

      // Use the 'diagnostic_procedures' key from your backend
      final scans = (data['diagnostic_procedures'] as List? ?? [])
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();

      final followUps = (data['follow_ups'] as List? ?? [])
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();

      final other = (data['other'] as List? ?? [])
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();

      return {
        'prescriptions': prescriptions,
        'symptoms': symptoms,
        'scans': scans,
        'follow_ups': followUps,
        'other': other,
      };
    } catch (e) {
      print("Error parsing structured summary: $e");
      return {
        'prescriptions': <Map<String, dynamic>>[],
        'symptoms': <Map<String, dynamic>>[],
        'scans': <Map<String, dynamic>>[],
        'follow_ups': <Map<String, dynamic>>[],
        'other': <Map<String, dynamic>>[],
      };
    }
  }

  // --- UI Action Methods (Main Translation) ---

  void _onStart() {
    // 1. Dispose of old resources
    _translationController.dispose();
    _nerSubscription.cancel();

    // 2. Re-initialize controllers
    _initializeControllers();

    // 3. Start the new translation controller
    final langCodes = _sourceLanguages.keys.toList();
    _translationController.start(
      sourceLanguages: langCodes,
      enableSpeakerDiarization: _enableDiarization,
    );

    // 4. Reset the state
    setState(() {
      _isRecording = true;
      _isPaused = false;
      _structuredNerSummary = {
        'prescriptions': [],
        'symptoms': [],
        'scans': [],
        'follow_ups': [],
        'other': [],
      };
    });
  }

  void _onStop() {
    _translationController.stop(); // Stop recording
    setState(() {
      _isRecording = false;
      _isPaused = false;
    });
  }

  void _onPause() {
    _translationController.pause();
    setState(() => _isPaused = true);
  }

  void _onResume() {
    _translationController.resume();
    setState(() => _isPaused = false);
  }

  // --- Chat Methods (ALL REMOVED) ---

  // --- Build Method (MODIFIED) ---
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
          constraints: const BoxConstraints(maxWidth: 1600),
          child: Column(
            children: [
              _buildConfigPanel(),
              _buildControls(),
              Expanded(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // --- Panel 1: Conversation Log ---
                    Expanded(
                      flex: 2,
                      child: _buildConversationLog(),
                    ),
                    // --- Panel 2: NER Results ---
                    Expanded(
                      flex: 1,
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

  // --- Config Panel (MODIFIED) ---
  Widget _buildConfigPanel() {
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
          // --- Language Chips (REMOVED) ---
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

  // --- Controls (Unchanged) ---
  Widget _buildControls() {
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
            icon: Icon(_isPaused ? Icons.play_arrow_rounded : Icons.pause_rounded),
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

  // --- Conversation Log (Unchanged) ---
  Widget _buildConversationLog() {
    return Container(
      padding: const EdgeInsets.all(16.0),
      margin: const EdgeInsets.fromLTRB(16, 0, 8, 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: StreamBuilder<List<ConversationEntry>>(
        key: ValueKey(_translationController.hashCode),
        stream: _translationController.conversationStream,
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
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (_isRecording) ...[
                    const CircularProgressIndicator(),
                    const SizedBox(height: 16),
                    const Text(
                      'Listening...',
                      style: TextStyle(fontSize: 16, color: Colors.grey),
                    ),
                  ] else ...[
                    const Text(
                      'No conversation yet.',
                      style: TextStyle(fontSize: 16, color: Colors.grey),
                    ),
                  ]
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

  // --- NER Results (Unchanged) ---
  Widget _buildNerResults() {
    final prescriptions = (_structuredNerSummary['prescriptions'] as List?)
            ?.cast<Map<String, dynamic>>() ??
        [];
    final symptoms = (_structuredNerSummary['symptoms'] as List?)
            ?.cast<Map<String, dynamic>>() ??
        [];
    final scans = (_structuredNerSummary['scans'] as List?)
            ?.cast<Map<String, dynamic>>() ??
        [];
    final followUps = (_structuredNerSummary['follow_ups'] as List?)
            ?.cast<Map<String, dynamic>>() ??
        [];
    final other =
        (_structuredNerSummary['other'] as List?)?.cast<Map<String, dynamic>>() ??
            [];

    final bool isEmpty = prescriptions.isEmpty &&
        symptoms.isEmpty &&
        scans.isEmpty &&
        followUps.isEmpty &&
        other.isEmpty;

    return Container(
      padding: const EdgeInsets.all(16.0),
      // --- MODIFIED MARGIN ---
      margin: const EdgeInsets.fromLTRB(8, 0, 16, 16), // Adjusted right margin
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
            child: isEmpty
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
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (prescriptions.isNotEmpty)
                          _buildNerCategorySection(
                            title: 'Prescriptions',
                            icon: Icons.medication_rounded,
                            color: Colors.blue.shade700,
                            items: prescriptions,
                            itemWidgetBuilder: (item) =>
                                _buildPrescriptionChip(item),
                          ),
                        if (symptoms.isNotEmpty)
                          _buildNerCategorySection(
                            title: 'Symptoms & Diseases',
                            icon: Icons.coronavirus_rounded,
                            color: Colors.red.shade700,
                            items: symptoms,
                            itemWidgetBuilder: (item) =>
                                _buildSymptomChip(item),
                          ),
                        if (scans.isNotEmpty)
                          _buildNerCategorySection(
                            title: 'Scans & Procedures',
                            icon: Icons.document_scanner_rounded,
                            color: Colors.purple.shade700,
                            items: scans,
                            itemWidgetBuilder: (item) => _buildScanChip(item),
                          ),
                        if (followUps.isNotEmpty)
                          _buildNerCategorySection(
                            title: 'Follow-ups',
                            icon: Icons.event_repeat_rounded,
                            color: Colors.orange.shade700,
                            items: followUps,
                            itemWidgetBuilder: (item) =>
                                _buildFollowUpChip(item),
                          ),
                        if (other.isNotEmpty)
                          _buildNerCategorySection(
                            title: 'Other Entities',
                            icon: Icons.info_outline_rounded,
                            color: Colors.grey.shade700,
                            items: other,
                            itemWidgetBuilder: (item) => _buildOtherChip(item),
                          ),
                      ],
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  // --- Color Helper (Unchanged) ---
  Color _getColorForLabel(String label) {
    switch (label) {
      case 'DRUG':
      case 'Medication':
        return Colors.blue.shade100;
      case 'DOSAGE':
      case 'Dosage':
        return Colors.green.shade100;
      case 'STRENGTH':
        return Colors.orange.shade100;
      case 'FORM':
        return Colors.purple.shade100;
      case 'ROUTE':
        return Colors.red.shade100;
      case 'FREQUENCY':
      case 'Frequency':
        return Colors.teal.shade100;
      case 'DURATION':
      case 'Duration':
        return Colors.indigo.shade100;
      case 'Disease_disorder':
      case 'DISEASE':
        return Colors.red.shade200;
      case 'Diagnostic_procedure':
        return Colors.yellow.shade200;
      case 'Lab_value':
        return Colors.cyan.shade100;
      case 'Biological_structure':
        return Colors.lime.shade200;
      case 'Clinical_event':
        return Colors.pink.shade100;
      case 'Age':
        return Colors.brown.shade100;
      case 'Date':
        return Colors.grey.shade300;
      case 'CUSTOM':
      case 'User':
        return Colors.amber.shade100;
      default:
        return Colors.grey.shade200;
    }
  }

  // --- Conversation Bubble (Unchanged) ---
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

  // --- NER Helper Widgets (WITH FIXES) ---
  Widget _buildNerCategorySection({
    required String title,
    required IconData icon,
    required Color color,
    required List<Map<String, dynamic>> items,
    required Widget Function(Map<String, dynamic> item) itemWidgetBuilder,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: color, size: 20),
              const SizedBox(width: 8),
              Text(
                title,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: color,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8.0,
            runSpacing: 4.0,
            children: items.map(itemWidgetBuilder).toList(),
          ),
        ],
      ),
    );
  }

  Widget _buildPrescriptionChip(Map<String, dynamic> item) {
    // This widget is correct, it uses 'medication'
    final med = item['medication'] ?? 'N/A';
    final details = [
      item['strength'],
      item['dosage'],
      item['frequency'],
      item['duration'],
      item['form'],
      item['route'],
    ].where((s) => s != null && s.isNotEmpty).join(', ');

    final label = details.isEmpty ? med : '$med ($details)';

    return Tooltip(
      message: "Prescription: $label",
      child: Chip(
        label: Text(label),
        backgroundColor: Colors.blue.shade100,
        labelStyle:
            const TextStyle(color: Colors.black, fontWeight: FontWeight.w500),
        side: BorderSide.none,
      ),
    );
  }

  // --- THIS WIDGET IS NOW FIXED ---
  Widget _buildSymptomChip(Map<String, dynamic> item) {
    final sym = item['symptom'] ?? 'N/A';
    final duration = item['duration'];
    final severity = item['severity'];

    String label = sym;

    // Prepend severity if it exists
    if (severity != null && severity.isNotEmpty) {
      label = '$severity $label'; // e.g., "severe heat"
    }

    // Append duration if it exists
    if (duration != null && duration.isNotEmpty) {
      label = '$label ($duration)'; // e.g., "severe heat (two days)"
    }

    return Tooltip(
      message: "Symptom: $label",
      child: Chip(
        label: Text(label),
        backgroundColor: Colors.red.shade100,
        labelStyle:
            const TextStyle(color: Colors.black, fontWeight: FontWeight.w500),
        side: BorderSide.none,
      ),
    );
  }

  Widget _buildScanChip(Map<String, dynamic> item) {
    // The map contains 'text', 'label', 'confidence' etc.
    // We just want the 'text' key.
    final procedure = item['text'] ?? 'N/A';

    return Tooltip(
      message: "Scan/Procedure: $procedure",
      child: Chip(
        label: Text(procedure), // This will now show "MRI" or "vitamin D test"
        backgroundColor: Colors.purple.shade100,
        labelStyle:
            const TextStyle(color: Colors.black, fontWeight: FontWeight.w500),
        side: BorderSide.none,
      ),
    );
  }

  Widget _buildFollowUpChip(Map<String, dynamic> item) {
    final event = item['event'] ?? 'N/A';
    final timeframe = item['timeframe'];
    final label =
        (timeframe != null && timeframe.isNotEmpty) ? '$event ($timeframe)' : event;

    return Tooltip(
      message: "Follow-up: $label",
      child: Chip(
        label: Text(label), // This will show "Follow up (two days)"
        backgroundColor: Colors.orange.shade100,
        labelStyle:
            const TextStyle(color: Colors.black, fontWeight: FontWeight.w500),
        side: BorderSide.none,
      ),
    );
  }

  Widget _buildOtherChip(Map<String, dynamic> item) {
    return Tooltip(
      message: "Label: ${item['label']}\nSource: ${item['source'] ?? 'N/VER'}",
      child: Chip(
        label: Text("${item['text']}"),
        backgroundColor: _getColorForLabel(item['label']),
        labelStyle:
            const TextStyle(color: Colors.black, fontWeight: FontWeight.w500),
        side: BorderSide.none,
      ),
    );
  }
}