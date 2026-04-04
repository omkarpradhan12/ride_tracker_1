import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';
import 'package:path_provider/path_provider.dart';
import 'package:quick_actions/quick_actions.dart';
import 'package:intl/intl.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart'; // For TargetPlatform
import 'package:permission_handler/permission_handler.dart';

void main() => runApp(const MaterialApp(
      home: MainNavigation(),
      debugShowCheckedModeBanner: false,
    ));

class MainNavigation extends StatefulWidget {
  const MainNavigation({super.key});
  @override
  State<MainNavigation> createState() => _MainNavigationState();
}

class _MainNavigationState extends State<MainNavigation> {
  final QuickActions quickActions = const QuickActions();
  int _currentIndex = 0;
  final GlobalKey<_GPSDashboardState> _gpsDashboardKey = GlobalKey<_GPSDashboardState>();
  final GlobalKey<HistoryPageState> _historyKey = GlobalKey<HistoryPageState>();

  @override
  void initState() {
    super.initState();
    quickActions.setShortcutItems(const <ShortcutItem>[
      ShortcutItem(type: 'action_start', localizedTitle: 'Start Ride', icon: 'play_arrow'),
      ShortcutItem(type: 'action_stop', localizedTitle: 'Stop Ride', icon: 'stop'),
    ]);
    quickActions.initialize((type) {
      if (!mounted) return;
      setState(() => _currentIndex = 0);
      if (type == 'action_start') {
        _gpsDashboardKey.currentState?.startRide();
      } else if (type == 'action_stop') {
        _gpsDashboardKey.currentState?.stopRide();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: IndexedStack(index: _currentIndex, children: [GPSDashboard(key: _gpsDashboardKey), HistoryPage(key: _historyKey)]),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentIndex,
        backgroundColor: const Color(0xFF121212),
        selectedItemColor: Colors.orangeAccent,
        unselectedItemColor: Colors.white24,
        type: BottomNavigationBarType.fixed,
        onTap: (index) {
          setState(() => _currentIndex = index);
          if (index == 1) {
            _historyKey.currentState?.reload();
          }
        },
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.bolt), label: "Live"),
          BottomNavigationBarItem(icon: Icon(Icons.history), label: "Logs"),
        ],
      ),
    );
  }
}

class GPSDashboard extends StatefulWidget {
  const GPSDashboard({super.key});
  @override
  State<GPSDashboard> createState() => _GPSDashboardState();
}

class _GPSDashboardState extends State<GPSDashboard> with AutomaticKeepAliveClientMixin {
  bool isTracking = false;
  double topSpeed = 0.0;
  double totalDistance = 0.0;
  List<LatLng> _routePoints = [];
  StreamSubscription<Position>? _positionStream;
  final MapController _mapController = MapController();

  // Time Tracking Variables
  Stopwatch _stopwatch = Stopwatch();
  Timer? _timer;
  String _elapsedTime = "00:00:00";

  @override
  bool get wantKeepAlive => true;

  void _updateTime(Timer timer) {
    if (_stopwatch.isRunning) {
      setState(() {
        _elapsedTime = _formatDuration(_stopwatch.elapsed);
      });
    }
  }

  String _formatDuration(Duration duration) {
    String twoDigits(int n) => n.toString().padLeft(2, "0");
    String twoDigitMinutes = twoDigits(duration.inMinutes.remainder(60));
    String twoDigitSeconds = twoDigits(duration.inSeconds.remainder(60));
    return "${twoDigits(duration.inHours)}:$twoDigitMinutes:$twoDigitSeconds";
  }

  Future<void> _toggleTracking() async {
    if (isTracking) {
      await stopRide();
    } else {
      await startRide();
    }
  }

  Future<void> stopRide() async {
    if (!isTracking) return;
    await _positionStream?.cancel();
    _positionStream = null;
    _stopwatch.stop();
    _timer?.cancel();

    await _saveRide();

    if (mounted) {
      setState(() {
        isTracking = false;
      });
    }
  }

