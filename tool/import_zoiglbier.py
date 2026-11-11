"""Übernimmt die Termine von zoiglbier.de/zoigltermine (CSV: Zoiglstube;Ort;Beginn;Ende;Öffnungszeiten)
in das App-Format.

- Termine aus Jahren, für die es schon eine assets/zoiglkalender_<jahr>.csv gibt:
  dort nur die Öffnungszeiten ergänzen (gleiche Stube, gleiches Datum).
- Alle anderen Jahre: neue assets/zoiglkalender_<jahr>.csv anlegen.

Aufruf: python tool/import_zoiglbier.py zoigltermine.csv
"""
import csv, datetime as dt, os, sys

HEADER = ['Datum_Von', 'Datum_Bis', 'Zeitraum', 'Wochentage', 'Zoiglstube', 'Ort', 'Bemerkung', 'Oeffnungszeiten']
TAGE = ['Mo', 'Di', 'Mi', 'Do', 'Fr', 'Sa', 'So']
# Schreibweise zoiglbier.de -> Schreibweise im Zoiglkalender (Favoriten hängen am Namen)
NAMEN = {
    'Strehern': 'Beim Strehern',
    'Lingl': 'Lingl-Zoigl',
    'Schlosshof': 'Schlosshof-Zoigl',
    'Kramer Wolf': 'Kramer-Wolf',
    'Käckn': "Käck'n",
    'Zum Roudn': "Zum Roud'n",
}
# Einträge ohne echten Ort (Karte/Ortsfilter brauchen einen Ort)
OHNE_ORT = {'Nähere Infos folgen!'}

def zeile(von, bis, stube, ort, bem, zeiten):
    fmt = lambda d: d.strftime('%d.%m.')
    same = von == bis
    zr = fmt(von) if same else f'{fmt(von)}-{fmt(bis)}'
    wt = TAGE[von.weekday()] if same else f'{TAGE[von.weekday()]} - {TAGE[bis.weekday()]}'
    return [von.isoformat(), bis.isoformat(), zr, wt, stube, ort, bem, zeiten]

def lesen(pfad):
    with open(pfad, encoding='utf-8-sig', newline='') as f:
        return list(csv.reader(f, delimiter=';'))

def schreiben(pfad, rows):
    with open(pfad, 'w', encoding='utf-8-sig', newline='') as f:
        w = csv.writer(f, delimiter=';', lineterminator='\r\n', quoting=csv.QUOTE_NONE, escapechar=chr(92))
        w.writerow(HEADER)
        # Spalte Oeffnungszeiten ist optional – leer weglassen, das hält Diffs klein
        w.writerows(r[:7] if len(r) > 7 and not r[7] else r for r in rows)

quelle = lesen(sys.argv[1])[1:]
pro_jahr = {}
for stube, ort, von, bis, zeiten in quelle:
    if ort in OHNE_ORT:
        print('übersprungen (kein Ort):', stube, von)
        continue
    von, bis = dt.date.fromisoformat(von), dt.date.fromisoformat(bis)
    pro_jahr.setdefault(von.year, []).append((von, bis, NAMEN.get(stube, stube), ort, zeiten.replace(';', ',')))

for jahr, termine in sorted(pro_jahr.items()):
    pfad = f'assets/zoiglkalender_{jahr}.csv'
    if os.path.exists(pfad):
        rows = [r + [''] * (8 - len(r)) for r in lesen(pfad)[1:] if any(r)]
        index = {(r[0], r[1], r[4], r[5]): r for r in rows}
        for von, bis, stube, ort, zeiten in termine:
            r = index.get((von.isoformat(), bis.isoformat(), stube, ort))
            if r is None:
                print('kein passender Termin in', pfad, ':', stube, ort, von)
            elif zeiten:
                r[7] = zeiten
    else:
        rows = [zeile(von, bis, stube, ort, '', zeiten) for von, bis, stube, ort, zeiten in sorted(termine)]
    schreiben(pfad, rows)
    print(pfad, len(rows), 'Termine')
