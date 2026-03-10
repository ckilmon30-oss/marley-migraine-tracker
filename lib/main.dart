import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:location/location.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

void main() {
  runApp(const MarleyMigraineTrackerApp());
}

class MarleyMigraineTrackerApp extends StatelessWidget {
  const MarleyMigraineTrackerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Marley Migraine Tracker',
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: const Color(0xFF1F3640),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: const Color(0xFF223944),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
      home: const TrackerPage(),
    );
  }
}

class Entry {
  final DateTime time;
  final bool headache;
  final bool nausea;
  final bool flushing;
  final String intensity;
  final String pressure;
  final String food;
  final String notes;
  final String loggedBy;

  Entry({
    required this.time,
    required this.headache,
    required this.nausea,
    required this.flushing,
    required this.intensity,
    required this.pressure,
    required this.food,
    required this.notes,
    required this.loggedBy,
  });

  Map<String, dynamic> toJson() {
    return {
      'time': time.toIso8601String(),
      'headache': headache,
      'nausea': nausea,
      'flushing': flushing,
      'intensity': intensity,
      'pressure': pressure,
      'food': food,
      'notes': notes,
      'loggedBy': loggedBy,
    };
  }

  factory Entry.fromJson(Map<String, dynamic> json) {
    return Entry(
      time: DateTime.parse(json['time'] as String),
      headache: json['headache'] as bool? ?? false,
      nausea: json['nausea'] as bool? ?? false,
      flushing: json['flushing'] as bool? ?? false,
      intensity: json['intensity'] as String? ?? 'Mild',
      pressure: json['pressure'] as String? ?? '',
      food: json['food'] as String? ?? '',
      notes: json['notes'] as String? ?? '',
      loggedBy: json['loggedBy'] as String? ?? 'Dad',
    );
  }
}

class TrackerPage extends StatefulWidget {
  const TrackerPage({super.key});

  @override
  State<TrackerPage> createState() => _TrackerPageState();
}

class _TrackerPageState extends State<TrackerPage> {
  static const String entriesStorageKey = 'marley_migraine_entries';

  bool headache = false;
  bool nausea = false;
  bool flushing = false;

  String intensity = 'Mild';
  String loggedBy = 'Dad';

  final TextEditingController pressureController = TextEditingController();
  final TextEditingController foodController = TextEditingController();
  final TextEditingController notesController = TextEditingController();

  bool isLoadingPressure = false;
  bool isLoadingSavedEntries = true;
  String pressureStatus = '';

  final List<Entry> entries = [];

  final List<String> guardians = const [
    'Dad',
    'Mom',
    'Pop',
    'Day-Day',
    'Nana',
    'Hendrix',
    'Ryder',
  ];

  final List<String> intensityOptions = const [
    'Mild',
    'Moderate',
    'Severe',
  ];

  @override
  void initState() {
    super.initState();
    _initializePage();
  }

  Future<void> _initializePage() async {
    await _loadEntries();
    await fillBarometricPressureFromLocation();
  }

  @override
  void dispose() {
    pressureController.dispose();
    foodController.dispose();
    notesController.dispose();
    super.dispose();
  }

  Future<void> _loadEntries() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final savedList = prefs.getStringList(entriesStorageKey) ?? [];

      final loadedEntries = savedList
          .map((item) => Entry.fromJson(jsonDecode(item) as Map<String, dynamic>))
          .toList();

      if (!mounted) return;

