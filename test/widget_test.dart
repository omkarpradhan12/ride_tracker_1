import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ride_tracker_1/main.dart';

void main() {
  testWidgets('App starts smoke test', (WidgetTester tester) async {
    await tester.pumpWidget(const MaterialApp(home: MainNavigation()));
    expect(find.byType(MainNavigation), findsOneWidget);
  });
}
