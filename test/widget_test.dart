import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:zoigl_zeit/main.dart';
import 'package:zoigl_zeit/stube_detail_page.dart';

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

  List<ZoiglEvent> alleEvents() => [
    for (final asset in kCsvAssets)
      ...File(asset)
          .readAsLinesSync()
          .skip(1)
          .where((l) => l.trim().isNotEmpty)
          .map(ZoiglEvent.fromCsvLine),
  ];

  test('Öffnungszeiten sind optional', () {
    final e = ZoiglEvent.fromCsvLine(
      '2027-01-02;2027-01-05;02.01.-05.01.;Sa - Di;Kramer-Wolf;Falkenberg;;ab 11 Uhr',
    );
    expect(e.bemerkung, isEmpty);
    expect(e.oeffnungszeiten, 'ab 11 Uhr');
    final ohne = ZoiglEvent.fromCsvLine(
      '2026-01-05;2026-01-05;05.01.;Mo;Zum Waldhauser;Neustadt/WN;',
    );
    expect(ohne.oeffnungszeiten, isEmpty);
  });

  test('alle CSV-Assets stehen in pubspec.yaml', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();
    for (final asset in [...kCsvAssets, kStubenAsset]) {
      expect(pubspec, contains('- $asset'));
    }
  });

  group('Zoiglstuben-Homepages', () {
    final raw = File(kStubenAsset).readAsStringSync();
    final homepages = parseStubenHomepages(raw);

    test('parst Zeilen und überspringt leere Homepages', () {
      final h = parseStubenHomepages(
        '﻿Zoiglstube;Ort;Homepage\r\n'
        'Bahler;Neuhaus;https://bahler-zoigl.de/\r\n'
        'Zum Mundl;Störnstein;\r\n',
      );
      expect(h, {stubenKey('Bahler', 'Neuhaus'): 'https://bahler-zoigl.de/'});
    });

    test('jede Zoiglstube aus der Liste hat Termine im Kalender', () {
      final ausKalender = alleEvents()
          .map((e) => stubenKey(e.zoiglstube, e.ort))
          .toSet();
      final unbekannt = homepages.keys
          .where((k) => !ausKalender.contains(k))
          .toList();
      expect(unbekannt, isEmpty);
    });

    test('Homepages sind gültige http(s)-Links ohne Duplikate', () {
      final zeilen = raw
          .split(RegExp(r'\r?\n'))
          .skip(1)
          .where((l) => l.trim().isNotEmpty)
          .length;
      expect(homepages.length, zeilen);
      for (final url in homepages.values) {
        final uri = Uri.parse(url);
        expect(uri.scheme, anyOf('http', 'https'), reason: url);
        expect(uri.host, isNotEmpty, reason: url);
      }
    });
  });

  group('Detailseite', () {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    String iso(DateTime d) => d.toIso8601String().substring(0, 10);
    ZoiglEvent termin(DateTime von, DateTime bis, [String zeiten = '']) =>
        ZoiglEvent.fromCsvLine(
          '${iso(von)};${iso(bis)};x;Fr - So;Bahler;Neuhaus;;$zeiten',
        );

    Widget seite({String? homepage, required List<ZoiglEvent> termine}) {
      var fav = false;
      return MaterialApp(
        home: ZoiglStubeDetailPage(
          zoiglstube: 'Bahler',
          ort: 'Neuhaus',
          homepage: homepage,
          termine: termine,
          isFavorite: () => fav,
          onToggleFavorite: () async => fav = !fav,
          showMap: false,
        ),
      );
    }

    testWidgets('zeigt Homepage, kommende und vergangene Termine', (
      tester,
    ) async {
      await tester.pumpWidget(
        seite(
          homepage: 'https://www.bahler-zoigl.de/',
          termine: [
            termin(
              today.subtract(const Duration(days: 30)),
              today.subtract(const Duration(days: 28)),
            ),
            termin(today, today.add(const Duration(days: 2)), 'ab 14 Uhr'),
            termin(
              today.add(const Duration(days: 30)),
              today.add(const Duration(days: 32)),
            ),
          ],
        ),
      );

      expect(find.text('Bahler'), findsOneWidget);
      expect(find.text('Neuhaus'), findsOneWidget);
      expect(find.text('Homepage: bahler-zoigl.de'), findsOneWidget);
      expect(find.text('HEUTE OFFEN'), findsOneWidget);
      expect(find.text('Nächste Termine (2)'), findsOneWidget);
      expect(find.text('ab 14 Uhr'), findsOneWidget);
      expect(find.text('Vergangene Termine (1)'), findsOneWidget);
    });

    testWidgets('ohne Homepage und Termine', (tester) async {
      await tester.pumpWidget(seite(termine: []));
      expect(find.text('Keine Homepage bekannt'), findsOneWidget);
      expect(find.text('Keine anstehenden Termine bekannt.'), findsOneWidget);
      expect(find.textContaining('Vergangene Termine'), findsNothing);
    });

    testWidgets('zoiglbier.de-Profil wird als Profil beschriftet', (
      tester,
    ) async {
      await tester.pumpWidget(
        seite(
          homepage: 'https://zoiglbier.de/die-brauer/neuhaus/kaeckn/',
          termine: [],
        ),
      );
      expect(find.text('Profil auf zoiglbier.de'), findsOneWidget);
    });

    testWidgets('Favorit lässt sich umschalten', (tester) async {
      await tester.pumpWidget(seite(termine: []));
      expect(find.byIcon(Icons.favorite_border), findsOneWidget);
      await tester.tap(find.byIcon(Icons.favorite_border));
      await tester.pump();
      expect(find.byIcon(Icons.favorite), findsOneWidget);
    });
  });

  test('jeder Ort in der CSV hat Koordinaten für die Karte', () {
    final orte = alleEvents().map((e) => e.ort).toSet();
    final ohneKoordinaten = orte
        .where((o) => !kOrtCoordinates.containsKey(o))
        .toList();
    expect(ohneKoordinaten, isEmpty);
  });

  group('CSV-Daten', () {
    final events = alleEvents();
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

    expect(find.text('Zoiglkalender'), findsOneWidget);
    expect(find.textContaining('Terminen'), findsOneWidget);
    expect(find.text('Vergangene'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);

    // Klick auf einen Termin öffnet die Detailseite der Zoiglstube.
    await tester.tap(find.byType(ListTile).first);
    await tester.pumpAndSettle();
    expect(find.byType(ZoiglStubeDetailPage), findsOneWidget);
    expect(find.textContaining('Nächste Termine'), findsOneWidget);
  });
}