  Future<void> startRide() async {
    if (isTracking) return;
    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) return;
    }

    if (defaultTargetPlatform == TargetPlatform.android) {
      if (await Permission.notification.isDenied) {
        await Permission.notification.request();
      }
    }

    setState(() {
      isTracking = true;
      _routePoints.clear();
      totalDistance = 0.0;
      topSpeed = 0.0;
      _elapsedTime = "00:00:00";
      _stopwatch = Stopwatch()..start();
      _timer = Timer.periodic(const Duration(seconds: 1), _updateTime);
    });

    late LocationSettings locationSettings;
    if (defaultTargetPlatform == TargetPlatform.android) {
      locationSettings = AndroidSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 10,
        forceLocationManager: true,
        intervalDuration: const Duration(seconds: 1),
        foregroundNotificationConfig: const ForegroundNotificationConfig(
          notificationText: "Ride is ongoing in the background",
          notificationTitle: "SwiftRide Tracker",
          enableWakeLock: true,
          notificationIcon: AndroidResource(name: 'play_arrow', defType: 'drawable'),
        ),
      );
    } else if (defaultTargetPlatform == TargetPlatform.iOS || defaultTargetPlatform == TargetPlatform.macOS) {
      locationSettings = AppleSettings(
        accuracy: LocationAccuracy.high,
        activityType: ActivityType.fitness,
        distanceFilter: 10,
        pauseLocationUpdatesAutomatically: true,
        showBackgroundLocationIndicator: true,
      );
    } else {
      locationSettings = const LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 10,
      );
    }

    _positionStream = Geolocator.getPositionStream(
      locationSettings: locationSettings
    ).listen((pos) {
      if (!mounted) return;

      Future.microtask(() {
        if (mounted) {
          LatLng newPoint = LatLng(pos.latitude, pos.longitude);
          double speed = pos.speed * 3.6;

          setState(() {
            if (speed > topSpeed) topSpeed = speed;
            if (_routePoints.isNotEmpty) {
              totalDistance += Geolocator.distanceBetween(
                _routePoints.last.latitude,
                _routePoints.last.longitude,
                pos.latitude,
                pos.longitude
              );
            }
            _routePoints.add(newPoint);
          });
          _mapController.move(newPoint, 16.0);
        }
      });
    });
  }

  Future<void> _saveRide() async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final file = File('${dir.path}/ride_${DateTime.now().millisecondsSinceEpoch}.json');
      await file.writeAsString(jsonEncode({
        'date': DateTime.now().toIso8601String(),
        'distance': totalDistance,
        'topSpeed': topSpeed,
        'duration': _elapsedTime,
        'route': _routePoints.map((p) => [p.latitude, p.longitude]).toList(),
      }));
    } catch (e) {
      debugPrint("Save error: $e");
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.only(top: 60, bottom: 20),
          decoration: const BoxDecoration(color: Color(0xFF121212)),
          child: Row(
            children: [
              _statHeader("DISTANCE", "${(totalDistance / 1000).toStringAsFixed(2)}", "KM"),
              _statHeader("TIME", _elapsedTime, "HRS"), // New Time Tile
              _statHeader("TOP SPEED", topSpeed.toStringAsFixed(1), "KM/H"),
            ],
          ),
        ),
        Expanded(
          child: FlutterMap(
            mapController: _mapController,
            options: const MapOptions(
              initialCenter: LatLng(18.5204, 73.8567),
              initialZoom: 15.0,
            ),
            children: [
              TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'com.omkar.swiftride',
              ),
              PolylineLayer(polylines: [
                Polyline(points: _routePoints, color: Colors.orangeAccent, strokeWidth: 5.0),
              ]),
            ],
          ),
        ),
        Container(
          padding: const EdgeInsets.all(25),
          decoration: const BoxDecoration(color: Color(0xFF121212)),
          child: ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: isTracking ? Colors.redAccent : Colors.orangeAccent,
              minimumSize: const Size(double.infinity, 65),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
            ),
            onPressed: _toggleTracking,
            child: Text(isTracking ? "FINISH SESSION" : "START NEW RIDE",
                 style: const TextStyle(color: Colors.black, fontSize: 18, fontWeight: FontWeight.bold)),
          ),
        ),
      ],
    );
  }

  Widget _statHeader(String label, String val, String unit) => Expanded(
    child: Column(children: [
      Text(label, style: const TextStyle(color: Colors.grey, fontSize: 10, letterSpacing: 1.5)),
      const SizedBox(height: 5),
      Row(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.baseline,
        textBaseline: TextBaseline.alphabetic,
        children: [
          Text(val, style: TextStyle(color: Colors.white, fontSize: val.length > 5 ? 20 : 28, fontWeight: FontWeight.w900)),
          const SizedBox(width: 4),
          Text(unit, style: const TextStyle(color: Colors.orangeAccent, fontSize: 10, fontWeight: FontWeight.bold)),
        ],
      )
    ]),
  );

  @override
  void dispose() {
    _timer?.cancel();
    _positionStream?.cancel();
    super.dispose();
  }
}

