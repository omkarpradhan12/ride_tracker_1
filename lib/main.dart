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
import 'package:image_picker/image_picker.dart';
import 'package:share_plus/share_plus.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

// ─────────────────────────────────────────────
// Speed color scheme — Motorcycle-tuned palette
// ─────────────────────────────────────────────
Color colorForSpeed(double speedKmH) {
  if (speedKmH <= 30.0) return const Color(0xFFFFD700);  // Gold  — Slow/Traffic
  if (speedKmH <= 55.0) return const Color(0xFF4CAF50);  // Green — Urban Cruising
  if (speedKmH <= 75.0) return const Color(0xFFFF8C00);  // Dark Orange — High Speed
  return const Color(0xFFE60000);                         // Electric Red — Aggressive
}

// ──────────────────────────────────────
// Data model for a photo taken on a ride
// ──────────────────────────────────────
class RidePhoto {
  final String filePath;
  final double latitude;
  final double longitude;
  final DateTime timestamp;

  RidePhoto({
    required this.filePath,
    required this.latitude,
    required this.longitude,
    required this.timestamp,
  });

  Map<String, dynamic> toJson() => {
        'filePath': filePath,
        'latitude': latitude,
        'longitude': longitude,
        'timestamp': timestamp.toIso8601String(),
      };

  factory RidePhoto.fromJson(Map<String, dynamic> json) => RidePhoto(
        filePath: json['filePath'] as String,
        latitude: (json['latitude'] as num).toDouble(),
        longitude: (json['longitude'] as num).toDouble(),
        timestamp: DateTime.parse(json['timestamp'] as String),
      );
}

// ─────────────────────────────────────────────────────────────────────────────
// NOTIFICATION SERVICE
// Wraps flutter_local_notifications and exposes pause/resume/stop actions.
// Action tap callbacks are routed back via a simple callback so GPSDashboard
// can update its own state without a global singleton holding widget refs.
// ─────────────────────────────────────────────────────────────────────────────
class RideNotificationService {
  RideNotificationService._();
  static final RideNotificationService instance = RideNotificationService._();

  static const int _notifId = 42;
  static const String _channelId = 'swiftride_tracking';
  static const String _channelName = 'SwiftRide Tracking';

  // Notification action IDs
  static const String actionPause  = 'ride_pause';
  static const String actionResume = 'ride_resume';
  static const String actionStop   = 'ride_stop';

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  VoidCallback? onPauseTapped;
  VoidCallback? onResumeTapped;
  VoidCallback? onStopTapped;

  Future<void> init() async {
    const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
    await _plugin.initialize(
      const InitializationSettings(android: androidInit),
      onDidReceiveNotificationResponse: _onAction,
      onDidReceiveBackgroundNotificationResponse: _onBackgroundAction,
    );
  }

  void _onAction(NotificationResponse r) => _dispatch(r.actionId);

  // Must be a top-level function — called from background isolate.
  // We send it back to the foreground via a MethodChannel.
  static void _onBackgroundAction(NotificationResponse r) {
    // Background isolate → foreground via platform channel
    _backgroundActionChannel.invokeMethod('notifAction', r.actionId);
  }

  // Channel used to receive background notification actions in the main isolate
  static const MethodChannel _backgroundActionChannel =
      MethodChannel('swiftride/notif_background');

  void _dispatch(String? actionId) {
    switch (actionId) {
      case actionPause:  onPauseTapped?.call();  break;
      case actionResume: onResumeTapped?.call(); break;
      case actionStop:   onStopTapped?.call();   break;
    }
  }

  // Listen for background-originated taps forwarded via the platform channel
  void listenBackgroundChannel() {
    _backgroundActionChannel.setMethodCallHandler((call) async {
      if (call.method == 'notifAction') {
        _dispatch(call.arguments as String?);
      }
    });
  }

  Future<void> showTracking({required bool isPaused}) async {
    final androidDetails = AndroidNotificationDetails(
      _channelId,
      _channelName,
      channelDescription: 'SwiftRide active ride notification',
      importance: Importance.low,         // silent — no sound
      priority: Priority.low,
      ongoing: true,                      // can't be swiped away
      showWhen: false,
      actions: [
        AndroidNotificationAction(
          isPaused ? actionResume : actionPause,
          isPaused ? '▶ Resume'  : '⏸ Pause',
          showsUserInterface: true,       // brings app to foreground
          cancelNotification: false,
        ),
        const AndroidNotificationAction(
          actionStop,
          '■ Stop',
          showsUserInterface: true,
          cancelNotification: false,
        ),
      ],
    );

    await _plugin.show(
      _notifId,
      'SwiftRide Live',
      isPaused ? 'Ride paused' : 'Tracking your active ride...',
      NotificationDetails(android: androidDetails),
    );
  }

  Future<void> dismiss() => _plugin.cancel(_notifId);
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await RideNotificationService.instance.init();
  RideNotificationService.instance.listenBackgroundChannel();
  runApp(const MaterialApp(
    home: MainNavigation(),
    debugShowCheckedModeBanner: false,
  ));
}

// ─────────────────────────────────────────────────────────────────────────────
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
          HistoryPage(key: _historyKey),
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
          if (index == 1) _historyKey.currentState?.reload();
        },
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.bolt), label: "Live"),
          BottomNavigationBarItem(icon: Icon(Icons.history), label: "Logs"),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
