import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:intl/intl.dart';

import 'main.dart';

/// Detailseite einer Zoiglstube: Ort, Homepage, Karte und alle Termine.
class ZoiglStubeDetailPage extends StatefulWidget {
  const ZoiglStubeDetailPage({
    super.key,
    required this.zoiglstube,
    required this.ort,
    required this.termine,
    required this.isFavorite,
    required this.onToggleFavorite,
    this.homepage,
    this.showMap = true,
  });

  final String zoiglstube;
  final String ort;

  /// Alle Termine dieser Zoiglstube (vergangene und kommende).
  final List<ZoiglEvent> termine;
  final String? homepage;

  /// Liefert den aktuellen Favoriten-Status (liegt im Zustand der Startseite).
  final bool Function() isFavorite;
  final Future<void> Function() onToggleFavorite;

  /// In Widget-Tests abschaltbar, weil die Karte Kacheln aus dem Netz lädt.
  final bool showMap;

  @override
  State<ZoiglStubeDetailPage> createState() => _ZoiglStubeDetailPageState();
}

class _ZoiglStubeDetailPageState extends State<ZoiglStubeDetailPage> {
  static final _datum = DateFormat('dd.MM.yyyy');

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final kommend = widget.termine.where((e) => !e.endsBefore(today)).toList()
      ..sort((a, b) => a.datumVon.compareTo(b.datumVon));
    final vergangen = widget.termine.where((e) => e.endsBefore(today)).toList()
      ..sort((a, b) => b.datumVon.compareTo(a.datumVon));
    final heuteOffen = kommend.any((e) => e.isOpenOn(now));
    final isFav = widget.isFavorite();
    final coords = kOrtCoordinates[widget.ort];

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.zoiglstube),
        actions: [
          IconButton(
            icon: Icon(
              isFav ? Icons.favorite : Icons.favorite_border,
              color: isFav ? Colors.red : null,
            ),
            tooltip: isFav ? 'Aus Favoriten entfernen' : 'Als Favorit merken',
            onPressed: () async {
              await widget.onToggleFavorite();
              if (mounted) setState(() {});
            },
          ),
        ],
      ),
      body: SafeArea(
        top: false,
        bottom: false,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Row(
              children: [
                Icon(Icons.place, color: Theme.of(context).colorScheme.primary),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    widget.ort,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                if (heuteOffen)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.amber.shade800,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Text(
                      'HEUTE OFFEN',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            _buildHomepage(context),
            if (widget.showMap && coords != null) ...[
              const SizedBox(height: 16),
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: SizedBox(
                  height: 180,
                  child: FlutterMap(
                    options: MapOptions(
                      initialCenter: coords,
                      initialZoom: 12.5,
                      interactionOptions: const InteractionOptions(
                        flags: InteractiveFlag.none,
                      ),
                    ),
                    children: [
                      TileLayer(
                        urlTemplate:
                            'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                        userAgentPackageName: 'net.grafm.zoiglzeit',
                      ),
                      MarkerLayer(
                        markers: [
                          Marker(
                            point: coords,
                            width: 34,
                            height: 34,
                            child: CircleAvatar(
                              backgroundColor: heuteOffen
                                  ? Colors.amber.shade800
                                  : Theme.of(context).colorScheme.primary,
                              child: const ZoiglStarIcon(
                                size: 20,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SimpleAttributionWidget(
                        source: Text('OpenStreetMap contributors'),
                      ),
                    ],
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  'Kartenpunkt zeigt den Ort, nicht die genaue Adresse.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
            ],
            const SizedBox(height: 20),
            Text(
              'Nächste Termine (${kommend.length})',
              style: Theme.of(context).textTheme.titleMedium
                  ?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            if (kommend.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 8),
                child: Text('Keine anstehenden Termine bekannt.'),
              ),
            ...kommend.map((e) => _buildTermin(context, e, now)),
            if (vergangen.isNotEmpty)
              ExpansionTile(
                tilePadding: EdgeInsets.zero,
                title: Text('Vergangene Termine (${vergangen.length})'),
                children: vergangen
                    .map((e) => _buildTermin(context, e, now))
                    .toList(),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildHomepage(BuildContext context) {
    final url = widget.homepage;
    if (url == null) {
      return Row(
        children: [
          const Icon(Icons.language, size: 20, color: Colors.grey),
          const SizedBox(width: 8),
          Text(
            'Keine Homepage bekannt',
            style: TextStyle(color: Colors.grey.shade700),
          ),
        ],
      );
    }
    final uri = Uri.tryParse(url);
    final isProfil = uri?.host.endsWith('zoiglbier.de') ?? false;
    final host = (uri?.host ?? url).replaceFirst(RegExp(r'^www\.'), '');
    return Align(
      alignment: Alignment.centerLeft,
      child: FilledButton.icon(
        onPressed: () => openExternalUrl(context, url),
        icon: const Icon(Icons.open_in_new),
        label: Text(isProfil ? 'Profil auf zoiglbier.de' : 'Homepage: $host'),
      ),
    );
  }

  Widget _buildTermin(BuildContext context, ZoiglEvent e, DateTime now) {
    final offen = e.isOpenOn(now);
    final zeitraum = e.datumVon == e.datumBis
        ? _datum.format(e.datumVon)
        : '${_datum.format(e.datumVon)} – ${_datum.format(e.datumBis)}';
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: offen
            ? BorderSide(color: Colors.amber.shade800, width: 1.5)
            : BorderSide.none,
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.event, size: 16, color: Colors.grey),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    '$zeitraum (${e.wochentage})',
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
                if (offen)
                  Text(
                    'OFFEN',
                    style: TextStyle(
                      color: Colors.amber.shade900,
                      fontWeight: FontWeight.bold,
                      fontSize: 11,
                    ),
                  ),
              ],
            ),
            if (e.oeffnungszeiten.isNotEmpty) ...[
              const SizedBox(height: 4),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.schedule, size: 16, color: Colors.grey),
                  const SizedBox(width: 6),
                  Expanded(child: Text(e.oeffnungszeiten)),
                ],
              ),
            ],
            if (e.bemerkung.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(
                '🎉 ${e.bemerkung}',
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  color: Colors.amber.shade900,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
