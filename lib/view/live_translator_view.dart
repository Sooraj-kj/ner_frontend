import 'dart:async'; // Import async for StreamSubscription
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
// NOTE: We are no longer using speech_to_text
// import 'package:speech_to_text/speech_to_text.dart';
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
  // ✨ RENAMED controller to be specific
  late final SonioxController _translationController;
  bool _isRecording = false;
  bool _isPaused = false;
  bool _enableDiarization = true;

  // List to accumulate all NER entities
  List<Map<String, dynamic>> _allNerEntities = [];
  // ✨ RENAMED subscription
  late StreamSubscription _nerSubscription;

  // --- Chat State ---
  // ✨ NEW: Second controller for chat STT
  late final SonioxController _chatSttController;
  final TextEditingController _chatController = TextEditingController();
  final List<Map<String, dynamic>> _chatMessages = [];
  bool _isChatListening = false;
  // ✨ NEW: Subscription for the chat controller
  late StreamSubscription _chatStreamSubscription;

  final Map<String, String> _sourceLanguages = {
    'es': 'Spanish',
    'fr': 'French',
    'de': 'German',
    'it': 'Italian',
    'pt': 'Portuguese',
    'hi': 'Hindi',
    'ml': 'Malayalam',
  };

  final String _chatApiUrl = "http://127.0.0.1:8000/chat";

  @override
  void initState() {
    super.initState();

    // --- 1. Init Translation Controller ---
    _translationController = SonioxController();
    _nerSubscription = _translationController.nerStream.listen((newEntities) {
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

    // --- 2. Init Chat STT Controller ---
    _chatSttController = SonioxController();
    // Listen to its conversation stream to get the transcription
    _chatStreamSubscription =
        _chatSttController.conversationStream.listen(_onChatResult);
  }

  @override
  void dispose() {
    _translationController.dispose();
    _chatSttController.dispose(); // ✨ NEW
    _nerSubscription.cancel();
    _chatStreamSubscription.cancel(); // ✨ NEW
    _chatController.dispose();
    super.dispose();
  }

  // --- UI Action Methods (Main Translation) ---
  void _onStart() {
    final langCodes = _sourceLanguages.keys.toList();
    // Use the translation controller
    _translationController.start(
      sourceLanguages: langCodes,
      enableSpeakerDiarization: _enableDiarization,
    );
    setState(() {
      _isRecording = true;
      _isPaused = false;
      _allNerEntities.clear();
      _chatMessages.clear();
    });
  }

  void _onStop() {
    _translationController.stop(); // Use the translation controller
    setState(() {
      _isRecording = false;
      _isPaused = false;
    });
  }

  void _onPause() {
    _translationController.pause(); // Use the translation controller
    setState(() => _isPaused = true);
  }

  void _onResume() {
    _translationController.resume(); // Use the translation controller
    setState(() => _isPaused = false);
  }

  // --- Chat Methods ---

  // This is called by the "Send" button (for TYPED text)
  void _onSendChatMessage() {
    final text = _chatController.text;
    if (text.isEmpty) return;

    // For typed messages, we DO add the user's message to the chat
    setState(() {
      _chatMessages.add({'sender': 'user', 'text': text});
    });
    _chatController.clear();

    // This now calls the new API function
    _processChatCommand(text);
  }

  // Called by the "Mic" button
  void _onToggleChatListen() async {
    if (_isChatListening) {
      // --- Stop listening for chat ---
      print("🎙️ CHAT: Stopping chat STT...");
      _chatSttController.stop();
      setState(() => _isChatListening = false);

      // ✨ FIX: RESTART the main translator after a delay
      if (_isRecording) {
        print("🎙️ MAIN: Restarting translation/NER (with delay)...");
        // ✨ Add a delay to let the chat mic release
        await Future.delayed(const Duration(milliseconds: 300));
        final langCodes = _sourceLanguages.keys.toList();
        _translationController.start(
          sourceLanguages: langCodes,
          enableSpeakerDiarization: _enableDiarization,
        );
        setState(() => _isPaused = false); // We are no longer paused
      }
    } else {
      // --- Start listening for chat ---
      print("🎙️ CHAT: Starting chat STT (with delay)...");

      // ✨ FIX: STOP the main translator
      if (_isRecording && !_isPaused) {
        print("🎙️ MAIN: Stopping translation/NER to free mic...");
        _translationController.stop();
      }

      // ✨ Add a delay to let the main mic release
      await Future.delayed(const Duration(milliseconds: 300));

      // Now it's safe to start the chat controller
      setState(() => _isChatListening = true);
      _chatSttController.start(
        sourceLanguages: ['en'],
        enableSpeakerDiarization: false,
      );
    }
  }

  // Listener for the chat controller's stream (for SPOKEN text)
  void _onChatResult(List<ConversationEntry> entries) async {
    if (!_isChatListening || entries.isEmpty) return;

    final command = entries.last.original;
    print("🎙️ CHAT: Received command: '$command'");

    if (command.isNotEmpty) {
      // 1. Stop the chat controller
      print("🎙️ CHAT: Command received. Stopping chat STT.");
      _chatSttController.stop();
      setState(() {
        _isChatListening = false;
      });

      // 2. Send the command to Gemini
      print("🎙️ CHAT: Processing command with Gemini...");
      // ✨ Await the Gemini call. This gives a natural delay.
      _processChatCommand(command);

      // 3. ✨ FIX: RESTART the main translator automatically
      if (_isRecording) {
        print("🎙️ MAIN: Restarting translation/NER...");
        // You can add another small delay here if needed, but awaiting
        // _processChatCommand is often enough.
        // await Future.delayed(const Duration(milliseconds: 100)); 
        final langCodes = _sourceLanguages.keys.toList();
        _translationController.start(
          sourceLanguages: langCodes,
          enableSpeakerDiarization: _enableDiarization,
        );
        setState(() => _isPaused = false); // We are no longer paused
      }
    }
  }

  // This function calls your Gemini backend (Unchanged)
  Future<void> _processChatCommand(String command) async {
    // 1. Create the request body
    final requestBody = json.encode({
      'command': command,
      'context': _allNerEntities // Send the current list as context
    });

    // ✨ Use the specific catch blocks from before
    try {
      // 2. Make the HTTP POST request
      final response = await http.post(
        Uri.parse(_chatApiUrl),
        headers: {'Content-Type': 'application/json'},
        body: requestBody,
      );

      if (response.statusCode == 200) {
        // ... (rest of the logic is the same)
        final dynamic responseData = json.decode(response.body);
        if (responseData is List) {
          final newList = List<Map<String, dynamic>>.from(responseData);
          if (newList.isNotEmpty && newList.first['label'] == 'ASSISTANT') {
            _addBotResponse(newList.first['text']);
          } else {
            setState(() {
              _allNerEntities = newList;
            });
            _addBotResponse("Done.");
          }
        }
      } else {
        _addBotResponse(
            "Error: Could not reach AI assistant (Code ${response.statusCode})");
      }
    } on http.ClientException catch (clientError) {
      // This handles network errors like "Connection refused"
      print("Network error: ${clientError.message}");
      _addBotResponse("Error: Cannot connect to assistant. Is the server running?");
    } catch (e) {
      // This catches all other errors
      print("Unknown error: ${e.toString()}");
      _addBotResponse("An unknown error occurred: ${e.toString()}");
    }
  }

  // Helper to add a bot message to the chat (Unchanged)
  void _addBotResponse(String text) {
    Future.delayed(const Duration(milliseconds: 300), () {
      setState(() {
        _chatMessages.add({'sender': 'bot', 'text': text});
      });
    });
  }

  // --- Build Method (Unchanged) ---
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
                    Expanded(
                      flex: 2,
                      child: _buildConversationLog(),
                    ),
                    Expanded(
                      flex: 1,
                      child: _buildNerResults(),
                    ),
                    Expanded(
                      flex: 1,
                      child: _buildChatPanel(),
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

  // --- Config Panel (Unchanged) ---
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
    return Container(
      padding: const EdgeInsets.all(16.0),
      margin: const EdgeInsets.fromLTRB(8, 0, 8, 16),
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

  // --- Chat Panel (Unchanged) ---
  Widget _buildChatPanel() {
    return Container(
      padding: const EdgeInsets.all(16.0),
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
            'Chat Assistant',
            style: Theme.of(context)
                .textTheme
                .titleMedium
                ?.copyWith(fontWeight: FontWeight.bold),
          ),
          const Divider(),
          Expanded(
            child: _chatMessages.isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.smart_toy_outlined,
                            color: Colors.grey.shade400, size: 30),
                        const SizedBox(height: 8),
                        Text(
                          'Use the mic or text to edit entities',
                          style: TextStyle(color: Colors.grey.shade600),
                          textAlign: TextAlign.center,
                        ),
                       ],
                    ),
                  )
                : ListView.builder(
                    itemCount: _chatMessages.length,
                    itemBuilder: (context, index) {
                      final message = _chatMessages[index];
                      final isUser = message['sender'] == 'user';
                      return Align(
                        alignment:
                         isUser ? Alignment.centerRight : Alignment.centerLeft,
                        child: Container(
                          padding: const EdgeInsets.all(10),
                          margin: const EdgeInsets.symmetric(vertical: 4),
                          decoration: BoxDecoration(
                            color: isUser
                                ? Colors.blue.shade50
                                : Colors.grey.shade200,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(message['text']),
                        ),
                      );
                    },
                  ),
          ),
          const Divider(),
          _buildChatInput(), // New helper widget for the input bar
        ],
      ),
    );
  }

  // --- Chat Input (Unchanged) ---
  Widget _buildChatInput() {
    return Padding(
      padding: const EdgeInsets.only(top: 8.0),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _chatController,
              decoration: InputDecoration(
                hintText:
                    _isChatListening ? 'Listening...' : 'Type or say "remove..."',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: Colors.grey.shade400),
                ),
                contentPadding: const EdgeInsets.symmetric(horizontal: 12),
              ),
              onSubmitted: (_) => _onSendChatMessage(),
            ),
          ),
          const SizedBox(width: 8),
         IconButton(
            icon: Icon(
              _isChatListening ? Icons.mic_off_rounded : Icons.mic_rounded,
              color: _isChatListening ? Colors.red.shade700 : Colors.blue.shade700,
            ),
           iconSize: 30,
            onPressed: _onToggleChatListen, // This now uses Soniox
          ),
          IconButton(
            icon: Icon(Icons.send_rounded, color: Colors.blue.shade700),
            iconSize: 30,
            onPressed: _onSendChatMessage,
          ),
        ],
      ),
   );
  }

  // --- Color Helper (Unchanged) ---
  Color _getColorForLabel(String label) {
    switch (label) {
      // --- Med7 Labels (Prescription) ---
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

      // --- NEW ---
      case 'CUSTOM':
        return Colors.amber.shade100;

      // Default fallback
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
}