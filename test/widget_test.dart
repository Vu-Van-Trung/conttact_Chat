import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pulse/widgets/gradient_background.dart';

void main() {
  testWidgets('GradientBackground renders child content', (WidgetTester tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: GradientBackground(
            child: Text('child-content'),
          ),
        ),
      ),
    );

    expect(find.text('child-content'), findsOneWidget);
  });
}
