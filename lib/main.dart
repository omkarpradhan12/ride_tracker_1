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
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const MaterialApp(
    home: MainNavigation(),
    debugShowCheckedModeBanner: false,
  ));
}

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
    _setupQuickActions();
  }

  void _setupQuickActions() {
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
      body: IndexedStack(
        index: _currentIndex,
        children: [
          GPSDashboard(key: _gpsDashboardKey),
          HistoryPage(key: _historyKey)
        ],
      ),
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
  final List<LatLng> _routePoints = [];
  StreamSubscription<Position>? _positionStream;
  final MapController _mapController = MapController();
  LatLng? _currentLocation;
  final LatLng _defaultLocation = const LatLng(18.5204, 73.8567);
  bool _useGpxMock = false;
  Timer? _mockRouteTimer;

  Stopwatch _stopwatch = Stopwatch();
  Timer? _timer;
  String _elapsedTime = "00:00:00";

  @override
  void initState() {
    super.initState();
    _loadInitialLocation();
  }

  Future<void> _loadInitialLocation() async {
    try {
      final status = await Permission.locationWhenInUse.request();
      if (!status.isGranted) return;

      final position = await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.best);
      if (!mounted) return;

      setState(() {
        _currentLocation = LatLng(position.latitude, position.longitude);
      });

      if (_currentLocation != null) {
        _mapController.move(_currentLocation!, 16.0);
      }
    } catch (e) {
      debugPrint("Initial location error: $e");
    }
  }

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
    return "${twoDigits(duration.inHours)}:${twoDigits(duration.inMinutes.remainder(60))}:${twoDigits(duration.inSeconds.remainder(60))}";
  }

  Future<void> _toggleTracking() async {
    if (isTracking) {
      await stopRide();
    } else {
      await startRide();
    }
  }

  Future<void> _startMockRide() async {
    if (isTracking) return;
    _useGpxMock = true;
    await startRide();
  }

  Future<List<LatLng>> _parseGpxPoints() async {
    try {
      final raw = await rootBundle.loadString('test_route.gpx');
      final matches = RegExp(r'<trkpt\s+lat="([^"]+)"\s+lon="([^"]+)"', caseSensitive: false).allMatches(raw);
      return matches.map((match) {
        return LatLng(double.parse(match.group(1)!), double.parse(match.group(2)!));
      }).toList();
    } catch (e) {
      debugPrint('Failed to parse GPX: $e');
      return [];
    }
  }

  Stream<Position> _createGpxPositionStream(List<LatLng> points) {
    final controller = StreamController<Position>();
    int index = 0;

    _mockRouteTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (index >= points.length) {
        _mockRouteTimer?.cancel();
        if (!controller.isClosed) controller.close();
        return;
      }

      final point = points[index++];
      controller.add(Position(
        latitude: point.latitude,
        longitude: point.longitude,
        timestamp: DateTime.now(),
        accuracy: 1.0,
        altitude: 0.0,
        heading: 0.0,
        headingAccuracy: 0.0,
        speed: 5.0,
        speedAccuracy: 0.0,
        altitudeAccuracy: 0.0,
      ));
    });

    controller.onCancel = () {
      _mockRouteTimer?.cancel();
    };
    return controller.stream;
  }

  void _onPositionUpdate(Position pos) {
    if (!mounted) return;
    LatLng newPoint = LatLng(pos.latitude, pos.longitude);
    double speed = pos.speed * 3.6; // Convert m/s to km/h

    setState(() {
      if (speed > topSpeed) topSpeed = speed;
      if (_routePoints.isNotEmpty) {
        totalDistance += Geolocator.distanceBetween(
          _routePoints.last.latitude,
          _routePoints.last.longitude,
          pos.latitude,
          pos.longitude,
        );
      }
      _routePoints.add(newPoint);
      _currentLocation = newPoint;
    });
    _mapController.move(newPoint, 16.0);
  }

  Future<void> stopRide() async {
    if (!isTracking) return;
    await _positionStream?.cancel();
    _positionStream = null;
    _stopwatch.stop();
    _timer?.cancel();
    await _saveRide();
    if (mounted) setState(() => isTracking = false);
  }

  Future<void> startRide() async {
    if (isTracking) return;

    if (!_useGpxMock) {
      var status = await Permission.location.request();
      if (!status.isGranted) return;
    }

    if (!_useGpxMock && defaultTargetPlatform == TargetPlatform.android) {
      await Permission.notification.request();
    }

    setState(() {
      isTracking = true;
      _routePoints.clear();
      totalDistance = 0.0;
      topSpeed = 0.0;
      _elapsedTime = "00:00:00";
      _stopwatch = Stopwatch()..reset()..start();
      _timer = Timer.periodic(const Duration(seconds: 1), _updateTime);
    });

    if (_useGpxMock) {
      final points = await _parseGpxPoints();
      if (points.isEmpty) {
        debugPrint('No GPX points available for mock route.');
        await stopRide();
        return;
      }
      _positionStream = _createGpxPositionStream(points).listen(_onPositionUpdate);
    } else {
      LocationSettings locationSettings;
      if (defaultTargetPlatform == TargetPlatform.android) {
        locationSettings = AndroidSettings(
          accuracy: LocationAccuracy.best,
          distanceFilter: 0,
          intervalDuration: const Duration(seconds: 1),
          foregroundNotificationConfig: const ForegroundNotificationConfig(
            notificationText: "Tracking your ride...",
            notificationTitle: "SwiftRide Active",
            enableWakeLock: true,
          ),
        );
      } else {
        locationSettings = const LocationSettings(
          accuracy: LocationAccuracy.best,
          distanceFilter: 0,
        );
      }

      _positionStream = Geolocator.getPositionStream(locationSettings: locationSettings).listen(_onPositionUpdate);
    }
    _useGpxMock = false;
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
        _buildStatPanel(),
        Expanded(
          child: FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: _currentLocation ?? _defaultLocation,
              initialZoom: 15.0,
            ),
            children: [
              TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'com.example.swiftride',
              ),
              if (_currentLocation != null)
                MarkerLayer(
                  markers: [
                    Marker(
                      point: _currentLocation!,
                      width: 18,
                      height: 18,
                      child: Container(
                        decoration: BoxDecoration(
                          color: Colors.orangeAccent.withOpacity(0.95),
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white, width: 2),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.orangeAccent.withOpacity(0.4),
                              blurRadius: 8,
                              spreadRadius: 1,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              PolylineLayer(polylines: [
                Polyline(points: _routePoints, color: Colors.orangeAccent, strokeWidth: 5.0),
              ]),
            ],
          ),
        ),
        _buildActionButton(),
      ],
    );
  }

  Widget _buildStatPanel() {
    return Container(
      padding: const EdgeInsets.only(top: 60, bottom: 20),
      color: const Color(0xFF121212),
      child: Row(
        children: [
          _statHeader("DISTANCE", (totalDistance / 1000).toStringAsFixed(2), "KM"),
          _statHeader("TIME", _elapsedTime, "HRS"),
          _statHeader("TOP SPEED", topSpeed.toStringAsFixed(1), "KM/H"),
        ],
      ),
    );
  }

  Widget _buildActionButton() {
    return Container(
      padding: const EdgeInsets.all(25),
      color: const Color(0xFF121212),
      child: Column(
        children: [
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: isTracking ? Colors.redAccent : Colors.orangeAccent,
              minimumSize: const Size(double.infinity, 65),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
            ),
            onPressed: _toggleTracking,
            child: Text(isTracking ? "FINISH SESSION" : "START NEW RIDE",
                style: const TextStyle(color: Colors.black, fontSize: 18, fontWeight: FontWeight.bold)),
          ),
          if (kIsWeb && !isTracking)
            Padding(
              padding: const EdgeInsets.only(top: 14),
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blueGrey,
                  minimumSize: const Size(double.infinity, 55),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                ),
                onPressed: _startMockRide,
                child: const Text("PLAY MOCK GPX ROUTE",
                    style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
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
          Text(val, style: TextStyle(color: Colors.white, fontSize: val.length > 7 ? 18 : 24, fontWeight: FontWeight.w900)),
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
  void initState() {
    super.initState();
    reload();
  }

  Future<void> reload({String? specificFile}) async {
    final dir = await getApplicationDocumentsDirectory();
    if (specificFile != null) {
      final content = await File('${dir.path}/$specificFile').readAsString();
      setState(() {
        rides = jsonDecode(content);
        isArchivedView = true;
      });
    } else {
      final files = dir.listSync().where((f) => f.path.endsWith('.json') && !f.path.contains('archive_')).toList();
      final List<dynamic> temp = [];
      for (var f in files) {
        try {
          Map<String, dynamic> data = jsonDecode(await File(f.path).readAsString());
          data['filePath'] = f.path;
          temp.add(data);
        } catch (e) {
          debugPrint("Load error for ${f.path}: $e");
        }
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
        title: Text(isArchivedView ? "ARCHIVE DATA" : "RIDE LOGS",
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.white)),
        backgroundColor: Colors.black,
        actions: [
          if (isArchivedView) IconButton(icon: const Icon(Icons.close), onPressed: () => reload()),
          IconButton(icon: const Icon(Icons.inventory_2, color: Colors.orangeAccent), onPressed: _performArchive),
          IconButton(icon: const Icon(Icons.folder_zip, color: Colors.orangeAccent), onPressed: _pickArchive),
        ],
      ),
      body: rides.isEmpty
          ? const Center(child: Text("No records yet.", style: TextStyle(color: Colors.white24)))
          : ListView.builder(
              itemCount: rides.length,
              itemBuilder: (c, i) => _buildRideCard(rides[i]),
            ),
    );
  }

  Widget _buildRideCard(dynamic ride) {
    return GestureDetector(
      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => RideDetailsPage(rideData: ride))),
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(color: const Color(0xFF1A1A1A), borderRadius: BorderRadius.circular(15)),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(DateFormat('MMM dd, yyyy • hh:mm a').format(DateTime.parse(ride['date'])),
                      style: const TextStyle(color: Colors.grey, fontSize: 12)),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Text("${(ride['distance'] / 1000).toStringAsFixed(2)}",
                          style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
                      const Text(" KM", style: TextStyle(color: Colors.orangeAccent, fontSize: 10)),
                      const SizedBox(width: 15),
                      Text("${ride['duration']}", style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
                    ],
                  ),
                ],
              ),
            ),
            if (!isArchivedView)
              IconButton(
                icon: const Icon(Icons.delete_outline, color: Colors.white54),
                onPressed: () async {
                  await File(ride['filePath']).delete();
                  reload();
                },
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _performArchive() async {
    final dir = await getApplicationDocumentsDirectory();
    final files = dir.listSync().where((f) => f.path.endsWith('.json') && !f.path.contains('archive_')).toList();
    if (files.isEmpty) return;
    List<dynamic> data = [];
    for (var f in files) {
      data.add(jsonDecode(await File(f.path).readAsString()));
      await f.delete();
    }
    final name = "archive_${DateFormat('yyyy_MM_dd_HHmm').format(DateTime.now())}.json";
    await File('${dir.path}/$name').writeAsString(jsonEncode(data));
    reload();
  }

  void _pickArchive() async {
    final dir = await getApplicationDocumentsDirectory();
    final archives = dir.listSync().where((f) => f.path.contains('archive_')).toList();
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF121212),
      builder: (c) => ListView(
        children: archives
            .map((f) => ListTile(
                  title: Text(f.path.split(Platform.pathSeparator).last, style: const TextStyle(color: Colors.white)),
                  onTap: () {
                    Navigator.pop(c);
                    reload(specificFile: f.path.split(Platform.pathSeparator).last);
                  },
                ))
            .toList(),
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
        route.add(LatLng(p[0], p[1]));
      }
    }

    return Scaffold(
      appBar: AppBar(title: const Text("RIDE DETAILS"), backgroundColor: Colors.black),
      backgroundColor: Colors.black,
      body: Column(
        children: [
          _buildDetailHeader(),
          Expanded(
            child: route.isEmpty
                ? const Center(child: Text("No path recorded", style: TextStyle(color: Colors.white24)))
                : FlutterMap(
                    options: MapOptions(
                      initialCenter: route.first,
                      initialZoom: 15.0
                    ),
                    children: [
                      TileLayer(urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png'),
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

  Widget _buildDetailHeader() {
    return Container(
      padding: const EdgeInsets.all(20),
      color: const Color(0xFF121212),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _detailTile("DISTANCE", "${(rideData['distance'] / 1000).toStringAsFixed(2)}", "KM"),
          _detailTile("TIME", rideData['duration'], ""),
          _detailTile("TOP", rideData['topSpeed'].toStringAsFixed(1), "KM/H"),
        ],
      ),
    );
  }

  Widget _detailTile(String label, String val, String unit) => Column(children: [
        Text(label, style: const TextStyle(color: Colors.grey, fontSize: 10)),
        Text(val, style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
        if (unit.isNotEmpty) Text(unit, style: const TextStyle(color: Colors.orangeAccent, fontSize: 10)),
      ]);
}
