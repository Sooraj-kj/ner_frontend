// lib/controller/soniox_controller.dart

import 'dart:async';
import 'dart:convert';
import 'dart:html' as html;
import 'package:flutter/foundation.dart';
// Make sure this path is correct for your ConversationEntry model
import 'package:nerfrontend/view/live_translator_view.dart'; 
// Import for Uint8List

class SonioxController {
  // --- 🛑🛑🛑 SECURITY WARNING 🛑🛑🛑 ---
  // REVOKE THIS KEY.
  final String _apiKey = '7abd494476c52798c6d69d2153d74009615f8d51dfd07ce57ac9ab59372720bb';

  // --- Soniox WebSocket ---
  html.WebSocket? _sonioxWebSocket;
  html.MediaRecorder? _mediaRecorder;
  html.MediaStream? _mediaStream;
  final _conversationStreamController = StreamController<List<ConversationEntry>>.broadcast();
  Stream<List<ConversationEntry>> get conversationStream => _conversationStreamController.stream;

  // --- NER WebSocket ---
  html.WebSocket? _nerWebSocket;
  final String _nerApiUrl = 'ws://127.0.0.1:8000/ws/ner';
  final _nerStreamController = StreamController<List<Map<String, dynamic>>>.broadcast();
  Stream<List<Map<String, dynamic>>> get nerStream => _nerStreamController.stream;


  // Internal state
  final List<ConversationEntry> _internalLog = [];
  bool _wasLastOriginalAnAppend = false;

  Future<void> start({
    required List<String> sourceLanguages,
    bool enableSpeakerDiarization = false,
  }) async {
    _internalLog.clear();
    _wasLastOriginalAnAppend = false;

    _connectNerWebSocket();

    // --- 🚨🚨🚨 FIX THIS 🚨🚨🚨 ---
    // You MUST change 'stt-rt-preview-v2' to a model name
    // that your Soniox account has permission to use.
    final config = {
      'api_key': _apiKey,
      'model': 'stt-rt-preview', // <-- FIX THIS
      
      // --- ✨ MODIFICATION HERE ---
      // Changed 'auto' to 'webm' to match the MediaRecorder
      'audio_format': 'webm', 
      
      'sample_rate': 16000,
      'num_channels': 1,
      'enable_speaker_diarization': enableSpeakerDiarization,
      'enable_language_identification': true,
      'language_identification': {
        'languages': sourceLanguages,
      },
      'translation': {
        'type': 'one_way',
        'target_language': 'en'
      },
    };

    try {
      _sonioxWebSocket = html.WebSocket('wss://stt-rt.soniox.com/transcribe-websocket');
      _sonioxWebSocket!.onOpen.listen((event) {
        debugPrint('Soniox WebSocket open. Sending config:');
        debugPrint(jsonEncode(config));
        _sonioxWebSocket!.send(jsonEncode(config));
        _startMicrophone();
      });

      _sonioxWebSocket!.onMessage.listen((event) {
        _handleSonioxMessage(event.data as String);
      });

      _sonioxWebSocket!.onError.listen((event) {
        debugPrint('Soniox WebSocket Error: $event');
      });

      _sonioxWebSocket!.onClose.listen((event) {
        debugPrint('Soniox WebSocket closed. Code: ${event.code}, Reason: ${event.reason}');
        stop(); 
      });
    } catch (e) {
      debugPrint('Failed to connect to Soniox: $e');
    }
  }

  void _connectNerWebSocket() {
    try {
      _nerWebSocket = html.WebSocket(_nerApiUrl);
      _nerWebSocket!.onOpen.listen((event) {
        debugPrint('NER WebSocket connected.');
      });

      _nerWebSocket!.onMessage.listen((event) {
        final List<dynamic> entitiesJson = jsonDecode(event.data as String);
        final entities = entitiesJson.cast<Map<String, dynamic>>();
        _nerStreamController.add(entities); 
      });

      _nerWebSocket!.onError.listen((event) {
        debugPrint('NER WebSocket Error: $event');
      });

      _nerWebSocket!.onClose.listen((event) {
        debugPrint('NER WebSocket closed.');
      });
    } catch (e) {
      debugPrint('Failed to connect to NER WebSocket: $e');
    }
  }

