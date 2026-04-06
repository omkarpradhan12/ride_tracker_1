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
import 'dart:math';
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
  final GlobalKey<_GPSDashboardState> _gpsDashboardKey =
      GlobalKey<_GPSDashboardState>();
  final GlobalKey<HistoryPageState> _historyKey = GlobalKey<HistoryPageState>();

  @override
  void initState() {
    super.initState();
    _setupQuickActions();
  }

  void _setupQuickActions() {
    quickActions.setShortcutItems(const <ShortcutItem>[
      ShortcutItem(
          type: 'action_start',
          localizedTitle: 'Start Ride',
          icon: 'play_arrow'),
      ShortcutItem(
          type: 'action_stop', localizedTitle: 'Stop Ride', icon: 'stop'),
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

class _GPSDashboardState extends State<GPSDashboard>
    with AutomaticKeepAliveClientMixin {
  bool isTracking = false;
  double topSpeed = 0.0;
  double totalDistance = 0.0;
  final List<LatLng> _routePoints = [];
  final List<double> _routeSegmentSpeeds = [];
  StreamSubscription<Position>? _positionStream;
  final MapController _mapController = MapController();
  LatLng? _currentLocation;
  final LatLng _defaultLocation = const LatLng(18.5204, 73.8567);

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

      final position = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.high);
      if (!mounted) return;

      setState(() {
        _currentLocation = LatLng(position.latitude, position.longitude);
      });
      _mapController.move(_currentLocation!, 16.0);
    } catch (e) {
      debugPrint("❌ Location Error: $e");
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

  Color _colorForSpeed(double speedKmH) {
    if (speedKmH <= 10.0) return Colors.red;
    if (speedKmH <= 30.0) return Colors.yellow;
    if (speedKmH <= 70.0) return Colors.green;
    return Colors.yellow;
  }

  void _onPositionUpdate(Position pos) {
    if (!mounted) return;

    LatLng newPoint = LatLng(pos.latitude, pos.longitude);
    double speedKmH = pos.speed * 3.6;

    // Filter out GPS jitter: Only update if accuracy is decent
    if (pos.accuracy > 25) return;

    setState(() {
      if (speedKmH > topSpeed) topSpeed = speedKmH;

      if (_routePoints.isNotEmpty) {
        double distanceDelta = Geolocator.distanceBetween(
          _routePoints.last.latitude,
          _routePoints.last.longitude,
          pos.latitude,
          pos.longitude,
        );

        // Only add points if moved more than 2 meters to keep polyline clean
        if (distanceDelta > 2.0) {
          totalDistance += distanceDelta;
          _routePoints.add(newPoint);
          _routeSegmentSpeeds.add(speedKmH);
        }
      } else {
        _routePoints.add(newPoint);
      }
      _currentLocation = newPoint;
    });

    _mapController.move(newPoint, 16.0);
  }

  Future<void> startRide() async {
    if (isTracking) return;

    var status = await Permission.location.request();
    if (!status.isGranted) {
      debugPrint("⚠️ Permission Denied");
      return;
    }

    setState(() {
      isTracking = true;
      _routePoints.clear();
      _routeSegmentSpeeds.clear();
      totalDistance = 0.0;
      topSpeed = 0.0;
      _elapsedTime = "00:00:00";
      _stopwatch = Stopwatch()
        ..reset()
        ..start();
      _timer = Timer.periodic(const Duration(seconds: 1), _updateTime);
    });

    LocationSettings locationSettings = (defaultTargetPlatform ==
            TargetPlatform.android)
        ? AndroidSettings(
            accuracy: LocationAccuracy.best,
            distanceFilter: 3, // Update every 3 meters
            intervalDuration: const Duration(seconds: 2),
            foregroundNotificationConfig: const ForegroundNotificationConfig(
              notificationText: "Tracking your active ride...",
              notificationTitle: "SwiftRide Live",
              enableWakeLock: true,
            ),
          )
        : const LocationSettings(
            accuracy: LocationAccuracy.best, distanceFilter: 3);

    _positionStream =
        Geolocator.getPositionStream(locationSettings: locationSettings)
            .listen(_onPositionUpdate);
    debugPrint("🛰️ Tracking Started");
  }

  Future<void> stopRide() async {
    if (!isTracking) return;

    await _positionStream?.cancel();
    _positionStream = null;
    _stopwatch.stop();
    _timer?.cancel();

    await _saveRide();
    if (mounted) setState(() => isTracking = false);
    debugPrint("🛑 Tracking Stopped");
  }

  Future<void> _saveRide() async {
    if (_routePoints.isEmpty) return;
    try {
      final dir = await getApplicationDocumentsDirectory();
      final fileName = 'ride_${DateTime.now().millisecondsSinceEpoch}.json';
      final file = File('${dir.path}/$fileName');

      final data = jsonEncode({
        'date': DateTime.now().toIso8601String(),
        'distance': totalDistance,
        'topSpeed': topSpeed,
        'duration': _elapsedTime,
        'route': _routePoints.map((p) => [p.latitude, p.longitude]).toList(),
        'segmentSpeeds': _routeSegmentSpeeds,
      });

      await file.writeAsString(data);
    } catch (e) {
      debugPrint("❌ Save error: $e");
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
                tileProvider: NetworkTileProvider(
                  headers: {'User-Agent': 'RideTracker/1.0'},
                ),
              ),
              if (_currentLocation != null)
                MarkerLayer(
                  markers: [
                    if (_routePoints.isNotEmpty) ...[
                      Marker(
                        point: _routePoints.first,
                        width: 30,
                        height: 30,
                        child: Container(
                          decoration: BoxDecoration(
                            color: Colors.green,
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.white, width: 2),
                          ),
                          child: const Icon(Icons.play_arrow, color: Colors.white, size: 16),
                        ),
                      ),
                      if (!isTracking)
                        Marker(
                          point: _routePoints.last,
                          width: 30,
                          height: 30,
                          child: Container(
                            decoration: BoxDecoration(
                              color: Colors.red,
                              shape: BoxShape.circle,
                              border: Border.all(color: Colors.white, width: 2),
                            ),
                            child: const Icon(Icons.stop, color: Colors.white, size: 16),
                          ),
                        ),
                    ],
                    Marker(
                      point: _currentLocation!,
                      width: 18,
                      height: 18,
                      child: Container(
                        decoration: BoxDecoration(
                          color: Colors.orangeAccent,
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white, width: 2),
                        ),
                      ),
                    ),
                  ],
                ),
              PolylineLayer(polylines: [
                for (int i = 1; i <= min(_routeSegmentSpeeds.length, _routePoints.length - 1); i++) ...[
                  if (_routeSegmentSpeeds[i - 1] > 70)
                    Polyline(
                      points: [_routePoints[i - 1], _routePoints[i]],
                      color: Colors.black,
                      strokeWidth: 7.0,
                    ),
                  Polyline(
                    points: [_routePoints[i - 1], _routePoints[i]],
                    color: _colorForSpeed(_routeSegmentSpeeds[i - 1]),
                    strokeWidth: 5.0,
                  ),
                ],
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
          _statHeader(
              "DISTANCE", (totalDistance / 1000).toStringAsFixed(2), "KM"),
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
      child: ElevatedButton(
        style: ElevatedButton.styleFrom(
          backgroundColor: isTracking ? Colors.redAccent : Colors.orangeAccent,
          minimumSize: const Size(double.infinity, 65),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
        ),
        onPressed: () => isTracking ? stopRide() : startRide(),
        child: Text(isTracking ? "FINISH SESSION" : "START NEW RIDE",
            style: const TextStyle(
                color: Colors.black,
                fontSize: 18,
                fontWeight: FontWeight.bold)),
      ),
    );
  }

  Widget _statHeader(String label, String val, String unit) => Expanded(
        child: Column(children: [
          Text(label,
              style: const TextStyle(
                  color: Colors.grey, fontSize: 10, letterSpacing: 1.5)),
          const SizedBox(height: 5),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(val,
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 24,
                      fontWeight: FontWeight.w900)),
              const SizedBox(width: 4),
              Text(unit,
                  style: const TextStyle(
                      color: Colors.orangeAccent,
                      fontSize: 10,
                      fontWeight: FontWeight.bold)),
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
  bool isArchiveView = false;
  bool isViewingArchived = false;
  bool isSelectionMode = false;
  Set<int> selectedRides = {};

  @override
  void initState() {
    super.initState();
    reload();
  }

  Future<void> reload({String? specificFile, bool archiveView = false}) async {
    final dir = await getApplicationDocumentsDirectory();
    setState(() {
      isArchiveView = archiveView;
      isViewingArchived = specificFile != null;
    });
    if (specificFile != null) {
      try {
        final content = await File('${dir.path}/$specificFile').readAsString();
        setState(() {
          rides = jsonDecode(content);
        });
        print("✅ Loaded archive: $specificFile with ${rides.length} rides");
      } catch (e) {
        print("❌ Error loading archive $specificFile: $e");
      }
    } else if (archiveView) {
      final dir = await getApplicationDocumentsDirectory();
      print("Dir path: ${dir.path}");
      print("All files in dir: ${Directory(dir.path).listSync().map((f) => f.path.split(Platform.pathSeparator).last).toList()}");
      final files = dir
          .listSync()
          .where((f) => f.path.endsWith('.json') && !f.path.split(Platform.pathSeparator).last.contains('ride_'))
          .toList();
      print("Files found: ${files.map((f) => f.path.split(Platform.pathSeparator).last).toList()}");
      print("📁 Loading archives, found ${files.length} files: ${files.map((f) => f.path.split(Platform.pathSeparator).last).toList()}");
      final List<dynamic> temp = [];
      for (var f in files) {
        String name = f.path.split(Platform.pathSeparator).last;
        try {
          List<dynamic> content = jsonDecode(await File(f.path).readAsString());
          DateTime date = content.map((r) => DateTime.parse(r['date'])).reduce((a, b) => a.isAfter(b) ? a : b);
          temp.add({
            'fileName': name,
            'date': date,
            'ridesCount': content.length,
          });
        } catch (e) {
          print("⚠️ Skipping invalid archive file: $name, error: $e");
        }
      }
      setState(() {
        rides = temp;
        rides.sort((a, b) => b['date'].compareTo(a['date']));
      });
      print("✅ Loaded ${rides.length} archives");
    } else {
      final files = dir
          .listSync()
          .where(
              (f) => f.path.endsWith('.json') && !f.path.split(Platform.pathSeparator).last.contains('archive_'))
          .toList();
      print("📝 Loading ride logs, found ${files.length} files");
      final List<dynamic> temp = [];
      for (var f in files) {
        try {
          Map<String, dynamic> data =
              jsonDecode(await File(f.path).readAsString());
          data['filePath'] = f.path;
          temp.add(data);
        } catch (e) {
          print("⚠️ Skipping invalid ride file: ${f.path.split(Platform.pathSeparator).last}, error: $e");
        }
      }
      setState(() {
        rides = temp;
        rides.sort((a, b) => b['date'].compareTo(a['date']));
      });
      print("✅ Loaded ${rides.length} ride logs");
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: Text(isSelectionMode ? "SELECT RIDES TO ARCHIVE" : (isArchiveView ? "ARCHIVES" : (isViewingArchived ? "ARCHIVED RIDES" : "RIDE LOGS")),
            style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.bold,
                color: Colors.white)),
        backgroundColor: Colors.black,
        actions: [
          if (isSelectionMode) ...[
            IconButton(
                icon: const Icon(Icons.close), onPressed: () => setState(() { isSelectionMode = false; selectedRides.clear(); })),
          ] else if (isArchiveView) ...[
            IconButton(
                icon: const Icon(Icons.close), onPressed: () => reload()),
          ] else if (isViewingArchived) ...[
            IconButton(
                icon: const Icon(Icons.close), onPressed: () => reload(archiveView: true)),
          ] else ...[
            IconButton(
                icon: const Icon(Icons.inventory_2, color: Colors.orangeAccent),
                onPressed: _startArchiveSelection),
            IconButton(
                icon: const Icon(Icons.archive, color: Colors.orangeAccent),
                onPressed: () => reload(archiveView: true)),
          ],
        ],
      ),
      body: rides.isEmpty
          ? const Center(
              child: Text("No records yet.",
                  style: TextStyle(color: Colors.white24)))
          : ListView.builder(
              itemCount: rides.length,
              itemBuilder: (c, i) => _buildRideCard(rides[i], i),
            ),
      floatingActionButton: isSelectionMode ? FloatingActionButton(
        onPressed: _confirmArchive,
        child: const Icon(Icons.archive),
        backgroundColor: Colors.orangeAccent,
      ) : null,
    );
  }

  Widget _buildRideCard(dynamic ride, int index) {
    if (ride.containsKey('fileName')) {
      // Archive card
      String nameWithoutExt = ride['fileName'].replaceAll('.json', '');
      List<String> parts = nameWithoutExt.split('_');
      String displayName = parts.length > 1 ? parts[1] : 'Archive';
      return GestureDetector(
        onTap: () => reload(specificFile: ride['fileName']),
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
              color: const Color(0xFF1A1A1A),
              borderRadius: BorderRadius.circular(15)),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(displayName,
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 20,
                            fontWeight: FontWeight.bold)),
                    const SizedBox(height: 4),
                    Text(
                        DateFormat('MMM dd, yyyy • hh:mm a')
                            .format(ride['date']),
                        style: const TextStyle(color: Colors.grey, fontSize: 12)),
                    const SizedBox(height: 8),
                    Text("${ride['ridesCount']} rides",
                        style: const TextStyle(
                            color: Colors.orangeAccent,
                            fontSize: 14,
                            fontWeight: FontWeight.w500)),
                  ],
                ),
              ),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    icon: const Icon(Icons.edit, color: Colors.white54),
                    onPressed: () async {
                      String? newName = await _showRenameDialog(context, ride['fileName']);
                      if (newName != null && newName.isNotEmpty) {
                        final dir = await getApplicationDocumentsDirectory();
                        String oldPath = '${dir.path}/${ride['fileName']}';
                        String nameWithoutExt = ride['fileName'].replaceAll('.json', '');
                        List<String> parts = nameWithoutExt.split('_');
                        String datePart = parts.length > 2 ? parts[2] : DateTime.now().millisecondsSinceEpoch.toString();
                        String newFileName = "archive_${newName}_${datePart}.json";
                        String newPath = '${dir.path}/$newFileName';
                        try {
                          await File(oldPath).rename(newPath);
                          print("✏️ Renamed archive from ${ride['fileName']} to $newFileName");
                          reload(archiveView: true);
                        } catch (e) {
                          print("❌ Error renaming archive: $e");
                        }
                      }
                    },
                  ),
                  IconButton(
                    icon: const Icon(Icons.delete_outline, color: Colors.white54),
                    onPressed: () async {
                      final dir = await getApplicationDocumentsDirectory();
                      await File('${dir.path}/${ride['fileName']}').delete();
                      print("🗑️ Deleted archive: ${ride['fileName']}");
                      reload(archiveView: true);
                    },
                  ),
                ],
              ),
            ],
          ),
        ),
      );
    } else {
      // Ride card
      return GestureDetector(
        onTap: isSelectionMode ? null : () => Navigator.push(context,
            MaterialPageRoute(builder: (_) => RideDetailsPage(rideData: ride))),
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
              color: const Color(0xFF1A1A1A),
              borderRadius: BorderRadius.circular(15)),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                        DateFormat('yyyy-MM-dd : hh:mm a')
                            .format(DateTime.parse(ride['date'])),
                        style: const TextStyle(color: Colors.grey, fontSize: 12)),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Text("${(ride['distance'] / 1000).toStringAsFixed(2)} KM",
                            style: const TextStyle(
                                color: Colors.white,
                                fontSize: 20,
                                fontWeight: FontWeight.bold)),
                        const SizedBox(width: 10),
                        Text(ride['duration'],
                            style: const TextStyle(
                                color: Colors.orangeAccent,
                                fontSize: 14,
                                fontWeight: FontWeight.w500)),
                      ],
                    ),
                  ],
                ),
              ),
              if (isSelectionMode) ...[
                Checkbox(
                  value: selectedRides.contains(index),
                  onChanged: (bool? value) {
                    setState(() {
                      if (value == true) {
                        selectedRides.add(index);
                      } else {
                        selectedRides.remove(index);
                      }
                    });
                  },
                  activeColor: Colors.orangeAccent,
                ),
              ] else if (!isViewingArchived) ...[
                IconButton(
                  icon: const Icon(Icons.delete_outline, color: Colors.white54),
                  onPressed: () async {
                    await File(ride['filePath']).delete();
                    reload();
                  },
                ),
              ],
            ],
          ),
        ),
      );
    }
  }

  void _startArchiveSelection() {
    setState(() {
      isSelectionMode = true;
      selectedRides.clear();
    });
  }

  void _confirmArchive() {
    if (selectedRides.isEmpty) return;
    _showArchiveNameDialog();
  }

  Future<void> _showArchiveNameDialog() async {
    String archiveName = '';
    return showDialog<void>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Name Your Archive'),
          content: TextField(
            onChanged: (value) => archiveName = value,
            decoration: const InputDecoration(hintText: 'Enter archive name'),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () {
                if (archiveName.isNotEmpty) {
                  Navigator.of(context).pop();
                  _performArchive(selectedRides, archiveName);
                }
              },
              child: const Text('Archive'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _performArchive(Set<int> selectedIndices, String name) async {
    final dir = await getApplicationDocumentsDirectory();
    List<dynamic> toArchive = selectedIndices.map((i) => rides[i]).toList();
    print("📦 Archiving ${toArchive.length} rides");
    if (toArchive.isEmpty) return;
    List<dynamic> data = [];
    for (var ride in toArchive) {
      data.add(ride);
      if (ride.containsKey('filePath')) {
        await File(ride['filePath']).delete();
        print("🗑️ Deleted ride file: ${ride['filePath'].split(Platform.pathSeparator).last}");
      }
    }
    final timestamp = DateTime.now().millisecondsSinceEpoch.toString();
    final fileName = "archive_${name}_${timestamp}.json";
    final file = File('${dir.path}/$fileName');
    print("💾 Saving archive to: ${file.path}");
    try {
      await file.writeAsString(jsonEncode(data));
      print("💾 Saved archive: $fileName with ${data.length} rides");
      print("File exists: ${file.existsSync()}");
    } catch (e) {
      print("❌ Save archive error: $e");
    }
    setState(() {
      isSelectionMode = false;
      selectedRides.clear();
    });
    await Future.delayed(const Duration(milliseconds: 100));
    reload(archiveView: true);
  }

  Future<String?> _showRenameDialog(BuildContext context, String currentName) async {
    String nameWithoutExt = currentName.replaceAll('.json', '');
    List<String> parts = nameWithoutExt.split('_');
    String name = parts.length > 1 ? parts[1] : 'Archive';
    return showDialog<String>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Rename Archive'),
          content: TextField(
            controller: TextEditingController(text: name),
            onChanged: (value) => name = value,
            decoration: const InputDecoration(hintText: 'Enter new archive name'),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(name),
              child: const Text('Rename'),
            ),
          ],
        );
      },
    );
  }
}