class GPSDashboard extends StatefulWidget {
  const GPSDashboard({super.key});
  @override
  State<GPSDashboard> createState() => _GPSDashboardState();
}

class _GPSDashboardState extends State<GPSDashboard>
    with AutomaticKeepAliveClientMixin {

  // ── State ──────────────────────────────────────────────────
  bool isTracking = false;
  bool isPaused = false;

  double topSpeed = 0.0;
  double totalDistance = 0.0;
  double _currentSpeedKmH = 0.0;

  final List<LatLng> _routePoints = [];
  final List<double> _routeSegmentSpeeds = [];
  final List<RidePhoto> _ridePhotos = [];

  StreamSubscription<Position>? _positionStream;
  final MapController _mapController = MapController();
  LatLng? _currentLocation;
  final LatLng _defaultLocation = const LatLng(18.5204, 73.8567);

  // ── Timer ──────────────────────────────────────────────────
  Stopwatch _stopwatch = Stopwatch();
  Timer? _uiTimer;
  String _elapsedTime = "00:00:00";

  // ── Camera ─────────────────────────────────────────────────
  final ImagePicker _imagePicker = ImagePicker();

  // ── Keep-alive ─────────────────────────────────────────────
  @override
  bool get wantKeepAlive => true;

  // ────────────────────────────────────────────────────────────
  @override
  void initState() {
    super.initState();
    _loadInitialLocation();
    // Wire notification action callbacks
    final notif = RideNotificationService.instance;
    notif.onPauseTapped  = () => _pauseRide();
    notif.onResumeTapped = () => _resumeRide();
    notif.onStopTapped   = () => stopRide();
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

  void _updateTime(Timer _) {
    if (_stopwatch.isRunning) {
      setState(() => _elapsedTime = _formatDuration(_stopwatch.elapsed));
    }
  }

  String _formatDuration(Duration d) {
    String pad(int n) => n.toString().padLeft(2, "0");
    return "${pad(d.inHours)}:${pad(d.inMinutes.remainder(60))}:${pad(d.inSeconds.remainder(60))}";
  }

  // ── Position handler ────────────────────────────────────────
  void _onPositionUpdate(Position pos) {
    if (!mounted) return;
    if (isPaused) return; // ignore GPS while paused

    final newPoint = LatLng(pos.latitude, pos.longitude);
    final speedKmH = pos.speed * 3.6;

    // Filter GPS jitter
    if (pos.accuracy > 25) return;

    setState(() {
      _currentSpeedKmH = speedKmH;
      if (speedKmH > topSpeed) topSpeed = speedKmH;

      if (_routePoints.isNotEmpty) {
        final distanceDelta = Geolocator.distanceBetween(
          _routePoints.last.latitude,
          _routePoints.last.longitude,
          pos.latitude,
          pos.longitude,
        );
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

  // ── Start / Stop / Pause / Resume ────────────────────────────
  Future<void> startRide() async {
    if (isTracking) return;

    final status = await Permission.location.request();
    if (!status.isGranted) {
      debugPrint("⚠️ Permission Denied");
      return;
    }

    setState(() {
      isTracking = true;
      isPaused = false;
      _routePoints.clear();
      _routeSegmentSpeeds.clear();
      _ridePhotos.clear();
      totalDistance = 0.0;
      topSpeed = 0.0;
      _currentSpeedKmH = 0.0;
      _elapsedTime = "00:00:00";
      _stopwatch = Stopwatch()
        ..reset()
        ..start();
      _uiTimer = Timer.periodic(const Duration(seconds: 1), _updateTime);
    });

    final LocationSettings locationSettings =
        (defaultTargetPlatform == TargetPlatform.android)
            ? AndroidSettings(
                accuracy: LocationAccuracy.best,
                distanceFilter: 3,
                intervalDuration: const Duration(seconds: 2),
                foregroundNotificationConfig: const ForegroundNotificationConfig(
                  // Minimal geolocator foreground service notification —
                  // the interactive one is managed by RideNotificationService.
                  notificationText: "Location in use by SwiftRide",
                  notificationTitle: "SwiftRide",
                  enableWakeLock: true,
                  notificationChannelName: 'SwiftRide Location',
                ),
              )
            : const LocationSettings(
                accuracy: LocationAccuracy.best, distanceFilter: 3);

    _positionStream =
        Geolocator.getPositionStream(locationSettings: locationSettings)
            .listen(_onPositionUpdate);

    // Show interactive notification with Pause + Stop actions
    await RideNotificationService.instance.showTracking(isPaused: false);
    debugPrint("🛰️ Tracking Started");
  }

  Future<void> stopRide() async {
    if (!isTracking) return;
    await _positionStream?.cancel();
    _positionStream = null;
    _stopwatch.stop();
    _uiTimer?.cancel();
    await RideNotificationService.instance.dismiss();
    await _saveRide();
    if (mounted) setState(() { isTracking = false; isPaused = false; });
    debugPrint("🛑 Tracking Stopped");
  }

  void _pauseRide() {
    if (!isTracking || isPaused) return;
    _stopwatch.stop();
    setState(() => isPaused = true);
    RideNotificationService.instance.showTracking(isPaused: true);
    debugPrint("⏸ Manually paused");
  }

  void _resumeRide() {
    if (!isTracking || !isPaused) return;
    _stopwatch.start();
    setState(() => isPaused = false);
    RideNotificationService.instance.showTracking(isPaused: false);
    debugPrint("▶️ Ride resumed");
  }

  // ── Photo capture ────────────────────────────────────────────
  Future<void> _capturePhoto() async {
    if (!isTracking || _currentLocation == null) return;
    try {
      final XFile? photo =
          await _imagePicker.pickImage(source: ImageSource.camera, imageQuality: 85);
      if (photo == null) return;

      final dir = await getApplicationDocumentsDirectory();
      final fileName = 'photo_${DateTime.now().millisecondsSinceEpoch}.jpg';
      final savedPath = '${dir.path}/$fileName';
      await File(photo.path).copy(savedPath);

      final ridePhoto = RidePhoto(
        filePath: savedPath,
        latitude: _currentLocation!.latitude,
        longitude: _currentLocation!.longitude,
        timestamp: DateTime.now(),
      );

      setState(() => _ridePhotos.add(ridePhoto));
      debugPrint("📸 Photo saved: $fileName at ${_currentLocation}");
    } catch (e) {
      debugPrint("❌ Photo capture error: $e");
    }
  }

  // ── Save ride ────────────────────────────────────────────────
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
        'photos': _ridePhotos.map((p) => p.toJson()).toList(),
      });

      await file.writeAsString(data);
      debugPrint("💾 Ride saved: $fileName");
    } catch (e) {
      debugPrint("❌ Save error: $e");
    }
  }

  // ────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    super.build(context);
    return Column(
      children: [
        _buildStatPanel(),
        Expanded(child: _buildMap()),
        _buildActionRow(),
      ],
    );
  }

  Widget _buildMap() {
    return FlutterMap(
      mapController: _mapController,
      options: MapOptions(
        initialCenter: _currentLocation ?? _defaultLocation,
        initialZoom: 15.0,
      ),
      children: [
        TileLayer(
          urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
          tileProvider: NetworkTileProvider(
            headers: {'User-Agent': 'SwiftRide/1.0'},
          ),
        ),
        if (_currentLocation != null)
          MarkerLayer(
            markers: [
              // Start marker
              if (_routePoints.isNotEmpty)
                Marker(
                  point: _routePoints.first,
                  width: 30,
                  height: 30,
                  child: _circleIcon(Colors.green, Icons.play_arrow),
                ),
              // End marker (only after ride ends)
              if (_routePoints.isNotEmpty && !isTracking)
                Marker(
                  point: _routePoints.last,
                  width: 30,
                  height: 30,
                  child: _circleIcon(Colors.red, Icons.stop),
                ),
              // Photo markers
              ..._ridePhotos.map((p) => Marker(
                    point: LatLng(p.latitude, p.longitude),
                    width: 32,
                    height: 32,
                    child: Container(
                      decoration: BoxDecoration(
                        color: Colors.deepPurpleAccent,
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 2),
                      ),
                      child: const Icon(Icons.photo_camera,
                          color: Colors.white, size: 16),
                    ),
                  )),
              // Current position dot
              Marker(
                point: _currentLocation!,
                width: 18,
                height: 18,
                child: Container(
                  decoration: BoxDecoration(
                    color: isPaused ? Colors.blueAccent : Colors.orangeAccent,
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 2),
                  ),
                ),
              ),
            ],
          ),
        PolylineLayer(
          polylines: [
            for (int i = 1;
                i <= min(_routeSegmentSpeeds.length, _routePoints.length - 1);
                i++) ...[
              // Outline stroke for high-speed segments
              if (_routeSegmentSpeeds[i - 1] > 75)
                Polyline(
                  points: [_routePoints[i - 1], _routePoints[i]],
                  color: Colors.black,
                  strokeWidth: 7.0,
                ),
              Polyline(
                points: [_routePoints[i - 1], _routePoints[i]],
                color: colorForSpeed(_routeSegmentSpeeds[i - 1]),
                strokeWidth: 5.0,
              ),
            ],
          ],
        ),
      ],
    );
  }

  Widget _circleIcon(Color bg, IconData icon) => Container(
        decoration: BoxDecoration(
          color: bg,
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white, width: 2),
        ),
        child: Icon(icon, color: Colors.white, size: 16),
      );

  // ── Stat panel ───────────────────────────────────────────────
  Widget _buildStatPanel() {
    return Container(
      padding: const EdgeInsets.only(top: 60, bottom: 20),
      color: const Color(0xFF121212),
      child: Column(
        children: [
          // Pause banner
          if (isPaused)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 6),
              color: Colors.blueAccent.withOpacity(0.2),
              child: const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.pause_circle_filled,
                      color: Colors.blueAccent, size: 16),
                  SizedBox(width: 6),
                  Text("RIDE PAUSED",
                      style: TextStyle(
                          color: Colors.blueAccent,
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 2)),
                ],
              ),
            ),
          Row(
            children: [
              _statHeader(
                  "DISTANCE",
                  (totalDistance / 1000).toStringAsFixed(2),
                  "KM"),
              _statHeader("TIME", _elapsedTime, "HRS"),
              _statHeader(
                  "TOP SPEED", topSpeed.toStringAsFixed(1), "KM/H"),
            ],
          ),
          // Speed color legend
          if (isTracking)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: _buildSpeedLegend(),
            ),
        ],
      ),
    );
  }

  Widget _buildSpeedLegend() {
    final segments = [
      (const Color(0xFFFFD700), "0–30"),
      (const Color(0xFF4CAF50), "31–55"),
      (const Color(0xFFFF8C00), "56–75"),
      (const Color(0xFFE60000), "75+"),
    ];
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: segments
          .map((s) => Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6),
                child: Row(
                  children: [
                    Container(
                        width: 12,
                        height: 4,
                        decoration: BoxDecoration(
                            color: s.$1,
                            borderRadius: BorderRadius.circular(2))),
                    const SizedBox(width: 4),
                    Text(s.$2,
                        style: const TextStyle(
                            color: Colors.white38, fontSize: 9)),
                  ],
                ),
              ))
          .toList(),
    );
  }

  // ── Dual-action button row ────────────────────────────────────
  Widget _buildActionRow() {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
      color: const Color(0xFF121212),
      child: !isTracking
          // ── Single START button when idle ────────────────────
          ? ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.orangeAccent,
                minimumSize: const Size(double.infinity, 65),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(15)),
              ),
              onPressed: startRide,
              icon: const Icon(Icons.play_arrow, color: Colors.black),
              label: const Text("START NEW RIDE",
                  style: TextStyle(
                      color: Colors.black,
                      fontSize: 18,
                      fontWeight: FontWeight.bold)),
            )
          // ── Dual action row during a ride ─────────────────────
          : Row(
              children: [
                // Left: Camera button
                _iconActionButton(
                  icon: Icons.photo_camera,
                  color: Colors.deepPurpleAccent,
                  onPressed: _capturePhoto,
                  tooltip: "Photo",
                  badge: _ridePhotos.isNotEmpty
                      ? "${_ridePhotos.length}"
                      : null,
                ),
                const SizedBox(width: 10),

                // Center: Pause / Resume
                Expanded(
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: isPaused
                          ? Colors.blueAccent
                          : const Color(0xFF2A2A2A),
                      minimumSize: const Size(0, 65),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(15)),
                      side: BorderSide(
                          color: isPaused
                              ? Colors.blueAccent
                              : Colors.white12),
                    ),
                    onPressed: isPaused ? _resumeRide : () => _pauseRide(),
                    icon: Icon(
                        isPaused ? Icons.play_arrow : Icons.pause,
                        color: Colors.white),
                    label: Text(
                        isPaused ? "RESUME" : "PAUSE",
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.bold)),
                  ),
                ),
                const SizedBox(width: 10),

                // Right: Finish
                Expanded(
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.redAccent,
                      minimumSize: const Size(0, 65),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(15)),
                    ),
                    onPressed: stopRide,
                    icon: const Icon(Icons.stop, color: Colors.white),
                    label: const Text("FINISH",
                        style: TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.bold)),
                  ),
                ),
              ],
            ),
    );
  }

  Widget _iconActionButton({
    required IconData icon,
    required Color color,
    required VoidCallback onPressed,
    required String tooltip,
    String? badge,
  }) {
    return SizedBox(
      width: 65,
      height: 65,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: color.withOpacity(0.2),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(15),
                  side: BorderSide(color: color.withOpacity(0.6))),
              padding: EdgeInsets.zero,
            ),
            onPressed: onPressed,
            child: Icon(icon, color: color, size: 26),
          ),
          if (badge != null)
            Positioned(
              right: -4,
              top: -4,
              child: Container(
                padding: const EdgeInsets.all(4),
                decoration: const BoxDecoration(
                    color: Colors.orangeAccent, shape: BoxShape.circle),
                child: Text(badge,
                    style: const TextStyle(
                        fontSize: 9,
                        color: Colors.black,
                        fontWeight: FontWeight.bold)),
              ),
            ),
        ],
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
    _uiTimer?.cancel();
    _positionStream?.cancel();
    // Clear notification callbacks so they don't fire after widget is gone
    final notif = RideNotificationService.instance;
    notif.onPauseTapped  = null;
    notif.onResumeTapped = null;
    notif.onStopTapped   = null;
    super.dispose();
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  HISTORY PAGE
// ─────────────────────────────────────────────────────────────────────────────
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
        setState(() => rides = jsonDecode(content));
      } catch (e) {
        debugPrint("❌ Error loading archive $specificFile: $e");
      }
    } else if (archiveView) {
      final files = dir
          .listSync()
          .where((f) =>
              f.path.endsWith('.json') &&
              !f.path.split(Platform.pathSeparator).last.contains('ride_'))
          .toList();
      final List<dynamic> temp = [];
      for (var f in files) {
        final name = f.path.split(Platform.pathSeparator).last;
        try {
          final List<dynamic> content =
              jsonDecode(await File(f.path).readAsString());
          final DateTime date = content
              .map((r) => DateTime.parse(r['date']))
              .reduce((a, b) => a.isAfter(b) ? a : b);
          temp.add({
            'fileName': name,
            'date': date,
            'ridesCount': content.length,
          });
        } catch (e) {
          debugPrint("⚠️ Skipping invalid archive file: $name, error: $e");
        }
      }
      setState(() {
        rides = temp;
        rides.sort((a, b) => b['date'].compareTo(a['date']));
      });
    } else {
      final files = dir
          .listSync()
          .where((f) =>
              f.path.endsWith('.json') &&
              !f.path
                  .split(Platform.pathSeparator)
                  .last
                  .contains('archive_'))
          .toList();
      final List<dynamic> temp = [];
      for (var f in files) {
        try {
          final Map<String, dynamic> data =
              jsonDecode(await File(f.path).readAsString());
          data['filePath'] = f.path;
          temp.add(data);
        } catch (e) {
          debugPrint("⚠️ Skipping invalid ride file: ${f.path.split(Platform.pathSeparator).last}, error: $e");
        }
      }
      setState(() {
        rides = temp;
        rides.sort((a, b) => b['date'].compareTo(a['date']));
      });
    }
  }

  // ── Share helpers ─────────────────────────────────────────────
  Future<void> _shareRideFile(Map<String, dynamic> ride) async {
    try {
      final filePath = ride['filePath'] as String?;
      if (filePath == null) return;
      await Share.shareXFiles(
        [XFile(filePath)],
        subject: 'SwiftRide Export — ${ride['date']}',
        text: 'My ride on ${DateFormat('MMM dd, yyyy').format(DateTime.parse(ride['date']))}',
      );
    } catch (e) {
      debugPrint("❌ Share error: $e");
    }
  }

  Future<void> _shareGpxRoute(Map<String, dynamic> ride) async {
    try {
      final routeRaw = ride['route'] as List?;
      if (routeRaw == null || routeRaw.isEmpty) return;

      final List<LatLng> points = routeRaw.map<LatLng>((p) {
        if (p is List) return LatLng((p[0] as num).toDouble(), (p[1] as num).toDouble());
        return LatLng(
            (p['latitude'] as num).toDouble(), (p['longitude'] as num).toDouble());
      }).toList();

      final gpx = _buildGpx(points, ride['date'] as String);
      final dir = await getApplicationDocumentsDirectory();
      final gpxFile = File('${dir.path}/route_export.gpx');
      await gpxFile.writeAsString(gpx);

      await Share.shareXFiles(
        [XFile(gpxFile.path, mimeType: 'application/gpx+xml')],
        subject: 'SwiftRide GPX Route',
      );
    } catch (e) {
      debugPrint("❌ GPX share error: $e");
    }
  }

  String _buildGpx(List<LatLng> points, String dateStr) {
    final buf = StringBuffer();
    buf.writeln('<?xml version="1.0" encoding="UTF-8"?>');
    buf.writeln(
        '<gpx version="1.1" creator="SwiftRide" xmlns="http://www.topografix.com/GPX/1/1">');
    buf.writeln('  <trk>');
    buf.writeln('    <name>SwiftRide $dateStr</name>');
    buf.writeln('    <trkseg>');
    for (final p in points) {
      buf.writeln(
          '      <trkpt lat="${p.latitude}" lon="${p.longitude}"></trkpt>');
    }
    buf.writeln('    </trkseg>');
    buf.writeln('  </trk>');
    buf.writeln('</gpx>');
    return buf.toString();
  }

  // ─────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: Text(
          isSelectionMode
              ? "SELECT RIDES TO ARCHIVE"
              : (isArchiveView
                  ? "ARCHIVES"
                  : (isViewingArchived ? "ARCHIVED RIDES" : "RIDE LOGS")),
          style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.bold,
              color: Colors.white),
        ),
        backgroundColor: Colors.black,
        actions: [
          if (isSelectionMode) ...[
            IconButton(
                icon: const Icon(Icons.close),
                onPressed: () => setState(
                    () { isSelectionMode = false; selectedRides.clear(); })),
          ] else if (isArchiveView) ...[
            IconButton(
                icon: const Icon(Icons.close), onPressed: () => reload()),
          ] else if (isViewingArchived) ...[
            IconButton(
                icon: const Icon(Icons.close),
                onPressed: () => reload(archiveView: true)),
          ] else ...[
            IconButton(
                icon: const Icon(Icons.inventory_2,
                    color: Colors.orangeAccent),
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
      floatingActionButton: isSelectionMode
          ? FloatingActionButton(
              onPressed: _confirmArchive,
              backgroundColor: Colors.orangeAccent,
              child: const Icon(Icons.archive),
            )
          : null,
    );
  }

  Widget _buildRideCard(dynamic ride, int index) {
    // ── Archive card ───────────────────────────────────────────
    if (ride.containsKey('fileName')) {
      final nameWithoutExt = ride['fileName'].replaceAll('.json', '') as String;
      final parts = nameWithoutExt.split('_');
      final displayName = parts.length > 1 ? parts[1] : 'Archive';

      return GestureDetector(
        onTap: () => reload(specificFile: ride['fileName'] as String),
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
                            .format(ride['date'] as DateTime),
                        style:
                            const TextStyle(color: Colors.grey, fontSize: 12)),
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
                      final newName = await _showRenameDialog(
                          context, ride['fileName'] as String);
                      if (newName != null && newName.isNotEmpty) {
                        final dir = await getApplicationDocumentsDirectory();
                        final oldPath =
                            '${dir.path}/${ride['fileName']}';
                        final nameParts = nameWithoutExt.split('_');
                        final datePart = nameParts.length > 2
                            ? nameParts[2]
                            : DateTime.now()
                                .millisecondsSinceEpoch
                                .toString();
                        final newFileName =
                            "archive_${newName}_$datePart.json";
                        try {
                          await File(oldPath).rename(
                              '${dir.path}/$newFileName');
                          reload(archiveView: true);
                        } catch (e) {
                          debugPrint("❌ Error renaming archive: $e");
                        }
                      }
                    },
                  ),
                  IconButton(
                    icon: const Icon(Icons.delete_outline,
                        color: Colors.white54),
                    onPressed: () async {
                      final dir = await getApplicationDocumentsDirectory();
                      await File('${dir.path}/${ride['fileName']}').delete();
                      reload(archiveView: true);
                    },
                  ),
                ],
              ),
            ],
          ),
        ),
      );
    }

    // ── Ride card ──────────────────────────────────────────────
    final photos = (ride['photos'] as List?)
            ?.map((p) => RidePhoto.fromJson(Map<String, dynamic>.from(p)))
            .toList() ??
        [];

    return GestureDetector(
      onTap: isSelectionMode
          ? null
          : () => Navigator.push(
              context,
              MaterialPageRoute(
                  builder: (_) => RideDetailsPage(rideData: ride))),
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
                          .format(DateTime.parse(ride['date'] as String)),
                      style:
                          const TextStyle(color: Colors.grey, fontSize: 12)),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Text(
                          "${(ride['distance'] / 1000).toStringAsFixed(2)} KM",
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 20,
                              fontWeight: FontWeight.bold)),
                      const SizedBox(width: 10),
                      Text(ride['duration'] as String,
                          style: const TextStyle(
                              color: Colors.orangeAccent,
                              fontSize: 14,
                              fontWeight: FontWeight.w500)),
                    ],
                  ),
                  if (photos.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        const Icon(Icons.photo_camera,
                            color: Colors.deepPurpleAccent, size: 14),
                        const SizedBox(width: 4),
                        Text("${photos.length} photo${photos.length > 1 ? 's' : ''}",
                            style: const TextStyle(
                                color: Colors.deepPurpleAccent, fontSize: 12)),
                      ],
                    ),
                  ],
                ],
              ),
            ),
            if (isSelectionMode) ...[
              Checkbox(
                value: selectedRides.contains(index),
                onChanged: (value) => setState(() {
                  if (value == true) {
                    selectedRides.add(index);
                  } else {
                    selectedRides.remove(index);
                  }
                }),
                activeColor: Colors.orangeAccent,
              ),
            ] else if (!isViewingArchived) ...[
              // Share menu
              PopupMenuButton<String>(
                icon: const Icon(Icons.more_vert, color: Colors.white54),
                color: const Color(0xFF2A2A2A),
                onSelected: (value) {
                  if (value == 'share_file') _shareRideFile(Map<String, dynamic>.from(ride));
                  if (value == 'share_gpx') _shareGpxRoute(Map<String, dynamic>.from(ride));
                  if (value == 'delete') {
                    File(ride['filePath'] as String).delete();
                    reload();
                  }
                },
                itemBuilder: (_) => [
                  const PopupMenuItem(
                    value: 'share_file',
                    child: Row(children: [
                      Icon(Icons.file_upload_outlined, color: Colors.orangeAccent, size: 18),
                      SizedBox(width: 10),
                      Text("Export Ride File", style: TextStyle(color: Colors.white)),
                    ]),
                  ),
                  const PopupMenuItem(
                    value: 'share_gpx',
                    child: Row(children: [
                      Icon(Icons.map_outlined, color: Colors.orangeAccent, size: 18),
                      SizedBox(width: 10),
                      Text("Export GPX Route", style: TextStyle(color: Colors.white)),
                    ]),
                  ),
                  const PopupMenuItem(
                    value: 'delete',
                    child: Row(children: [
                      Icon(Icons.delete_outline, color: Colors.redAccent, size: 18),
                      SizedBox(width: 10),
                      Text("Delete", style: TextStyle(color: Colors.redAccent)),
                    ]),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  void _startArchiveSelection() => setState(() {
        isSelectionMode = true;
        selectedRides.clear();
      });

  void _confirmArchive() {
    if (selectedRides.isEmpty) return;
    _showArchiveNameDialog();
  }

  Future<void> _showArchiveNameDialog() async {
    String archiveName = '';
    return showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Name Your Archive'),
        content: TextField(
          onChanged: (v) => archiveName = v,
          decoration: const InputDecoration(hintText: 'Enter archive name'),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Cancel')),
          TextButton(
            onPressed: () {
              if (archiveName.isNotEmpty) {
                Navigator.of(ctx).pop();
                _performArchive(selectedRides, archiveName);
              }
            },
            child: const Text('Archive'),
          ),
        ],
      ),
    );
  }

  Future<void> _performArchive(Set<int> selectedIndices, String name) async {
    final dir = await getApplicationDocumentsDirectory();
    final List<dynamic> toArchive =
        selectedIndices.map((i) => rides[i]).toList();
    if (toArchive.isEmpty) return;

    for (var ride in toArchive) {
      if (ride.containsKey('filePath')) {
        await File(ride['filePath'] as String).delete();
      }
    }

    final timestamp = DateTime.now().millisecondsSinceEpoch.toString();
    final fileName = "archive_${name}_$timestamp.json";
    final file = File('${dir.path}/$fileName');
    try {
      await file.writeAsString(jsonEncode(toArchive));
    } catch (e) {
      debugPrint("❌ Save archive error: $e");
    }

    setState(() { isSelectionMode = false; selectedRides.clear(); });
    await Future.delayed(const Duration(milliseconds: 100));
    reload(archiveView: true);
  }

  Future<String?> _showRenameDialog(
      BuildContext context, String currentName) async {
    final nameWithoutExt = currentName.replaceAll('.json', '');
    final parts = nameWithoutExt.split('_');
    String name = parts.length > 1 ? parts[1] : 'Archive';
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Rename Archive'),
        content: TextField(
          controller: TextEditingController(text: name),
          onChanged: (v) => name = v,
          decoration:
              const InputDecoration(hintText: 'Enter new archive name'),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Cancel')),
          TextButton(
              onPressed: () => Navigator.of(ctx).pop(name),
              child: const Text('Rename')),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  RIDE DETAILS PAGE
// ─────────────────────────────────────────────────────────────────────────────
class RideDetailsPage extends StatefulWidget {
  final Map<String, dynamic> rideData;
  const RideDetailsPage({super.key, required this.rideData});

  @override
  State<RideDetailsPage> createState() => _RideDetailsPageState();
}

class _RideDetailsPageState extends State<RideDetailsPage> {
  late List<LatLng> route;
  late List<double> segmentSpeeds;
  late List<RidePhoto> photos;
  final MapController _mapController = MapController();

  RidePhoto? _selectedPhoto;

  @override
  void initState() {
    super.initState();

    route = [];
    if (widget.rideData['route'] != null) {
      for (final p in widget.rideData['route'] as List) {
        if (p is List && p.length >= 2) {
          route.add(LatLng((p[0] as num).toDouble(), (p[1] as num).toDouble()));
        } else if (p is Map) {
          final lat = p['latitude'] ?? p['lat'];
          final lon = p['longitude'] ?? p['lng'] ?? p['lon'];
          if (lat != null && lon != null) {
            route.add(LatLng((lat as num).toDouble(), (lon as num).toDouble()));
          }
        }
      }
    }

    segmentSpeeds = [];
    if (widget.rideData['segmentSpeeds'] != null) {
      segmentSpeeds = List<double>.from(
          (widget.rideData['segmentSpeeds'] as List)
              .map((e) => (e as num).toDouble()));
    }

    photos = [];
    if (widget.rideData['photos'] != null) {
      for (final p in widget.rideData['photos'] as List) {
        try {
          photos.add(RidePhoto.fromJson(Map<String, dynamic>.from(p)));
        } catch (_) {}
      }
    }

    if (route.isNotEmpty) {
      WidgetsBinding.instance
          .addPostFrameCallback((_) => _fitBounds());
    }
  }

  void _fitBounds() {
    if (route.isEmpty) return;
    final minLat = route.map((p) => p.latitude).reduce(min);
    final maxLat = route.map((p) => p.latitude).reduce(max);
    final minLng = route.map((p) => p.longitude).reduce(min);
    final maxLng = route.map((p) => p.longitude).reduce(max);
    _mapController.fitCamera(
      CameraFit.bounds(
        bounds: LatLngBounds(
            LatLng(minLat, minLng), LatLng(maxLat, maxLng)),
        padding: const EdgeInsets.all(50),
      ),
    );
  }

  // ── Share from details page ──────────────────────────────────
  Future<void> _shareFromDetails() async {
    final filePath = widget.rideData['filePath'] as String?;
    if (filePath == null) return;
    await Share.shareXFiles(
      [XFile(filePath)],
      subject: 'SwiftRide Export',
      text:
          'My ride on ${DateFormat('MMM dd, yyyy').format(DateTime.parse(widget.rideData['date'] as String))}',
    );
  }

  Future<void> _shareGpxFromDetails() async {
    if (route.isEmpty) return;
    final dateStr = widget.rideData['date'] as String;
    final buf = StringBuffer();
    buf.writeln('<?xml version="1.0" encoding="UTF-8"?>');
    buf.writeln(
        '<gpx version="1.1" creator="SwiftRide" xmlns="http://www.topografix.com/GPX/1/1">');
    buf.writeln('  <trk>');
    buf.writeln('    <name>SwiftRide $dateStr</name>');
    buf.writeln('    <trkseg>');
    for (final p in route) {
      buf.writeln(
          '      <trkpt lat="${p.latitude}" lon="${p.longitude}"></trkpt>');
    }
    buf.writeln('    </trkseg>');
    buf.writeln('  </trk>');
    buf.writeln('</gpx>');

    final dir = await getApplicationDocumentsDirectory();
    final gpxFile = File('${dir.path}/route_export.gpx');
    await gpxFile.writeAsString(buf.toString());
    await Share.shareXFiles(
      [XFile(gpxFile.path, mimeType: 'application/gpx+xml')],
      subject: 'SwiftRide GPX Route',
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("RIDE DETAILS"),
        backgroundColor: Colors.black,
        actions: [
          PopupMenuButton<String>(
            icon: const Icon(Icons.share, color: Colors.orangeAccent),
            color: const Color(0xFF2A2A2A),
            onSelected: (v) {
              if (v == 'file') _shareFromDetails();
              if (v == 'gpx') _shareGpxFromDetails();
            },
            itemBuilder: (_) => [
              const PopupMenuItem(
                value: 'file',
                child: Row(children: [
                  Icon(Icons.file_upload_outlined,
                      color: Colors.orangeAccent, size: 18),
                  SizedBox(width: 10),
                  Text("Export Ride File",
                      style: TextStyle(color: Colors.white)),
                ]),
              ),
              const PopupMenuItem(
                value: 'gpx',
                child: Row(children: [
                  Icon(Icons.map_outlined,
                      color: Colors.orangeAccent, size: 18),
                  SizedBox(width: 10),
                  Text("Export GPX Route",
                      style: TextStyle(color: Colors.white)),
                ]),
              ),
            ],
          ),
        ],
      ),
      backgroundColor: Colors.black,
      body: Column(
        children: [
          _buildDetailHeader(),
          Expanded(child: _buildMap()),
          // Photo strip
          if (photos.isNotEmpty) _buildPhotoStrip(),
          // Photo full-view overlay
          if (_selectedPhoto != null) _buildPhotoOverlay(_selectedPhoto!),
        ],
      ),
    );
  }

  Widget _buildMap() {
    if (route.isEmpty) {
      return const Center(
          child: Text("No path recorded",
              style: TextStyle(color: Colors.white24)));
    }
    return FlutterMap(
      mapController: _mapController,
      options: MapOptions(
        initialCenter: route.first,
        initialZoom: 15.0,
      ),
      children: [
        TileLayer(
          urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
          tileProvider: NetworkTileProvider(
              headers: {'User-Agent': 'SwiftRide/1.0'}),
        ),
        MarkerLayer(
          markers: [
            // Start
            Marker(
              point: route.first,
              width: 30,
              height: 30,
              child: _circleIcon(Colors.green, Icons.play_arrow),
            ),
            // End
            Marker(
              point: route.last,
              width: 30,
              height: 30,
              child: _circleIcon(Colors.red, Icons.stop),
            ),
            // Photo pins
            ...photos.map((p) => Marker(
                  point: LatLng(p.latitude, p.longitude),
                  width: 32,
                  height: 32,
                  child: GestureDetector(
                    onTap: () => setState(() => _selectedPhoto = p),
                    child: Container(
                      decoration: BoxDecoration(
                        color: Colors.deepPurpleAccent,
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 2),
                      ),
                      child: const Icon(Icons.photo_camera,
                          color: Colors.white, size: 16),
                    ),
                  ),
                )),
          ],
        ),
        PolylineLayer(
          polylines: [
            if (segmentSpeeds.isNotEmpty && route.length > 1)
              for (int i = 1;
                  i <= min(segmentSpeeds.length, route.length - 1);
                  i++) ...[
                if (segmentSpeeds[i - 1] > 75)
                  Polyline(
                      points: [route[i - 1], route[i]],
                      color: Colors.black,
                      strokeWidth: 7.0),
                Polyline(
                    points: [route[i - 1], route[i]],
                    color: colorForSpeed(segmentSpeeds[i - 1]),
                    strokeWidth: 5.0),
              ]
            else
              Polyline(
                  points: route,
                  color: Colors.orangeAccent,
                  strokeWidth: 5.0),
          ],
        ),
      ],
    );
  }

  Widget _circleIcon(Color bg, IconData icon) => Container(
        decoration: BoxDecoration(
          color: bg,
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white, width: 2),
        ),
        child: Icon(icon, color: Colors.white, size: 16),
      );

  Widget _buildPhotoStrip() {
    return Container(
      height: 80,
      color: const Color(0xFF121212),
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.all(8),
        itemCount: photos.length,
        itemBuilder: (_, i) {
          final photo = photos[i];
          return GestureDetector(
            onTap: () => setState(() => _selectedPhoto = photo),
            child: Container(
              margin: const EdgeInsets.only(right: 8),
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.deepPurpleAccent, width: 2),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: Image.file(
                  File(photo.filePath),
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => const Icon(
                      Icons.broken_image,
                      color: Colors.white24),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildPhotoOverlay(RidePhoto photo) {
    return GestureDetector(
      onTap: () => setState(() => _selectedPhoto = null),
      child: Container(
        color: Colors.black87,
        child: Stack(
          children: [
            Center(
              child: Image.file(
                File(photo.filePath),
                fit: BoxFit.contain,
                errorBuilder: (_, __, ___) =>
                    const Icon(Icons.broken_image, color: Colors.white, size: 64),
              ),
            ),
            Positioned(
              top: 8,
              right: 8,
              child: IconButton(
                icon: const Icon(Icons.close, color: Colors.white),
                onPressed: () => setState(() => _selectedPhoto = null),
              ),
            ),
            Positioned(
              bottom: 16,
              left: 0,
              right: 0,
              child: Text(
                DateFormat('MMM dd, yyyy • hh:mm a').format(photo.timestamp),
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white70, fontSize: 12),
              ),
            ),
          ],
        ),
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
          _detailTile("TIME", widget.rideData['duration'] as String, ""),
          _detailTile("TOP SPEED",
              (widget.rideData['topSpeed'] as num).toStringAsFixed(1), "KM/H"),
        ],
      ),
    );
  }

  Widget _detailTile(String label, String val, String unit) =>
      Column(children: [
        Text(label,
            style: const TextStyle(color: Colors.grey, fontSize: 10)),
        Text(val,
            style: const TextStyle(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.bold)),
        if (unit.isNotEmpty)
          Text(unit,
              style: const TextStyle(
                  color: Colors.orangeAccent, fontSize: 10)),
      ]);
}
