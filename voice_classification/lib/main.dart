import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'dart:io';
import 'dart:convert';
import 'dart:typed_data';
import 'package:file_selector/file_selector.dart';
import 'package:http/http.dart' as http;
import 'package:permission_handler/permission_handler.dart';
import 'package:flutter_sound/flutter_sound.dart';
import 'package:path_provider/path_provider.dart';
import 'login.dart';

void main() {
  runApp(const VoiceClassifierApp());
}

class VoiceClassifierApp extends StatelessWidget {
  const VoiceClassifierApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Voice Classifier',
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color.fromARGB(255, 37, 34, 109),
          brightness: Brightness.light,
        ),
        fontFamily: 'Roboto',
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            elevation: 8,
            shadowColor: const Color.fromARGB(
              255,
              33,
              29,
              101,
            ).withOpacity(0.4),
            backgroundColor: const Color.fromARGB(255, 35, 30, 116),
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
          ),
        ),
        outlinedButtonTheme: OutlinedButtonThemeData(
          style: OutlinedButton.styleFrom(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            side: const BorderSide(
              color: Color.fromARGB(255, 62, 65, 138),
              width: 2,
            ),
            foregroundColor: const Color.fromARGB(255, 62, 65, 138),
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
          ),
        ),
      ),
      home: const LoginPage(),
    );
  }
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  FlutterSoundRecorder? _recorder;
  FlutterSoundPlayer? _player;
  late String _apiUrl;

  bool _isRecording = false;
  bool _isLoading = false;
  bool _isPlaying = false;
  String? _recordingPath;
  Duration _recordingDuration = Duration.zero;

  ClassificationResult? _result;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _recorder = FlutterSoundRecorder();
    _player = FlutterSoundPlayer();
    _initRecorder();
    _initPlayer();
    _apiUrl = 'https://mohsinramzan-audioclassification.hf.space/predict';
  }

  Future<void> _initRecorder() async {
    try {
      await _recorder?.openRecorder();
    } catch (e) {
      print('Error initializing recorder: $e');
    }
  }

  Future<void> _initPlayer() async {
    try {
      await _player?.openPlayer();
    } catch (e) {
      print('Error initializing player: $e');
    }
  }

  @override
  void dispose() {
    _recorder?.closeRecorder();
    _player?.closePlayer();
    super.dispose();
  }

  Future<void> _startRecording() async {
    if (kIsWeb) {
      setState(() {
        _errorMessage =
            'Recording is not supported on web. Please upload an audio file instead.';
      });
      return;
    }

    try {
      final status = await Permission.microphone.request();
      if (!status.isGranted) {
        setState(() {
          _errorMessage = 'Microphone permission denied';
        });
        return;
      }

      final dir = await getApplicationDocumentsDirectory();
      final path =
          '${dir.path}/audio_${DateTime.now().millisecondsSinceEpoch}.wav';

      await _recorder?.startRecorder(toFile: path, codec: Codec.pcm16WAV);

      setState(() {
        _isRecording = true;
        _recordingPath = path;
        _recordingDuration = Duration.zero;
        _errorMessage = null;
      });

      // Update duration
      while (_isRecording) {
        await Future.delayed(const Duration(milliseconds: 100));
        setState(() {
          _recordingDuration += const Duration(milliseconds: 100);
        });
      }
    } catch (e) {
      setState(() {
        _errorMessage = 'Recording error: ${e.toString()}';
      });
    }
  }

  Future<void> _stopRecording() async {
    try {
      final path = await _recorder?.stopRecorder();
      setState(() {
        _isRecording = false;
        _recordingPath = path;
      });
    } catch (e) {
      setState(() {
        _errorMessage = 'Stop recording error: ${e.toString()}';
      });
    }
  }

  Future<void> _uploadAudio(
    String? filePath, {
    Uint8List? fileBytes,
    String? fileName,
  }) async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
      _result = null;
    });

    try {
      final request = http.MultipartRequest('POST', Uri.parse(_apiUrl));

      if (kIsWeb && fileBytes != null && fileName != null) {
        // For web, use bytes
        request.files.add(
          http.MultipartFile.fromBytes('file', fileBytes, filename: fileName),
        );
      } else if (filePath != null) {
        // For mobile/desktop, use file path
        final file = File(filePath);
        request.files.add(await http.MultipartFile.fromPath('file', file.path));
      }

      final response = await request.send();
      final responseBody = await response.stream.bytesToString();

      print('API Status: ${response.statusCode}');
      print('API Response: $responseBody');

      if (response.statusCode == 200) {
        final jsonResponse = jsonDecode(responseBody);
        setState(() {
          _result = ClassificationResult.fromJson(jsonResponse);
          _isLoading = false;
        });
      } else {
        setState(() {
          _errorMessage = 'API Error: ${response.statusCode}';
          _isLoading = false;
        });
      }
    } catch (e) {
      setState(() {
        _errorMessage = 'Upload error: ${e.toString()}';
        _isLoading = false;
      });
    }
  }

  Future<void> _pickAndUploadFile() async {
    try {
      final XTypeGroup audioTypeGroup = XTypeGroup(
        label: 'audio',
        extensions: <String>['m4a', 'mp3', 'wav', 'aac', 'flac'],
      );

      final XFile? file = await openFile(
        acceptedTypeGroups: <XTypeGroup>[audioTypeGroup],
      );

      if (file != null) {
        if (kIsWeb) {
          final bytes = await file.readAsBytes();
          await _uploadAudio(null, fileBytes: bytes, fileName: file.name);
        } else {
          await _uploadAudio(file.path);
        }
      }
    } catch (e) {
      setState(() {
        _errorMessage = 'File picker error: ${e.toString()}';
      });
    }
  }

  void _clearResults() {
    setState(() {
      _result = null;
      _recordingPath = null;
      _recordingDuration = Duration.zero;
      _errorMessage = null;
    });
  }

  String _formatDuration(Duration duration) {
    final minutes = duration.inMinutes;
    final seconds = duration.inSeconds % 60;
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }

  Future<void> _playRecording() async {
    try {
      if (_recordingPath != null) {
        setState(() => _isPlaying = true);
        await _player?.startPlayer(fromURI: _recordingPath);
        Future.delayed(const Duration(seconds: 5)).then((_) {
          setState(() => _isPlaying = false);
        });
      }
    } catch (e) {
      setState(() {
        _errorMessage = 'Playback error: ${e.toString()}';
        _isPlaying = false;
      });
    }
  }

  Future<void> _stopPlayback() async {
    try {
      await _player?.stopPlayer();
      setState(() => _isPlaying = false);
    } catch (e) {
      print('Error stopping playback: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: _result != null ? _buildResultScreen() : _buildMainScreen(),
      ),
    );
  }

  Widget _buildMainScreen() {
    return SingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Header
            Column(
              children: [
                Container(
                  width: 80,
                  height: 80,
                  decoration: BoxDecoration(
                    color: Theme.of(
                      context,
                    ).colorScheme.primary.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Icon(
                    Icons.mic,
                    size: 40,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ),
                const SizedBox(height: 24),
                Text(
                  'Voice Classifier',
                  style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Classify Arabic voice genres',
                  style: Theme.of(
                    context,
                  ).textTheme.bodyMedium?.copyWith(color: Colors.grey[600]),
                ),
              ],
            ),
            const SizedBox(height: 56),

            // Recording Section
            if (!_isRecording && _recordingPath == null) ...[
              Center(
                child: Column(
                  children: [
                    Text(
                      'Record Audio',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 20),
                    ElevatedButton.icon(
                      onPressed: _startRecording,
                      icon: const Icon(Icons.mic),
                      label: const Text('Start Recording'),
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 32,
                          vertical: 16,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 48),
            ] else if (_isRecording) ...[
              Center(
                child: Container(
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: Colors.red.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Column(
                    children: [
                      const Icon(Icons.mic, size: 40, color: Colors.red),
                      const SizedBox(height: 16),
                      Text(
                        'Recording...',
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(
                              color: Colors.red,
                              fontWeight: FontWeight.bold,
                            ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        _formatDuration(_recordingDuration),
                        style: Theme.of(
                          context,
                        ).textTheme.bodyLarge?.copyWith(color: Colors.red),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 24),
              Center(
                child: ElevatedButton.icon(
                  onPressed: _stopRecording,
                  icon: const Icon(Icons.stop),
                  label: const Text('Stop Recording'),
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 32,
                      vertical: 16,
                    ),
                    backgroundColor: Colors.red,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 48),
            ] else if (_recordingPath != null && !_isLoading) ...[
              Center(
                child: Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: Colors.green.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: Colors.green.withOpacity(0.3)),
                  ),
                  child: Column(
                    children: [
                      const Icon(
                        Icons.check_circle,
                        size: 40,
                        color: Colors.green,
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'Recording Complete',
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          color: Colors.green,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        _formatDuration(_recordingDuration),
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Colors.green[700],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _isPlaying ? _stopPlayback : _playRecording,
                  icon: Icon(_isPlaying ? Icons.stop : Icons.play_arrow),
                  label: Text(_isPlaying ? 'Stop' : 'Play'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blue,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _clearResults,
                      icon: const Icon(Icons.refresh),
                      label: const Text('Re-record'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: () => _uploadAudio(_recordingPath!),
                      icon: const Icon(Icons.send),
                      label: const Text('Classify'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 48),
            ],

            // Or Divider
            if (_recordingPath == null || _isLoading)
              Column(
                children: [
                  Row(
                    children: [
                      Expanded(child: Divider(color: Colors.grey[300])),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: Text(
                          'OR',
                          style: TextStyle(color: Colors.grey[600]),
                        ),
                      ),
                      Expanded(child: Divider(color: Colors.grey[300])),
                    ],
                  ),
                  const SizedBox(height: 48),
                ],
              ),

            // Upload Section
            if (_recordingPath == null || _isLoading)
              Center(
                child: Column(
                  children: [
                    Text(
                      'Upload File',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 20),
                    ElevatedButton.icon(
                      onPressed: _isLoading ? null : _pickAndUploadFile,
                      icon: const Icon(Icons.upload_file),
                      label: const Text('Choose Audio File'),
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 32,
                          vertical: 16,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                  ],
                ),
              ),

            // Loading
            if (_isLoading) ...[
              const SizedBox(height: 32),
              Center(
                child: Column(
                  children: [
                    const CircularProgressIndicator(),
                    const SizedBox(height: 16),
                    Text(
                      'Classifying audio...',
                      style: Theme.of(
                        context,
                      ).textTheme.bodyMedium?.copyWith(color: Colors.grey[600]),
                    ),
                  ],
                ),
              ),
            ],

            // Error Message
            if (_errorMessage != null) ...[
              const SizedBox(height: 32),
              Center(
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.red.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.red.withOpacity(0.3)),
                  ),
                  child: Column(
                    children: [
                      Text(
                        'Error',
                        style: Theme.of(context).textTheme.labelMedium
                            ?.copyWith(
                              color: Colors.red,
                              fontWeight: FontWeight.bold,
                            ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        _errorMessage!,
                        style: Theme.of(
                          context,
                        ).textTheme.bodySmall?.copyWith(color: Colors.red[700]),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildResultScreen() {
    if (_result == null) return const SizedBox.shrink();

    final sortedScores = _result!.allScores.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Results',
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              IconButton(
                onPressed: _clearResults,
                icon: const Icon(Icons.close),
              ),
            ],
          ),
          const SizedBox(height: 24),

          // Main Result
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  Theme.of(context).colorScheme.primary.withOpacity(0.1),
                  Theme.of(context).colorScheme.secondary.withOpacity(0.05),
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: Theme.of(context).colorScheme.primary.withOpacity(0.2),
              ),
            ),
            child: Column(
              children: [
                Text(
                  'Detected Genre',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Colors.grey[600],
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  _result!.label,
                  style: Theme.of(context).textTheme.displaySmall?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.check_circle, color: Colors.green, size: 20),
                    const SizedBox(width: 8),
                    Text(
                      '${(_result!.confidence * 100).toStringAsFixed(2)}% Confidence',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        color: Colors.green[700],
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 32),

          // Confidence Scores
          Text(
            'All Scores',
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 16),
          ...sortedScores.map((entry) {
            final percentage = entry.value * 100;
            return Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        entry.key,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      Text(
                        '${percentage.toStringAsFixed(2)}%',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: LinearProgressIndicator(
                      value: entry.value,
                      minHeight: 8,
                      backgroundColor: Colors.grey[200],
                      valueColor: AlwaysStoppedAnimation<Color>(
                        entry.key == _result!.label
                            ? Theme.of(context).colorScheme.primary
                            : Theme.of(
                                context,
                              ).colorScheme.primary.withOpacity(0.4),
                      ),
                    ),
                  ),
                ],
              ),
            );
          }),

          // Spacing and action button
          const Spacer(),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _clearResults,
              icon: const Icon(Icons.add),
              label: const Text('Classify Another'),
            ),
          ),
        ],
      ),
    );
  }
}

class ClassificationResult {
  final String label;
  final double confidence;
  final Map<String, double> allScores;

  ClassificationResult({
    required this.label,
    required this.confidence,
    required this.allScores,
  });

  factory ClassificationResult.fromJson(Map<String, dynamic> json) {
    final allScores = Map<String, double>.from(
      (json['all_scores'] as Map).cast<String, dynamic>().map(
        (key, value) => MapEntry(key, (value as num).toDouble()),
      ),
    );

    return ClassificationResult(
      label: json['label'] as String,
      confidence: (json['confidence'] as num).toDouble(),
      allScores: allScores,
    );
  }
}