class RideDetailsPage extends StatefulWidget {
  final Map<String, dynamic> rideData;
  const RideDetailsPage({super.key, required this.rideData});

  @override
  State<RideDetailsPage> createState() => _RideDetailsPageState();
}

class _RideDetailsPageState extends State<RideDetailsPage> {
  late List<LatLng> route;
  late List<double> segmentSpeeds;
  late List<LatLng> stops;
  final MapController _mapController = MapController();

  Color _colorForSpeed(double speedKmH) {
    if (speedKmH <= 10.0) return Colors.red;
    if (speedKmH <= 30.0) return Colors.yellow;
    if (speedKmH <= 70.0) return Colors.green;
    return Colors.yellow;
  }

  @override
  void initState() {
    super.initState();
    route = [];
    if (widget.rideData['route'] != null) {
      for (var p in widget.rideData['route']) {
        route.add(LatLng(p[0], p[1]));
      }
    }
    segmentSpeeds = [];
    if (widget.rideData['segmentSpeeds'] != null) {
      segmentSpeeds = List<double>.from((widget.rideData['segmentSpeeds'] as List).map((e) => (e as num).toDouble()));
    }
    stops = [];
    if (widget.rideData['stops'] != null) {
      for (var p in widget.rideData['stops']) {
        stops.add(LatLng(p[0], p[1]));
      }
    }

    if (route.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _fitBounds();
      });
    }
  }

  void _fitBounds() {
    if (route.isEmpty) return;
    double minLat = route.map((p) => p.latitude).reduce(min);
    double maxLat = route.map((p) => p.latitude).reduce(max);
    double minLng = route.map((p) => p.longitude).reduce(min);
    double maxLng = route.map((p) => p.longitude).reduce(max);

    LatLngBounds bounds = LatLngBounds(
      LatLng(minLat, minLng),
      LatLng(maxLat, maxLng),
    );
    _mapController.fitCamera(
      CameraFit.bounds(bounds: bounds, padding: const EdgeInsets.all(50)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
          title: const Text("RIDE DETAILS"), backgroundColor: Colors.black),
      backgroundColor: Colors.black,
      body: Column(
        children: [
          _buildDetailHeader(),
          Expanded(
            child: route.isEmpty
                ? const Center(
                    child: Text("No path recorded",
                        style: TextStyle(color: Colors.white24)))
                : FlutterMap(
                    mapController: _mapController,
                    options: MapOptions(
                      initialCenter: route.first,
                      initialZoom: 15.0,
                    ),
                    children: [
                      TileLayer(
                        urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                        tileProvider: NetworkTileProvider(
                          headers: {'User-Agent': 'RideTracker/1.0'},
                        ),
                      ),
                      MarkerLayer(
                        markers: [
                          // Start marker
                          Marker(
                            point: route.first,
                            width: 30,
                            height: 30,
                            child: Container(
                              decoration: BoxDecoration(
                                color: Colors.green,
                                shape: BoxShape.circle,
                                border: Border.all(color: Colors.white, width: 2),
                              ),
                              child: const Icon(Icons.play_arrow, color: Colors.white, size: 16),
                            ),
                          ),
                          // End marker
                          Marker(
                            point: route.last,
                            width: 30,
                            height: 30,
                            child: Container(
                              decoration: BoxDecoration(
                                color: Colors.red,
                                shape: BoxShape.circle,
                                border: Border.all(color: Colors.white, width: 2),
                              ),
                              child: const Icon(Icons.stop, color: Colors.white, size: 16),
                            ),
                          ),
                          // Stop markers
                          ...stops.map((stopPoint) => Marker(
                            point: stopPoint,
                            width: 24,
                            height: 24,
                            child: const Icon(Icons.location_on, color: Colors.red),
                          )),
                        ],
                      ),
                      PolylineLayer(polylines: [
                        if (segmentSpeeds.isNotEmpty && route.length > 1)
                          for (int i = 1; i <= min(segmentSpeeds.length, route.length - 1); i++) ...[
                            if (segmentSpeeds[i - 1] > 70)
                              Polyline(
                                points: [route[i - 1], route[i]],
                                color: Colors.black,
                                strokeWidth: 7.0,
                              ),
                            Polyline(
                              points: [route[i - 1], route[i]],
                              color: _colorForSpeed(segmentSpeeds[i - 1]),
                              strokeWidth: 5.0,
                            ),
                          ]
                        else
                          Polyline(
                              points: route,
                              color: Colors.orangeAccent,
                              strokeWidth: 5.0),
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
          _detailTile("DISTANCE",
              "${(widget.rideData['distance'] / 1000).toStringAsFixed(2)}", "KM"),
          _detailTile("TIME", widget.rideData['duration'], ""),
          _detailTile("TOP", widget.rideData['topSpeed'].toStringAsFixed(1), "KM/H"),
        ],
      ),
    );
  }

  Widget _detailTile(String label, String val, String unit) =>
      Column(children: [
        Text(label, style: const TextStyle(color: Colors.grey, fontSize: 10)),
        Text(val,
            style: const TextStyle(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.bold)),
        if (unit.isNotEmpty)
          Text(unit,
              style: const TextStyle(color: Colors.orangeAccent, fontSize: 10)),
      ]);
}
