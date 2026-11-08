import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:intl/intl.dart';
import 'package:latlong2/latlong.dart' hide Path;
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  runApp(const ZoiglApp());
}

class ZoiglApp extends StatelessWidget {
  const ZoiglApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Zoiglkalender 2026',
      debugShowCheckedModeBanner: false,
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const [
        Locale('de', 'DE'),
      ],
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF1B5E20), // Dunkelgrün / Waldgrün
          primary: const Color(0xFF1B5E20),
          brightness: Brightness.light,
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFF1B5E20),
          foregroundColor: Colors.white,
        ),
      ),
      home: const ZoiglHomePage(),
    );
  }
}

/// Koordinaten-Tabelle für alle 26 Zoigl-Orte im Oberpfälzer Wald
const Map<String, LatLng> kOrtCoordinates = {
  'Burkhardsreuth': LatLng(49.8058, 11.8386),
  'Bärnau': LatLng(49.8111, 12.4356),
  'Eslarn': LatLng(49.5831, 12.5206),
  'Falkenberg': LatLng(49.8586, 12.2247),
  'Fuchsmühl': LatLng(49.9250, 12.1481),
  'Hammerles': LatLng(49.7186, 12.0833),
  'Kohlberg': LatLng(49.5939, 12.0169),
  'Konnersreuth': LatLng(50.0172, 12.2356),
  'Krummennaab': LatLng(49.8322, 12.0994),
  'Mitterteich': LatLng(49.9486, 12.2422),
  'Nabburg': LatLng(49.4539, 12.1786),
  'Neuhaus': LatLng(49.7997, 12.1647),
  'Neunkirchen b. Weiden': LatLng(49.6875, 12.1128),
  'Neustadt/WN': LatLng(49.7308, 12.1714),
  'Pfaffenreuth': LatLng(50.0039, 12.1819),
  'Plößberg': LatLng(49.7931, 12.3119),
  'Reuth b. Erbendorf': LatLng(49.8453, 12.1189),
  'Störnstein': LatLng(49.7294, 12.2039),
  'Tirschenreuth': LatLng(49.8806, 12.3372),
  'Trausnitz': LatLng(49.5228, 12.2669),
  'Waldershof': LatLng(49.9822, 12.0628),
  'Waldsassen': LatLng(50.0044, 12.3086),
  'Weiden i.d.OPf.': LatLng(49.6761, 12.1561),
  'Wiesau': LatLng(49.9086, 12.1869),
  'Windischeschenbach': LatLng(49.8047, 12.1569),
  'Windmais': LatLng(49.2869, 12.3106),
};

class ZoiglEvent {
  final DateTime datumVon;
  final DateTime datumBis;
  final String zeitraum;
  final String wochentage;
  final String zoiglstube;
  final String ort;
  final String bemerkung;

  ZoiglEvent({
    required this.datumVon,
    required this.datumBis,
    required this.zeitraum,
    required this.wochentage,
    required this.zoiglstube,
    required this.ort,
    required this.bemerkung,
  });

  bool isOpenOn(DateTime date) {
    final check = DateTime(date.year, date.month, date.day);
    final start = DateTime(datumVon.year, datumVon.month, datumVon.day);
    final end = DateTime(datumBis.year, datumBis.month, datumBis.day);
    return (check.isAtSameMomentAs(start) || check.isAfter(start)) &&
        (check.isAtSameMomentAs(end) || check.isBefore(end));
  }

  factory ZoiglEvent.fromCsvLine(String line) {
    final parts = line.split(';');
    return ZoiglEvent(
      datumVon: DateTime.parse(parts[0].trim()),
      datumBis: DateTime.parse(parts[1].trim()),
      zeitraum: parts[2].trim(),
      wochentage: parts[3].trim(),
      zoiglstube: parts[4].trim(),
      ort: parts[5].trim(),
      bemerkung: parts.length > 6 ? parts[6].trim() : '',
    );
  }
}

class ZoiglHomePage extends StatefulWidget {
  const ZoiglHomePage({super.key});

  @override
  State<ZoiglHomePage> createState() => _ZoiglHomePageState();
}

