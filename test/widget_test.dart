import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:task_management_app/main.dart';

void main() {
  testWidgets('logs in as admin, adds a task, and logs out', (tester) async {
    setTestMode(true);
    await tester.pumpWidget(const MyApp());
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField).at(0), 'admin');
    await tester.enterText(find.byType(TextField).at(1), '1234');
    await tester.tap(find.text('Login'));
    await tester.pumpAndSettle();

    expect(find.text('Flat Manager'), findsOneWidget);

    await tester.tap(find.text('Add task'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField).first, 'Test task');
    await tester.tap(find.text('Save task'));
    await tester.pumpAndSettle();

    expect(find.text('Test task'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.logout));
    await tester.pumpAndSettle();

    expect(find.text('Flatmates Login'), findsOneWidget);
  });

  testWidgets('admin can create a roommate account and the roommate can log in', (tester) async {
    setTestMode(true);
    await tester.pumpWidget(const MyApp());
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField).at(0), 'admin');
    await tester.enterText(find.byType(TextField).at(1), '1234');
    await tester.tap(find.text('Login'));
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.menu));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Roommates'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Add user'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField).at(0), 'testuser');
    await tester.enterText(find.byType(TextField).at(1), 'testpass');
    await tester.tap(find.text('Create user'));
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.logout));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField).at(0), 'testuser');
    await tester.enterText(find.byType(TextField).at(1), 'testpass');
    await tester.tap(find.text('Login'));
    await tester.pumpAndSettle();

    expect(find.text('Your assigned tasks'), findsOneWidget);
  });

  testWidgets('admin can open user management and see created users', (tester) async {
    setTestMode(true);
    await tester.pumpWidget(const MyApp());
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField).at(0), 'admin');
    await tester.enterText(find.byType(TextField).at(1), '1234');
    await tester.tap(find.text('Login'));
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.menu));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Roommates'));
    await tester.pumpAndSettle();

    expect(find.text('Created users'), findsOneWidget);
    expect(find.textContaining('Assigned tasks'), findsWidgets);
  });

  testWidgets('roommate can update assigned task status and admin sees it', (tester) async {
    setTestMode(true);
    await tester.pumpWidget(const MyApp());
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField).at(0), 'rahul');
    await tester.enterText(find.byType(TextField).at(1), 'rahul123');
    await tester.tap(find.text('Login'));
    await tester.pumpAndSettle();

    expect(find.text('Your assigned tasks'), findsOneWidget);

    final listFinder = find.byType(ListView).first;
    await tester.drag(listFinder, const Offset(0, -400));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Pick up').first);
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.logout));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField).at(0), 'admin');
    await tester.enterText(find.byType(TextField).at(1), '1234');
    await tester.tap(find.text('Login'));
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.menu));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Roommates'));
    await tester.pumpAndSettle();

    expect(find.text('Started'), findsWidgets);
  });
}