  void _handleSonioxMessage(String jsonData) {
    final data = jsonDecode(jsonData);

    // Add this debug print to see *everything* Soniox sends
    debugPrint('SONIOX_MSG: $jsonData'); 

    final tokens = data['tokens'] as List;
    if (tokens.isEmpty) return; // This is a keep-alive message, ignore it

    final status = tokens.first['translation_status'];

    if (status == 'original') {
      final text = tokens.map((token) => token['text']).join('');
      final isFinal = (tokens.last['is_final'] as bool?) ?? false;

      if (isFinal && text.trim().isNotEmpty) {
        final entry = ConversationEntry(
          original: text,
          translation: '...',
          langCode: tokens.first['source_language'] ?? tokens.first['language'] ?? '',
          speaker: (tokens.first['speaker'] ?? 1).toString(),
          endMs: tokens.last['end_ms'] as int,
        );
        final startTime = tokens.first['start_ms'] as int;
        bool append = false;
        if (_internalLog.isNotEmpty) {
          final last = _internalLog.last;
          if (last.speaker == entry.speaker && last.langCode == entry.langCode && (startTime - last.endMs) < 700) {
            append = true;
          }
        }
        if (append) {
          _internalLog.last.original += ' ${entry.original}';
          _internalLog.last.endMs = entry.endMs;
          _wasLastOriginalAnAppend = true;
        } else {
          _internalLog.add(entry);
          _wasLastOriginalAnAppend = false;
        }
      }
    } else if (status == 'translation') {
      final translatedText = tokens.map((token) => token['text']).join('');
      final isFinal = (tokens.last['is_final'] as bool?) ?? false;

      if (_internalLog.isNotEmpty) {
        if (_wasLastOriginalAnAppend) {
          _internalLog.last.translation += ' $translatedText';
        } else {
          _internalLog.last.translation = translatedText;
        }

        if (isFinal && translatedText.trim().isNotEmpty) {
          String fullTranslation = _internalLog.last.translation;
          if (_nerWebSocket != null && _nerWebSocket!.readyState == html.WebSocket.OPEN) {
            _nerWebSocket!.send(fullTranslation);
            debugPrint('Sent to NER: $fullTranslation');
          }
        }
      }
    }
    _conversationStreamController.add(List.from(_internalLog));
  }

  Future<void> _startMicrophone() async {
    try {
      _mediaStream = await html.window.navigator.mediaDevices!.getUserMedia({
        'audio': {'sampleRate': 16000, 'channelCount': 1}
      });
      _mediaRecorder = html.MediaRecorder(_mediaStream!, {'mimeType': 'audio/webm'});
      
      _mediaRecorder!.addEventListener('dataavailable', (event) {
        final data = (event as dynamic).data;
        if (data != null && data.size > 0 && _sonioxWebSocket?.readyState == html.WebSocket.OPEN) {
          _sonioxWebSocket!.send(data);
        }
      });

      _mediaRecorder!.start(250); 
      debugPrint('Microphone started.');
    } catch (e) {
      debugPrint('Error starting microphone: $e');
    }
  }
  
  void pause() {
    if (_mediaRecorder != null && _mediaRecorder!.state == 'recording') {
      _mediaRecorder!.pause();
      debugPrint('Soniox recording paused.');
    }
  }

  void resume() {
    if (_mediaRecorder != null && _mediaRecorder!.state == 'paused') {
      _mediaRecorder!.resume();
      debugPrint('Soniox recording resumed.');
    }
  }

  void stop() {
    _mediaRecorder?.stop();
    _mediaStream?.getTracks().forEach((track) => track.stop());
    
    if (_sonioxWebSocket?.readyState == html.WebSocket.OPEN) {
      _sonioxWebSocket!.send(Uint8List(0)); 
      _sonioxWebSocket!.close();
    }
    
    _nerWebSocket?.close();

    _mediaRecorder = null;
    _mediaStream = null;
    _sonioxWebSocket = null; 
    _nerWebSocket = null; 
    debugPrint('All streams stopped.');
  }

  void dispose() {
    _conversationStreamController.close();
    _nerStreamController.close();
    stop();
  }
}