class HistoryPage extends StatefulWidget {
  const HistoryPage({super.key});
  @override
  State<HistoryPage> createState() => HistoryPageState();
}

class HistoryPageState extends State<HistoryPage> {
  List<dynamic> rides = [];
  bool isArchivedView = false;

  @override
  void initState() { super.initState(); reload(); }

  Future<void> reload({String? specificFile}) async {
    final dir = await getApplicationDocumentsDirectory();
    if (specificFile != null) {
      final content = await File('${dir.path}/$specificFile').readAsString();
      setState(() { rides = jsonDecode(content); isArchivedView = true; });
    } else {
      final files = dir.listSync().where((f) => f.path.endsWith('.json') && !f.path.contains('archive_')).toList();
      final List<dynamic> temp = [];
      for (var f in files) {
        Map<String, dynamic> data = jsonDecode(await File(f.path).readAsString());
        data['filePath'] = f.path;
        temp.add(data);
      }
      setState(() {
        rides = temp;
        rides.sort((a, b) => b['date'].compareTo(a['date']));
        isArchivedView = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: Text(isArchivedView ? "ARCHIVE DATA" : "RIDE LOGS", style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.white)),
        backgroundColor: Colors.black,
        elevation: 0,
        actions: [
          if (isArchivedView) IconButton(icon: const Icon(Icons.close, color: Colors.white), onPressed: () => reload()),
          IconButton(icon: const Icon(Icons.inventory_2_outlined, color: Colors.orangeAccent), onPressed: _performArchive),
          IconButton(icon: const Icon(Icons.folder_zip_outlined, color: Colors.orangeAccent), onPressed: _pickArchive),
        ],
      ),
      body: rides.isEmpty
          ? const Center(child: Text("No records yet.", style: TextStyle(color: Colors.white24)))
          : ListView.builder(
              itemCount: rides.length,
              itemBuilder: (c, i) => GestureDetector(
                onTap: () {
                  Navigator.push(context, MaterialPageRoute(builder: (_) => RideDetailsPage(rideData: rides[i])));
                },
                child: Container(
                  margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(color: const Color(0xFF1A1A1A), borderRadius: BorderRadius.circular(15)),
                  child: Row(
                    children: [
                      Expanded(child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(DateFormat('MMM dd, yyyy • hh:mm a').format(DateTime.parse(rides[i]['date'])), style: const TextStyle(color: Colors.grey, fontSize: 12)),
                          const SizedBox(height: 8),
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.baseline,
                            textBaseline: TextBaseline.alphabetic,
                            children: [
                              Text("${(rides[i]['distance']/1000).toStringAsFixed(2)}", style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.w900)),
                              const Text(" KM", style: TextStyle(color: Colors.orangeAccent, fontSize: 12, fontWeight: FontWeight.bold)),
                              const SizedBox(width: 15),
                              Text("${rides[i]['duration'] ?? '--:--'}", style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold)),
                              const Text(" HRS", style: TextStyle(color: Colors.orangeAccent, fontSize: 12, fontWeight: FontWeight.bold)),
                            ],
                          ),
                        ],
                      )),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text("${rides[i]['topSpeed'].toStringAsFixed(1)} km/h", style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold)),
                          if (!isArchivedView)
                            IconButton(
                              icon: const Icon(Icons.delete_outline, color: Colors.white54),
                              onPressed: () async {
                                if (rides[i]['filePath'] != null) {
                                  await File(rides[i]['filePath']).delete();
                                  reload();
                                }
                              },
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
    );
  }