class _ZoiglHomePageState extends State<ZoiglHomePage> {
  List<ZoiglEvent> _allEvents = [];
  List<ZoiglEvent> _filteredEvents = [];
  List<String> _availableOrte = [];
  Set<String> _favoriteStuben = {};

  String _searchQuery = '';
  String? _selectedOrt;
  DateTime? _selectedDate;
  bool _onlyOpenToday = false;
  bool _onlyFavorites = false;
  bool _isLoading = true;
  int _currentTabIndex = 0;

  final TextEditingController _searchController = TextEditingController();
  final MapController _mapController = MapController();

  @override
  void initState() {
    super.initState();
    _initData();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _initData() async {
    await _loadFavorites();
    await _loadCsvData();
  }

  Future<void> _loadFavorites() async {
    final prefs = await SharedPreferences.getInstance();
    final favList = prefs.getStringList('favorite_zoiglstuben') ?? [];
    setState(() {
      _favoriteStuben = favList.toSet();
    });
  }

  Future<void> _toggleFavorite(String zoiglstube) async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      if (_favoriteStuben.contains(zoiglstube)) {
        _favoriteStuben.remove(zoiglstube);
      } else {
        _favoriteStuben.add(zoiglstube);
      }
    });
    await prefs.setStringList('favorite_zoiglstuben', _favoriteStuben.toList());
    _applyFilters();
  }

  Future<void> _loadCsvData() async {
    try {
      final rawCsv = await rootBundle.loadString('assets/zoiglkalender_2026.csv');
      final lines = rawCsv
          .split(RegExp(r'\r?\n'))
          .where((line) => line.trim().isNotEmpty)
          .toList();

      final events = <ZoiglEvent>[];
      for (int i = 1; i < lines.length; i++) {
        try {
          events.add(ZoiglEvent.fromCsvLine(lines[i]));
        } catch (e) {
          debugPrint('Fehler in Zeile $i: ${lines[i]}');
        }
      }

      events.sort((a, b) => a.datumVon.compareTo(b.datumVon));

      final orteSet = events.map((e) => e.ort).where((o) => o.isNotEmpty).toSet();
      final orteList = orteSet.toList()..sort();

      setState(() {
        _allEvents = events;
        _availableOrte = orteList;
        _isLoading = false;
      });
      _applyFilters();
    } catch (e) {
      debugPrint('Fehler beim Laden der CSV: $e');
      setState(() => _isLoading = false);
    }
  }

  void _applyFilters() {
    setState(() {
      _filteredEvents = _allEvents.where((event) {
        if (_searchQuery.isNotEmpty) {
          final q = _searchQuery.toLowerCase();
          final matchWirt = event.zoiglstube.toLowerCase().contains(q);
          final matchOrt = event.ort.toLowerCase().contains(q);
          final matchBemerkung = event.bemerkung.toLowerCase().contains(q);
          if (!matchWirt && !matchOrt && !matchBemerkung) return false;
        }

        if (_selectedOrt != null && event.ort != _selectedOrt) {
          return false;
        }

        if (_selectedDate != null) {
          if (!event.isOpenOn(_selectedDate!)) return false;
        }

        if (_onlyOpenToday) {
          if (!event.isOpenOn(DateTime.now())) return false;
        }

        if (_onlyFavorites) {
          if (!_favoriteStuben.contains(event.zoiglstube)) return false;
        }

        return true;
      }).toList();
    });
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final initial = _selectedDate ?? (now.year == 2026 ? now : DateTime(2026, 1, 1));

    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(2026, 1, 1),
      lastDate: DateTime(2026, 12, 31),
      locale: const Locale('de', 'DE'),
      helpText: 'Ausschank-Datum wählen',
    );

    if (picked != null) {
      setState(() {
        _selectedDate = picked;
        _onlyOpenToday = false;
      });
      _applyFilters();
    }
  }

  void _resetFilters() {
    _searchController.clear();
    setState(() {
      _searchQuery = '';
      _selectedOrt = null;
      _selectedDate = null;
      _onlyOpenToday = false;
      _onlyFavorites = false;
    });
    _applyFilters();
  }

  void _showImpressum(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return DraggableScrollableSheet(
          initialChildSize: 0.6,
          maxChildSize: 0.9,
          minChildSize: 0.4,
          expand: false,
          builder: (_, scrollController) {
            return SingleChildScrollView(
              controller: scrollController,
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Row(
                        children: [
                          ZoiglStarIcon(size: 26, color: Color(0xFF1B5E20)),
                          SizedBox(width: 10),
                          Text(
                            'Impressum & Infos',
                            style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                      IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: () => Navigator.pop(ctx),
                      ),
                    ],
                  ),
                  const Divider(height: 20),
                  //const Text(
                  //  'Autor der App:',
                  //  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                  //),
                  //const SizedBox(height: 4),
                  //const Text(
                  //  'Michael Graf für Zoigl Jehovas\n'
                  //  'migraf18@gmail.com\n'
                  //  '\n'
                  //  'www.grafm.net'
                  //),
                  const SizedBox(height: 12),
                  const Text(
                    'Datenquelle:',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'Tourismusverband Oberpfälzer Wald\n'
                    'Web: www.oberpfaelzerwald.de',
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'Hinweise:',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'Die auf Meldung der Wirte bzw. Gemeinden beruhenden Angaben '
                    'wurden sorgfältig erhoben und bearbeitet. Änderungen und Irrtum vorbehalten.',
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'Urheberrecht:',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                  ),
                  const Text(
                    'steht unter Apache License 2.0\n'
                    'https://www.apache.org/licenses/LICENSE-2.0\n'
                    '(c) 2026 Michael Graf (Zoiglbrüder Zoigl Jehovas)\n'
                    'www.grafm.net',
                  ),
                  const SizedBox(height: 20),
                  Center(
                    child: OutlinedButton.icon(
                      onPressed: () => Navigator.pop(ctx),
                      icon: const Icon(Icons.check),
                      label: const Text('Schließen'),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final dateFormatter = DateFormat('dd.MM.yyyy', 'de_DE');
    final hasActiveFilters = _searchQuery.isNotEmpty ||
        _selectedOrt != null ||
        _selectedDate != null ||
        _onlyOpenToday ||
        _onlyFavorites;

    return Scaffold(
      appBar: AppBar(
        title: const Row(
          children: [
            ZoiglStarIcon(size: 34, color: Colors.white),
            SizedBox(width: 12),
            Text(
              'ZoiglZeit 2026',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
          ],
        ),
        actions: [
          if (hasActiveFilters)
            IconButton(
              icon: const Icon(Icons.filter_alt_off),
              tooltip: 'Alle Filter zurücksetzen',
              onPressed: _resetFilters,
            ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                _buildFilterHeader(dateFormatter),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  color: Theme.of(context)
                      .colorScheme
                      .surfaceContainerHighest
                      .withValues(alpha: 0.4),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        '${_filteredEvents.length} von ${_allEvents.length} Terminen',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                      if (_favoriteStuben.isNotEmpty)
                        Text(
                          '★ ${_favoriteStuben.length} Favoriten gespeichert',
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                color: Colors.amber.shade900,
                                fontWeight: FontWeight.w600,
                              ),
                        ),
                    ],
                  ),
                ),
                Expanded(
                  child: _currentTabIndex == 0
                      ? _buildListView()
                      : _buildMapView(),
                ),
              ],
            ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _currentTabIndex,
        onDestinationSelected: (index) {
          setState(() => _currentTabIndex = index);
        },
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.list_alt),
            selectedIcon: Icon(Icons.list_alt),
            label: 'Terminliste',
          ),
          NavigationDestination(
            icon: Icon(Icons.map_outlined),
            selectedIcon: Icon(Icons.map),
            label: 'Zoigl-Karte',
          ),
        ],
      ),
    );
  }

  Widget _buildFilterHeader(DateFormat dateFormatter) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        children: [
          Row(
            children: [
              IconButton(
                icon: const Icon(Icons.info_outline),
                color: Theme.of(context).colorScheme.primary,
                tooltip: 'Impressum & Infos',
                onPressed: () => _showImpressum(context),
              ),
              const SizedBox(width: 4),
              Expanded(
                child: TextField(
                  controller: _searchController,
                  decoration: InputDecoration(
                    hintText: 'Zoiglstube, Ort oder Anlass suchen...',
                    prefixIcon: const Icon(Icons.search),
                    suffixIcon: _searchQuery.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear),
                            onPressed: () {
                              _searchController.clear();
                              setState(() => _searchQuery = '');
                              _applyFilters();
                            },
                          )
                        : null,
                    filled: true,
                    contentPadding: const EdgeInsets.symmetric(vertical: 0),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                  ),
                  onChanged: (value) {
                    setState(() => _searchQuery = value);
                    _applyFilters();
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                FilterChip(
                  label: Text(
                    _favoriteStuben.isEmpty
                        ? 'Favoriten'
                        : 'Favoriten (${_favoriteStuben.length})',
                  ),
                  selected: _onlyFavorites,
                  avatar: Icon(
                    _onlyFavorites ? Icons.favorite : Icons.favorite_border,
                    size: 18,
                    color: _onlyFavorites ? Colors.red : null,
                  ),
                  onSelected: (val) {
                    setState(() => _onlyFavorites = val);
                    _applyFilters();
                  },
                ),
                const SizedBox(width: 8),
                FilterChip(
                  label: const Text('Heute offen'),
                  selected: _onlyOpenToday,
                  avatar: const Icon(Icons.today, size: 18),
                  onSelected: (val) {
                    setState(() {
                      _onlyOpenToday = val;
                      if (val) _selectedDate = null;
                    });
                    _applyFilters();
                  },
                ),
                const SizedBox(width: 8),
                InputChip(
                  avatar: const Icon(Icons.calendar_month, size: 18),
                  label: Text(
                    _selectedDate == null
                        ? 'Datum wählen'
                        : dateFormatter.format(_selectedDate!),
                  ),
                  selected: _selectedDate != null,
                  onPressed: _pickDate,
                  onDeleted: _selectedDate != null
                      ? () {
                          setState(() => _selectedDate = null);
                          _applyFilters();
                        }
                      : null,
                ),
                const SizedBox(width: 8),
                InputChip(
                  avatar: const Icon(Icons.location_on_outlined, size: 18),
                  label: Text(_selectedOrt ?? 'Alle Orte (${_availableOrte.length})'),
                  selected: _selectedOrt != null,
                  onPressed: () => _showOrtPicker(context),
                  onDeleted: _selectedOrt != null
                      ? () {
                          setState(() => _selectedOrt = null);
                          _applyFilters();
                        }
                      : null,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildListView() {
    if (_filteredEvents.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.sentiment_dissatisfied, size: 56, color: Colors.grey.shade400),
            const SizedBox(height: 12),
            const Text(
              'Keine Zoigl-Termine für diesen Filter gefunden.',
              style: TextStyle(fontSize: 16),
            ),
            const SizedBox(height: 8),
            TextButton.icon(
              onPressed: _resetFilters,
              icon: const Icon(Icons.refresh),
              label: const Text('Filter zurücksetzen'),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: _filteredEvents.length,
      itemBuilder: (context, index) {
        final event = _filteredEvents[index];
        return _buildEventCard(event);
      },
    );
  }

  Widget _buildEventCard(ZoiglEvent event) {
    final isOpenNow = event.isOpenOn(DateTime.now());
    final isFav = _favoriteStuben.contains(event.zoiglstube);

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      elevation: isOpenNow ? 3 : 1,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: isOpenNow
            ? BorderSide(color: Colors.amber.shade800, width: 1.5)
            : BorderSide.none,
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        leading: Container(
          width: 58,
          padding: const EdgeInsets.symmetric(vertical: 6),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.primaryContainer,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                DateFormat('dd.MM.').format(event.datumVon),
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                  color: Theme.of(context).colorScheme.onPrimaryContainer,
                ),
              ),
              if (event.datumVon != event.datumBis)
                Text(
                  'bis ${DateFormat('dd.MM.').format(event.datumBis)}',
                  style: TextStyle(
                    fontSize: 10,
                    color: Theme.of(context).colorScheme.onPrimaryContainer,
                  ),
                ),
            ],
          ),
        ),
        title: Row(
          children: [
            Expanded(
              child: Text(
                event.zoiglstube,
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              ),
            ),
            if (isOpenNow)
              Container(
                margin: const EdgeInsets.only(right: 4),
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.amber.shade800,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Text(
                  'OFFEN',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
          ],
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.place, size: 15, color: Colors.grey),
                  const SizedBox(width: 4),
                  Flexible(
                    child: Text(
                      event.ort,
                      style: const TextStyle(fontWeight: FontWeight.w500),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 10),
                  const Icon(Icons.access_time, size: 15, color: Colors.grey),
                  const SizedBox(width: 4),
                  Text('${event.zeitraum} (${event.wochentage})'),
                ],
              ),
              if (event.bemerkung.isNotEmpty) ...[
                const SizedBox(height: 6),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: Colors.amber.shade100,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    '🎉 ${event.bemerkung}',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: Colors.amber.shade900,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
        trailing: IconButton(
          icon: Icon(
            isFav ? Icons.favorite : Icons.favorite_border,
            color: isFav ? Colors.red : Colors.grey,
          ),
          tooltip: isFav ? 'Aus Favoriten entfernen' : 'Als Favorit merken',
          onPressed: () => _toggleFavorite(event.zoiglstube),
        ),
      ),
    );
  }

  Widget _buildMapView() {
    final Color todayColor = Colors.amber.shade800;
    final Color plannedColor = Theme.of(context).colorScheme.primary;

    final Map<String, List<ZoiglEvent>> eventsByOrt = {};
    for (final ev in _filteredEvents) {
      eventsByOrt.putIfAbsent(ev.ort, () => []).add(ev);
    }

    final markers = <Marker>[];
    eventsByOrt.forEach((ort, ortEvents) {
      final coords = kOrtCoordinates[ort];
      if (coords == null) return;

      final hasOpenToday = ortEvents.any((e) => e.isOpenOn(DateTime.now()));
      final hasFavorite = ortEvents.any((e) => _favoriteStuben.contains(e.zoiglstube));

      markers.add(
        Marker(
          point: coords,
          width: 110,
          height: 75,
          child: GestureDetector(
            onTap: () => _showOrtEventsBottomSheet(ort, ortEvents),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: hasOpenToday ? todayColor : plannedColor,
                        borderRadius: BorderRadius.circular(16),
                        boxShadow: const [
                          BoxShadow(color: Colors.black26, blurRadius: 4),
                        ],
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const ZoiglStarIcon(size: 16, color: Colors.white),
                          const SizedBox(width: 4),
                          Text(
                            '${ortEvents.length}',
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (hasFavorite)
                      const Positioned(
                        right: -6,
                        top: -6,
                        child: CircleAvatar(
                          radius: 9,
                          backgroundColor: Colors.white,
                          child: Icon(Icons.favorite, size: 12, color: Colors.red),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 2),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.9),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    ort,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      color: Colors.black87,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    });

    return Stack(
      children: [
        FlutterMap(
          mapController: _mapController,
          options: const MapOptions(
            initialCenter: LatLng(49.78, 12.18),
            initialZoom: 9.8,
          ),
          children: [
            TileLayer(
              urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
              userAgentPackageName: 'de.oberpfalz.zoiglkalender2026',
            ),
            MarkerLayer(markers: markers),
          ],
        ),
        Positioned(
          top: 12,
          right: 12,
          child: Card(
            elevation: 3,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.circle, size: 12, color: todayColor),
                      const SizedBox(width: 6),
                      const Text('Heute Ausschank', style: TextStyle(fontSize: 11)),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.circle, size: 12, color: plannedColor),
                      const SizedBox(width: 6),
                      const Text('Geplante Termine', style: TextStyle(fontSize: 11)),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  void _showOrtEventsBottomSheet(String ort, List<ZoiglEvent> ortEvents) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return DraggableScrollableSheet(
              initialChildSize: 0.55,
              maxChildSize: 0.9,
              minChildSize: 0.35,
              expand: false,
              builder: (_, scrollController) {
                return Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Row(
                            children: [
                              Icon(
                                Icons.place,
                                color: Theme.of(context).colorScheme.primary,
                              ),
                              const SizedBox(width: 8),
                              Text(
                                '$ort (${ortEvents.length} Termine)',
                                style: const TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                          IconButton(
                            icon: const Icon(Icons.close),
                            onPressed: () => Navigator.pop(ctx),
                          ),
                        ],
                      ),
                    ),
                    const Divider(height: 1),
                    Expanded(
                      child: ListView.builder(
                        controller: scrollController,
                        padding: const EdgeInsets.all(12),
                        itemCount: ortEvents.length,
                        itemBuilder: (context, index) {
                          final ev = ortEvents[index];
                          return _buildEventCard(ev);
                        },
                      ),
                    ),
                  ],
                );
              },
            );
          },
        );
      },
    );
  }

  void _showOrtPicker(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return DraggableScrollableSheet(
          initialChildSize: 0.6,
          maxChildSize: 0.9,
          minChildSize: 0.4,
          expand: false,
          builder: (_, scrollController) {
            return Column(
              children: [
                const Padding(
                  padding: EdgeInsets.all(16),
                  child: Text(
                    'Ort auswählen',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                ),
                const Divider(height: 1),
                Expanded(
                  child: ListView(
                    controller: scrollController,
                    children: [
                      ListTile(
                        leading: const Icon(Icons.clear_all),
                        title: const Text('Alle Orte anzeigen'),
                        selected: _selectedOrt == null,
                        onTap: () {
                          setState(() => _selectedOrt = null);
                          _applyFilters();
                          Navigator.pop(ctx);
                        },
                      ),
                      ..._availableOrte.map((ort) {
                        final count = _allEvents.where((e) => e.ort == ort).length;
                        return ListTile(
                          leading: const Icon(Icons.location_city),
                          title: Text(ort),
                          trailing: Text('$count Termine'),
                          selected: _selectedOrt == ort,
                          onTap: () {
                            setState(() => _selectedOrt = ort);
                            _applyFilters();
                            Navigator.pop(ctx);
                            if (_currentTabIndex == 1 &&
                                kOrtCoordinates.containsKey(ort)) {
                              _mapController.move(kOrtCoordinates[ort]!, 12.5);
                            }
                          },
                        );
                      }),
                    ],
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }
}

class ZoiglStarIcon extends StatelessWidget {
  final double size;
  final Color? color;

  const ZoiglStarIcon({
    super.key,
    this.size = 32.0,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    final starColor = color ?? Theme.of(context).colorScheme.onPrimaryContainer;
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          CustomPaint(
            size: Size(size, size),
            painter: _ZoiglStarPainter(color: starColor),
          ),
          Icon(
            Icons.sports_bar,
            size: size * 0.36,
            color: starColor,
          ),
        ],
      ),
    );
  }
}

class _ZoiglStarPainter extends CustomPainter {
  final Color color;

  const _ZoiglStarPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = size.width * 0.075
      ..strokeJoin = StrokeJoin.round;

    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width * 0.46;

    final pathUp = Path();
    for (int i = 0; i < 3; i++) {
      final angle = (-90 + i * 120) * math.pi / 180;
      final point = Offset(
        center.dx + radius * math.cos(angle),
        center.dy + radius * math.sin(angle),
      );
      if (i == 0) {
        pathUp.moveTo(point.dx, point.dy);
      } else {
        pathUp.lineTo(point.dx, point.dy);
      }
    }
    pathUp.close();

    final pathDown = Path();
    for (int i = 0; i < 3; i++) {
      final angle = (90 + i * 120) * math.pi / 180;
      final point = Offset(
        center.dx + radius * math.cos(angle),
        center.dy + radius * math.sin(angle),
      );
      if (i == 0) {
        pathDown.moveTo(point.dx, point.dy);
      } else {
        pathDown.lineTo(point.dx, point.dy);
      }
    }
    pathDown.close();

    canvas.drawPath(pathUp, paint);
    canvas.drawPath(pathDown, paint);
  }

  @override
  bool shouldRepaint(covariant _ZoiglStarPainter oldDelegate) =>
      oldDelegate.color != color;
}