      setState(() {
        entries
          ..clear()
          ..addAll(loadedEntries);
        isLoadingSavedEntries = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        isLoadingSavedEntries = false;
      });
    }
  }

  Future<void> _saveEntriesToStorage() async {
    final prefs = await SharedPreferences.getInstance();
    final encoded = entries.map((e) => jsonEncode(e.toJson())).toList();
    await prefs.setStringList(entriesStorageKey, encoded);
  }

  double _hPaToInHg(double hPa) {
    return hPa * 0.0295299830714;
  }

  Future<void> fillBarometricPressureFromLocation() async {
    if (!mounted) return;

    setState(() {
      isLoadingPressure = true;
      pressureStatus = 'Getting location...';
    });

    try {
      final location = Location();

      bool serviceEnabled = await location.serviceEnabled();
      if (!serviceEnabled) {
        serviceEnabled = await location.requestService();
        if (!serviceEnabled) {
          if (!mounted) return;
          setState(() {
            pressureStatus = 'Location services disabled';
            isLoadingPressure = false;
          });
          return;
        }
      }

      PermissionStatus permissionGranted = await location.hasPermission();
      if (permissionGranted == PermissionStatus.denied) {
        permissionGranted = await location.requestPermission();
      }

      if (permissionGranted != PermissionStatus.granted &&
          permissionGranted != PermissionStatus.grantedLimited) {
        if (!mounted) return;
        setState(() {
          pressureStatus = 'Location permission denied';
          isLoadingPressure = false;
        });
        return;
      }

      final currentLocation = await location.getLocation();
      final double? lat = currentLocation.latitude;
      final double? lon = currentLocation.longitude;

      if (lat == null || lon == null) {
        if (!mounted) return;
        setState(() {
          pressureStatus = 'Unable to read location';
          isLoadingPressure = false;
        });
        return;
      }

      if (!mounted) return;
      setState(() {
        pressureStatus = 'Fetching weather...';
      });

      final uri = Uri.parse(
        'https://api.open-meteo.com/v1/forecast'
        '?latitude=$lat'
        '&longitude=$lon'
        '&current=surface_pressure'
        '&timezone=auto',
      );

      final response = await http.get(uri);

      if (response.statusCode != 200) {
        if (!mounted) return;
        setState(() {
          pressureStatus = 'Weather lookup failed';
          isLoadingPressure = false;
        });
        return;
      }

      final Map<String, dynamic> data =
          jsonDecode(response.body) as Map<String, dynamic>;
      final current = data['current'];

      if (current == null || current['surface_pressure'] == null) {
        if (!mounted) return;
        setState(() {
          pressureStatus = 'Pressure unavailable';
          isLoadingPressure = false;
        });
        return;
      }

      final double hPa = (current['surface_pressure'] as num).toDouble();
      final double inHg = _hPaToInHg(hPa);

      pressureController.text = '${inHg.toStringAsFixed(2)} inHg';

      if (!mounted) return;
      setState(() {
        pressureStatus = 'Barometric pressure updated';
        isLoadingPressure = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        pressureStatus = 'Error loading pressure';
        isLoadingPressure = false;
      });
    }
  }

  Future<void> saveEntry() async {
    setState(() {
      entries.insert(
        0,
        Entry(
          time: DateTime.now(),
          headache: headache,
          nausea: nausea,
          flushing: flushing,
          intensity: intensity,
          pressure: pressureController.text.trim(),
          food: foodController.text.trim(),
          notes: notesController.text.trim(),
          loggedBy: loggedBy,
        ),
      );
    });

    await _saveEntriesToStorage();

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Entry saved')),
    );

    setState(() {
      headache = false;
      nausea = false;
      flushing = false;
      intensity = 'Mild';
      foodController.clear();
      notesController.clear();
      loggedBy = 'Dad';
    });

    await fillBarometricPressureFromLocation();
  }

  Future<void> emailReport() async {
    final String body = entries.isEmpty
        ? '''
Date: ${DateTime.now()}

Headache: $headache
Nausea: $nausea
Flushing: $flushing

Intensity: $intensity
Pressure: ${pressureController.text}
Food: ${foodController.text}

Notes: ${notesController.text}
Logged by: $loggedBy
'''
        : entries.map((e) {
            return '''
Date: ${e.time}

Headache: ${e.headache}
Nausea: ${e.nausea}
Flushing: ${e.flushing}

Intensity: ${e.intensity}
Pressure: ${e.pressure}
Food: ${e.food}

Notes: ${e.notes}
Logged by: ${e.loggedBy}
''';
          }).join('\n-----------------------------\n');

    final Uri uri = Uri(
      scheme: 'mailto',
      path: 'ckilmon3984@gmail.com',
      queryParameters: {
        'subject': 'Marley Migraine Log',
        'body': body,
      },
    );

    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    } else {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not open email app')),
      );
    }
  }

  String entrySummary(Entry e) {
    final List<String> symptoms = [];

    if (e.headache) symptoms.add('Headache');
    if (e.nausea) symptoms.add('Nausea');
    if (e.flushing) symptoms.add('Flushing');

    if (symptoms.isEmpty) symptoms.add('No symptoms');

    return symptoms.join(', ');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Marley Migraine Tracker'),
        centerTitle: true,
        backgroundColor: Colors.transparent,
      ),
      body: Stack(
        children: [
          Positioned.fill(
            child: Image.asset(
              'assets/images/snorlax_bg_1080x1920.png',
              fit: BoxFit.cover,
              alignment: Alignment.center,
            ),
          ),
          Positioned.fill(
            child: Container(
              color: const Color.fromRGBO(0, 0, 0, 0.60),
            ),
          ),
          SafeArea(
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                const Text(
                  'Symptoms',
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 10),
                SwitchListTile(
                  title: const Text('Headache'),
                  value: headache,
                  onChanged: (v) => setState(() => headache = v),
                ),
                SwitchListTile(
                  title: const Text('Nausea'),
                  value: nausea,
                  onChanged: (v) => setState(() => nausea = v),
                ),
                SwitchListTile(
                  title: const Text('Hot / Flushing'),
                  value: flushing,
                  onChanged: (v) => setState(() => flushing = v),
                ),
                const SizedBox(height: 10),
                const Text(
                  'Intensity',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  children: intensityOptions.map((e) {
                    return ChoiceChip(
                      label: Text(e),
                      selected: intensity == e,
                      onSelected: (_) => setState(() => intensity = e),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: pressureController,
                  decoration: const InputDecoration(
                    labelText: 'Barometric Pressure',
                  ),
                ),
                const SizedBox(height: 8),
                OutlinedButton(
                  onPressed:
                      isLoadingPressure ? null : fillBarometricPressureFromLocation,
                  child: Text(
                    isLoadingPressure
                        ? 'Loading...'
                        : 'Auto-fill from location',
                  ),
                ),
                if (pressureStatus.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(pressureStatus),
                  ),
                const SizedBox(height: 12),
                TextField(
                  controller: foodController,
                  decoration: const InputDecoration(
                    labelText: 'What he ate today',
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: notesController,
                  maxLines: 3,
                  decoration: const InputDecoration(
                    labelText: 'Notes',
                  ),
                ),
                const SizedBox(height: 16),
                const Text(
                  'Logged By',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: guardians.map((g) {
                    return ChoiceChip(
                      label: Text(g),
                      selected: loggedBy == g,
                      onSelected: (_) {
                        setState(() {
                          loggedBy = g;
                        });
                      },
                    );
                  }).toList(),
                ),
                const SizedBox(height: 20),
                ElevatedButton(
                  onPressed: saveEntry,
                  child: const Text('Save Entry'),
                ),
                const SizedBox(height: 10),
                OutlinedButton.icon(
                  onPressed: emailReport,
                  icon: const Icon(Icons.email),
                  label: const Text('Email Report'),
                ),
                const SizedBox(height: 30),
                const Text(
                  'Recent Entries',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 10),
                if (isLoadingSavedEntries)
                  const Card(
                    child: Padding(
                      padding: EdgeInsets.all(12),
                      child: Text('Loading saved entries...'),
                    ),
                  )
                else if (entries.isEmpty)
                  const Card(
                    child: Padding(
                      padding: EdgeInsets.all(12),
                      child: Text('No entries yet.'),
                    ),
                  )
                else
                  ...entries.map((e) {
                    return Card(
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              e.time.toString(),
                              style: const TextStyle(fontWeight: FontWeight.bold),
                            ),
                            const SizedBox(height: 6),
                            Text(entrySummary(e)),
                            Text('Intensity: ${e.intensity}'),
                            Text('Pressure: ${e.pressure.isEmpty ? '—' : e.pressure}'),
                            Text('Food: ${e.food.isEmpty ? '—' : e.food}'),
                            Text('Logged by: ${e.loggedBy}'),
                            if (e.notes.isNotEmpty) Text('Notes: ${e.notes}'),
                          ],
                        ),
                      ),
                    );
                  }),
              ],
            ),
          ),
        ],
      ),
    );
  }
}