  Future<void> _performArchive() async {
    final dir = await getApplicationDocumentsDirectory();
    final files = dir.listSync().where((f) => f.path.endsWith('.json') && !f.path.contains('archive_')).toList();
    if (files.isEmpty) return;
    List<dynamic> data = [];
    for (var f in files) { data.add(jsonDecode(await File(f.path).readAsString())); await f.delete(); }
    final name = "archive_${DateFormat('yyyy_MM_dd').format(DateTime.now())}.json";
    await File('${dir.path}/$name').writeAsString(jsonEncode(data));
    reload();
  }

  void _pickArchive() async {
    final dir = await getApplicationDocumentsDirectory();
    final archives = dir.listSync().where((f) => f.path.contains('archive_')).toList();
    if (!mounted) return;
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF121212),
      builder: (c) => ListView(
        children: archives.map((f) => ListTile(
          title: Text(f.path.split(Platform.pathSeparator).last, style: const TextStyle(color: Colors.white)),
          onTap: () { Navigator.pop(c); reload(specificFile: f.path.split(Platform.pathSeparator).last); },
        )).toList(),
      ),
    );
  }
}

class RideDetailsPage extends StatelessWidget {
  final Map<String, dynamic> rideData;
  const RideDetailsPage({super.key, required this.rideData});

  @override
  Widget build(BuildContext context) {
    List<LatLng> route = [];
    if (rideData['route'] != null) {
      for (var p in rideData['route']) {
        route.add(LatLng(p[0] as double, p[1] as double));
      }
    }

    final double dist = rideData['distance'] ?? 0.0;
    final String dur = rideData['duration'] ?? '--:--';
    final double topSpeed = rideData['topSpeed'] ?? 0.0;

    return Scaffold(
      appBar: AppBar(title: const Text("RIDE DETAILS"), backgroundColor: Colors.black, iconTheme: const IconThemeData(color: Colors.white)),
      backgroundColor: Colors.black,
      body: Column(
        children: [
          Container(
             padding: const EdgeInsets.all(20),
             color: const Color(0xFF121212),
             child: Row(
               mainAxisAlignment: MainAxisAlignment.spaceEvenly,
               children: [
                 _statHeader("DISTANCE", "${(dist / 1000).toStringAsFixed(2)}", "KM"),
                 _statHeader("TIME", dur, "HRS"),
                 _statHeader("TOP SPEED", topSpeed.toStringAsFixed(1), "KM/H"),
               ],
             ),
          ),
          Expanded(
            child: route.isEmpty
                ? const Center(child: Text("Path data not available.", style: TextStyle(color: Colors.white54)))
                : FlutterMap(
                    options: MapOptions(
                      initialCenter: route.isNotEmpty ? route.first : const LatLng(0, 0),
                      initialZoom: 15.0,
                    ),
                    children: [
                      TileLayer(
                        urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                        userAgentPackageName: 'com.omkar.swiftride',
                      ),
                      PolylineLayer(polylines: [
                        Polyline(points: route, color: Colors.orangeAccent, strokeWidth: 5.0),
                      ]),
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  Widget _statHeader(String label, String val, String unit) => Expanded(
    child: Column(children: [
      Text(label, style: const TextStyle(color: Colors.grey, fontSize: 10, letterSpacing: 1.5)),
      const SizedBox(height: 5),
      Row(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.baseline,
        textBaseline: TextBaseline.alphabetic,
        children: [
          Text(val, style: TextStyle(color: Colors.white, fontSize: val.length > 5 ? 16 : 22, fontWeight: FontWeight.w900)),
          const SizedBox(width: 4),
          Text(unit, style: const TextStyle(color: Colors.orangeAccent, fontSize: 10, fontWeight: FontWeight.bold)),
        ],
      )
    ]),
  );
}
