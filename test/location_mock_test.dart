import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:geolocator_platform_interface/geolocator_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:ride_tracker_1/main.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

class MockGeolocator extends GeolocatorPlatform with MockPlatformInterfaceMixin {
  final StreamController<Position> _positionStreamController = StreamController<Position>.broadcast();

  @override
  Future<LocationPermission> checkPermission() async => LocationPermission.always;

  @override
  Future<LocationPermission> requestPermission() async => LocationPermission.always;

  @override
  Stream<Position> getPositionStream({LocationSettings? locationSettings}) {
    return _positionStreamController.stream;
  }

  void yieldPosition(Position position) {
    _positionStreamController.add(position);
  }
}

class MockPathProvider extends PathProviderPlatform with MockPlatformInterfaceMixin {
  @override
  Future<String?> getApplicationDocumentsPath() async {
    return '.';
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  
  setUpAll(() {
    HttpOverrides.global = null;
  });

  testWidgets('Ride Tracking logs and path creation test', (WidgetTester tester) async {
    final mockGeo = MockGeolocator();
    GeolocatorPlatform.instance = mockGeo;
    PathProviderPlatform.instance = MockPathProvider();

    final gpsKey = GlobalKey<State>();

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: GPSDashboard(key: gpsKey),
      )
    ));

    // Wait for initial render
    await tester.pumpAndSettle();

    // Verify initial "START NEW RIDE" button
    expect(find.text("START NEW RIDE"), findsOneWidget);

    // Tap to start ride
    await tester.tap(find.text("START NEW RIDE"));
    await tester.pump();

    // Verify button turned to "FINISH SESSION"
    expect(find.text("FINISH SESSION"), findsOneWidget);

    // Mock first position
    mockGeo.yieldPosition(Position(
      longitude: 73.8567,
      latitude: 18.5204,
      timestamp: DateTime.now(),
      accuracy: 1.0,
      altitude: 0.0,
      altitudeAccuracy: 0.0,
      heading: 0.0,
      headingAccuracy: 0.0,
      speed: 10.0, // This evaluates to 36.0 km/h (10 * 3.6)
      speedAccuracy: 0.0,
    ));
    await tester.pump(const Duration(seconds: 1));

    // Mock second position to accumulate distance and change top speed
    mockGeo.yieldPosition(Position(
      longitude: 73.8570,
      latitude: 18.5210,
      timestamp: DateTime.now(),
      accuracy: 1.0,
      altitude: 0.0,
      altitudeAccuracy: 0.0,
      heading: 0.0,
      headingAccuracy: 0.0,
      speed: 15.0, // This evaluates to 54.0 km/h (15 * 3.6)
      speedAccuracy: 0.0,
    ));
    await tester.pump(const Duration(seconds: 1));

    // Wait for the UI updates like microtasks
    await tester.pumpAndSettle();

    // Verify internal state using UI mapping
    expect(find.text('54.0'), findsOneWidget);

    // Stop ride to trigger file save
    await tester.tap(find.text("FINISH SESSION"));
    for (int i = 0; i < 50; i++) {
      await tester.pump(const Duration(milliseconds: 50));
      if (find.text("START NEW RIDE").evaluate().isNotEmpty) {
        break;
      }
    }

    // Verify it backed to START NEW RIDE
    expect(find.text("START NEW RIDE"), findsOneWidget);

    // Check if file is created
    var dir = Directory('.');
    var files = dir.listSync().where((f) => f.path.contains('ride_') && f.path.endsWith('.json')).toList();
    expect(files.isNotEmpty, isTrue);
    
    var lastFile = File(files.last.path);
    var content = jsonDecode(await lastFile.readAsString());
    
    // Top speed should be 15.0 * 3.6 = 54.0
    expect(content['topSpeed'], 54.0);
    // Distance should be greater than 0
    expect(content['distance'], greaterThan(0));
    
    // Clean up
    for(var f in files) {
      if (f is File) {
         await f.delete();
      }
    }
  });
}
