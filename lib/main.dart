import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:flutter_sound/flutter_sound.dart';
import 'dart:io';

void main() {
  runApp(const App());
}

class App extends StatelessWidget {
  const App({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(primarySwatch: Colors.blue),
      home: const MainScreen(),
    );
  }
}

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  _MainScreenState createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  int _selectedIndex = 1;

  static List<Widget> _screens = [
    const HistoryScreen(),
    const HomeScreen(),
    const SavedScreen(),
  ];

  void _onItemTapped(int index) {
    setState(() {
      _selectedIndex = index;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("App"),
      ),
      body: _screens[_selectedIndex],
      bottomNavigationBar: BottomNavigationBar(
        items: const <BottomNavigationBarItem>[
          BottomNavigationBarItem(icon: Icon(Icons.history), label: 'History'),
          BottomNavigationBarItem(icon: Icon(Icons.home), label: 'Home'),
          BottomNavigationBarItem(icon: Icon(Icons.save), label: 'Saved'),
        ],
        currentIndex: _selectedIndex,
        selectedItemColor: Colors.blue,
        onTap: _onItemTapped,
      ),
    );
  }
}

// Home Screen with Microphone Recording
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  _HomeScreenState createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  FlutterSoundRecorder? _recorder;
  bool _isRecording = false;
  String? _filePath;

  @override
  void initState() {
    super.initState();
    _initRecorder();
  }

  Future<void> _initRecorder() async {
    _recorder = FlutterSoundRecorder();
    await _recorder!.openRecorder();
    await requestMicrophonePermission();
  }

  Future<void> requestMicrophonePermission() async {
    var status = await Permission.microphone.request();
    if (!status.isGranted) {
      openAppSettings();
    }
  }

  Future<void> _toggleRecording() async {
    if (_isRecording) {
      _filePath = await _recorder!.stopRecorder();
      print("Recording saved: $_filePath");
    } else {
      Directory tempDir = Directory.systemTemp;
      _filePath = '${tempDir.path}/temp_audio.aac';
      await _recorder!.startRecorder(toFile: _filePath);
      print("Recording started...");
    }
    setState(() {
      _isRecording = !_isRecording;
    });
  }

  @override
  void dispose() {
    _recorder!.closeRecorder();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        const SizedBox(height: 100),
        Center(
          child: Container(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.blue.withOpacity(0.2),
            ),
            padding: const EdgeInsets.all(15),
            child: IconButton(
              icon: Icon(
                _isRecording ? Icons.stop : Icons.mic,
                size: 50,
                color: Colors.blue,
              ),
              onPressed: _toggleRecording,
            ),
          ),
        ),
        const SizedBox(height: 20),
        Text(
          _isRecording ? "Recording..." : "Tap mic to start recording",
          style: const TextStyle(fontSize: 16),
        ),
      ],
    );
  }
}

// History Screen
class HistoryScreen extends StatelessWidget {
  const HistoryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const Center(child: Text("History Screen"));
  }
}

// Saved Screen
class SavedScreen extends StatelessWidget {
  const SavedScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const Center(child: Text("Saved Screen"));
  }
}
