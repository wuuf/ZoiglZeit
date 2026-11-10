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
    final ohneKoordinaten = orte
        .where((o) => !kOrtCoordinates.containsKey(o))
        .toList();
    expect(ohneKoordinaten, isEmpty);
  });

  group('CSV-Daten', () {
    final events = File('assets/zoiglkalender_2026.csv')
        .readAsLinesSync()
        .skip(1)
        .where((l) => l.trim().isNotEmpty)
        .map(ZoiglEvent.fromCsvLine)
        .toList();
    const wochentag = ['Mo', 'Di', 'Mi', 'Do', 'Fr', 'Sa', 'So'];
    String fmt(DateTime d) =>
        '${d.day.toString().padLeft(2, '0')}.${d.month.toString().padLeft(2, '0')}.';
    String label(ZoiglEvent e) => '${e.zoiglstube} (${e.ort}) ${e.zeitraum}';

    test('Zeitraum und Wochentage passen zum Datum', () {
      final fehler = <String>[];
      for (final e in events) {
        final same = e.datumVon == e.datumBis;
        final zeitraum = same
            ? fmt(e.datumVon)
            : '${fmt(e.datumVon)}-${fmt(e.datumBis)}';
        final tage = same
            ? wochentag[e.datumVon.weekday - 1]
            : '${wochentag[e.datumVon.weekday - 1]} - '
                  '${wochentag[e.datumBis.weekday - 1]}';
        if (e.datumBis.isBefore(e.datumVon)) {
          fehler.add('Ende vor Start: ${label(e)}');
        }
        if (e.zeitraum != zeitraum) {
          fehler.add('Zeitraum: ${label(e)}');
        }
        if (e.wochentage != tage) {
          fehler.add('Wochentage "${e.wochentage}": ${label(e)}');
        }
      }
      expect(fehler, isEmpty);
    });

    test('keine überlappenden Termine derselben Zoiglstube', () {
      final byStube = <String, List<ZoiglEvent>>{};
      for (final e in events) {
        byStube.putIfAbsent('${e.zoiglstube}|${e.ort}', () => []).add(e);
      }
      final fehler = <String>[];
      for (final list in byStube.values) {
        list.sort((a, b) => a.datumVon.compareTo(b.datumVon));
        for (var i = 1; i < list.length; i++) {
          if (!list[i].datumVon.isAfter(list[i - 1].datumBis)) {
            fehler.add('${label(list[i - 1])} ↔ ${list[i].zeitraum}');
          }
        }
      }
      expect(fehler, isEmpty);
    });
  });

  testWidgets('App startet und zeigt die Terminliste', (tester) async {
    SharedPreferences.setMockInitialValues({});

    await tester.pumpWidget(const ZoiglApp());
    // Asset-Laden und SharedPreferences laufen außerhalb der Fake-Zeit.
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 500)),
    );
    await tester.pumpAndSettle();

    expect(find.text('ZoiglZeit 2026'), findsOneWidget);
    expect(find.textContaining('Terminen'), findsOneWidget);
    expect(find.text('Vergangene'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });
}
