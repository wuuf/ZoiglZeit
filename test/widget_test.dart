import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:zoigl_zeit/main.dart';

void main() {
  group('ZoiglEvent', () {
    final event = ZoiglEvent.fromCsvLine(
      '2026-01-02;2026-01-06;02.01.-06.01.;Fr - Di;Käck\'n;Neuhaus;Kirwa',
    );

    test('parst eine CSV-Zeile', () {
      expect(event.datumVon, DateTime(2026, 1, 2));
      expect(event.datumBis, DateTime(2026, 1, 6));
      expect(event.zoiglstube, "Käck'n");
      expect(event.ort, 'Neuhaus');
      expect(event.bemerkung, 'Kirwa');
    });

    test('leere Bemerkung ist erlaubt', () {
      final e = ZoiglEvent.fromCsvLine(
        '2026-01-05;2026-01-05;05.01.;Mo;Zum Waldhauser;Neustadt/WN;',
      );
      expect(e.bemerkung, isEmpty);
    });

    test('isOpenOn schließt Start- und Endtag ein', () {
      expect(event.isOpenOn(DateTime(2026, 1, 1)), isFalse);
      expect(event.isOpenOn(DateTime(2026, 1, 2, 23, 59)), isTrue);
      expect(event.isOpenOn(DateTime(2026, 1, 4)), isTrue);
      expect(event.isOpenOn(DateTime(2026, 1, 6, 8)), isTrue);
      expect(event.isOpenOn(DateTime(2026, 1, 7)), isFalse);
    });

    test('endsBefore erkennt vergangene Termine', () {
      expect(event.endsBefore(DateTime(2026, 1, 6, 22)), isFalse);
      expect(event.endsBefore(DateTime(2026, 1, 7)), isTrue);
    });
  });

  test('jeder Ort in der CSV hat Koordinaten für die Karte', () {
    final lines = File('assets/zoiglkalender_2026.csv')
        .readAsLinesSync()
        .skip(1)
        .where((l) => l.trim().isNotEmpty);
    final orte = lines.map((l) => ZoiglEvent.fromCsvLine(l).ort).toSet();
    final ohneKoordinaten =
        orte.where((o) => !kOrtCoordinates.containsKey(o)).toList();
    expect(ohneKoordinaten, isEmpty);
  });

  testWidgets('App startet und zeigt die Terminliste', (tester) async {
    SharedPreferences.setMockInitialValues({});

    await tester.pumpWidget(const ZoiglApp());
    // Asset-Laden und SharedPreferences laufen außerhalb der Fake-Zeit.
    await tester.runAsync(() => Future<void>.delayed(
          const Duration(milliseconds: 500),
        ));
    await tester.pumpAndSettle();

    expect(find.text('ZoiglZeit 2026'), findsOneWidget);
    expect(find.textContaining('Terminen'), findsOneWidget);
    expect(find.text('Vergangene'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });
}
