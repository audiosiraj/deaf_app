import 'dart:typed_data';
import 'dart:math';
import 'dart:async'; // Import StreamController
import 'package:flutter/material.dart';
import 'package:flutter_sound/flutter_sound.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:tflite_flutter/tflite_flutter.dart' as tfl;
import 'package:permission_handler/permission_handler.dart';

void main() {
  runApp(const SpeakerDiarizationApp());
}

class SpeakerDiarizationApp extends StatelessWidget {
  const SpeakerDiarizationApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Speaker Diarization',
      theme: ThemeData(primarySwatch: Colors.blue),
      home: const SpeakerDiarizationScreen(),
    );
  }
}

class SpeakerDiarizationScreen extends StatefulWidget {
  const SpeakerDiarizationScreen({super.key});

  @override
  _SpeakerDiarizationScreenState createState() =>
      _SpeakerDiarizationScreenState();
}

class _SpeakerDiarizationScreenState extends State<SpeakerDiarizationScreen> {
  late tfl.Interpreter _interpreter;
  final FlutterSoundRecorder _recorder = FlutterSoundRecorder();
  final stt.SpeechToText _speech = stt.SpeechToText();
  final StreamController<Uint8List> _audioStreamController = StreamController<Uint8List>(); // Create a StreamController

  List<ConversationSegment> _conversation = [];
  List<List<double>> _speakerEmbeddings = [];
  List<int> _speakerLabels = [];
  int _speakerCount = 0;
  bool _isRecording = false;
  bool _isModelLoaded = false;
  bool _isSpeechInitialized = false;
  String _statusMessage = 'Initializing...';

  static const int _embeddingSize = 512;
  static const double _dbscanEps = 0.5;
  static const int _dbscanMinSamples = 2;
  static const int _maxEmbeddings = 100;

  @override
  void initState() {
    super.initState();
    _initializeApp();
  }

  Future<void> _initializeApp() async {
    try {
      await _initRecorder();
      await _loadModel();
      await _initSpeechToText();
      setState(() => _statusMessage = 'Ready to record');
    } catch (e) {
      setState(() => _statusMessage = 'Initialization failed: $e');
    }
  }

  Future<void> _loadModel() async {
    try {
      _interpreter = await tfl.Interpreter.fromAsset('speaker_model.tflite');
      setState(() => _isModelLoaded = true);
    } catch (e) {
      throw Exception('Model loading failed: $e');
    }
  }

  Future<void> _initRecorder() async {
    final status = await Permission.microphone.request();
    if (!status.isGranted) throw Exception('Microphone permission denied');
    await _recorder.openRecorder();
  }

  Future<void> _initSpeechToText() async {
    _isSpeechInitialized = await _speech.initialize();
    if (!_isSpeechInitialized) throw Exception('Speech-to-Text failed');
  }

  Future<void> _startRecording() async {
    if (!_isModelLoaded || !_isSpeechInitialized) {
      setState(() => _statusMessage = 'Requirements not met');
      return;
    }

    try {
      await _recorder.startRecorder(
        toStream: _audioStreamController.sink, // Use the StreamController's sink
        codec: Codec.pcm16,
        sampleRate: 16000,
      );

      _speech.listen(
        onResult: (result) {
          if (result.finalResult && result.recognizedWords.isNotEmpty) {
            _addConversationSegment(result.recognizedWords);
          }
        },
        listenFor: const Duration(seconds: 30),
      );

      setState(() {
        _isRecording = true;
        _statusMessage = 'Recording...';
      });

      // Listen to the audio stream
      _audioStreamController.stream.listen(_handleAudioStream);
    } catch (e) {
      setState(() => _statusMessage = 'Recording failed: $e');
    }
  }

  void _handleAudioStream(Uint8List data) {
    _processAudioChunk(data).catchError((e) {
      debugPrint('Audio processing error: $e');
    });
  }

  Future<void> _processAudioChunk(Uint8List chunk) async {
    final embeddings = await _extractSpeakerEmbeddings(chunk);
    final speakerId = _identifySpeaker(embeddings);

    if (_conversation.isNotEmpty) {
      final lastSegment = _conversation.last;
      if (lastSegment.speakerId == speakerId) {
        setState(() => lastSegment.endTime = DateTime.now());
      }
    }
  }

