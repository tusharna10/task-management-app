import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:task_management_app/main.dart';

void main() {
  testWidgets('logs in, adds a task, and logs out', (tester) async {
    await tester.pumpWidget(const MyApp());

    await tester.enterText(find.byType(TextField).at(0), 'admin');
    await tester.enterText(find.byType(TextField).at(1), '1234');
    await tester.tap(find.text('Login'));
    await tester.pumpAndSettle();

    expect(find.text('Bachelor Flat Task Manager'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.add));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField).first, 'Buy groceries');
    await tester.tap(find.text('Save task'));
    await tester.pumpAndSettle();

    expect(find.text('Add task'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.logout));
    await tester.pumpAndSettle();

    expect(find.text('Login to your flat dashboard'), findsOneWidget);
  });

  testWidgets('admin can create a roommate account and the roommate can see assigned tasks', (tester) async {
    await tester.pumpWidget(const MyApp());

    await tester.enterText(find.byType(TextField).at(0), 'admin');
    await tester.enterText(find.byType(TextField).at(1), '1234');
    await tester.tap(find.text('Login'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Add user'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField).at(0), 'asha');
    await tester.enterText(find.byType(TextField).at(1), 'room123');
    await tester.tap(find.text('Create user'));
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.logout));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField).at(0), 'asha');
    await tester.enterText(find.byType(TextField).at(1), 'room123');
    await tester.tap(find.text('Login'));
    await tester.pumpAndSettle();

    expect(find.text('Your assigned tasks'), findsOneWidget);
    expect(find.text('Buy groceries'), findsOneWidget);
  });

  testWidgets('admin can open a user details view with assigned tasks', (tester) async {
    await tester.pumpWidget(const MyApp());

    await tester.enterText(find.byType(TextField).at(0), 'admin');
    await tester.enterText(find.byType(TextField).at(1), '1234');
    await tester.tap(find.text('Login'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('View users'));
    await tester.pumpAndSettle();

    expect(find.text('Asha'), findsOneWidget);
    expect(find.text('Assigned tasks'), findsWidgets);
  });

  testWidgets('roommate can update assigned task status and admin sees it', (tester) async {
    await tester.pumpWidget(const MyApp());

    await tester.enterText(find.byType(TextField).at(0), 'asha');
    await tester.enterText(find.byType(TextField).at(1), 'room123');
    await tester.tap(find.text('Login'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Pick up'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Started'));
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.logout));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField).at(0), 'admin');
    await tester.enterText(find.byType(TextField).at(1), '1234');
    await tester.tap(find.text('Login'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('View users'));
    await tester.pumpAndSettle();

    expect(find.text('Started'), findsWidgets);
  });
}