  Future<List<double>> _extractSpeakerEmbeddings(Uint8List audioBytes) async {
    final input = Int16List.view(audioBytes.buffer)
        .map((sample) => sample / 32768.0)
        .toList();

    final inputTensor = input.reshape([1, input.length]);
    final outputTensor = List<double>.filled(_embeddingSize, 0)
        .reshape([1, _embeddingSize]);

    _interpreter.run(inputTensor, outputTensor);

    final embedding = outputTensor[0];
    final norm = sqrt(embedding.map((x) => x * x).reduce((a, b) => a + b));
    return embedding.map((x) => x / norm).toList();
  }

  int _identifySpeaker(List<double> newEmbedding) {
    _speakerEmbeddings.add(newEmbedding);
    if (_speakerEmbeddings.length > _maxEmbeddings) {
      _speakerEmbeddings.removeAt(0);
    }

    final clusters = _dbscan(_speakerEmbeddings, _dbscanEps, _dbscanMinSamples);
    final currentSpeakerId = clusters.last;

    if (currentSpeakerId >= _speakerCount) {
      setState(() => _speakerCount = currentSpeakerId + 1);
    }

    return currentSpeakerId;
  }

  List<int> _dbscan(List<List<double>> data, double eps, int minSamples) {
    final labels = List<int>.filled(data.length, -1);
    int clusterId = 0;

    for (int i = 0; i < data.length; i++) {
      if (labels[i] != -1) continue;

      final neighbors = _regionQuery(data, i, eps);
      if (neighbors.length < minSamples) {
        labels[i] = -1;
        continue;
      }

      labels[i] = ++clusterId;
      final seedSet = List<int>.from(neighbors);

      while (seedSet.isNotEmpty) {
        final currentPoint = seedSet.removeLast();

        if (labels[currentPoint] == -1) {
          labels[currentPoint] = clusterId;
        }

        if (labels[currentPoint] != 0) continue;

        labels[currentPoint] = clusterId;
        final newNeighbors = _regionQuery(data, currentPoint, eps);
        if (newNeighbors.length >= minSamples) {
          seedSet.addAll(newNeighbors);
        }
      }
    }
    return labels;
  }

  List<int> _regionQuery(List<List<double>> data, int pointIndex, double eps) {
    final neighbors = <int>[];
    for (int i = 0; i < data.length; i++) {
      if (_cosineSimilarity(data[pointIndex], data[i]) > (1 - eps)) {
        neighbors.add(i);
      }
    }
    return neighbors;
  }

  double _cosineSimilarity(List<double> a, List<double> b) {
    double dot = 0.0, normA = 0.0, normB = 0.0;
    for (int i = 0; i < a.length; i++) {
      dot += a[i] * b[i];
      normA += a[i] * a[i];
      normB += b[i] * b[i];
    }
    return dot / (sqrt(normA) * sqrt(normB));
  }

  void _addConversationSegment(String text) {
    final speakerId = _speakerLabels.isNotEmpty ? _speakerLabels.last : 0;
    setState(() {
      _conversation.add(ConversationSegment(
        speakerId: speakerId,
        text: text,
        startTime: DateTime.now(),
        endTime: DateTime.now(),
      ));
      _speakerLabels.add(speakerId); // Add the speakerId to the labels
    });
  }

  Future<void> _stopRecording() async {
    try {
      await _recorder.stopRecorder();
      _speech.stop();
      setState(() {
        _isRecording = false;
        _statusMessage = 'Recording stopped';
      });
    } catch (e) {
      setState(() => _statusMessage = 'Stop failed: $e');
    }
  }

  @override
  void dispose() {
    _recorder.closeRecorder();
    _interpreter.close();
    _audioStreamController.close(); // Close the StreamController
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Speaker Diarization')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12.0),
            child: Text(_statusMessage, style: const TextStyle(fontSize: 16)),
          ),
          ElevatedButton(
            onPressed: _isRecording ? _stopRecording : _startRecording,
            style: ElevatedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 32),
            ),
            child: Text(_isRecording ? 'STOP RECORDING' : 'START RECORDING'),
          ),
          Expanded(
            child: ListView.builder(
              itemCount: _conversation.length,
              itemBuilder: (context, index) {
                final segment = _conversation[index];
                return ListTile(
                  title: Text('Speaker ${segment.speakerId + 1}',
                      style: const TextStyle(fontWeight: FontWeight.bold)),
                  subtitle: Text(segment.text),
                  trailing: Text(
                    '${segment.startTime.hour}:${segment.startTime.minute.toString().padLeft(2, '0')}:${segment.startTime.second.toString().padLeft(2, '0')}',
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class ConversationSegment {
  final int speakerId;
  final String text;
  final DateTime startTime;
  DateTime endTime;

  ConversationSegment({
    required this.speakerId,
    required this.text,
    required this.startTime,
    required this.endTime,
  });
}
