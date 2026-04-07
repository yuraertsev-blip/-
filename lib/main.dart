import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

// Твои настройки из консоли Firebase
const firebaseOptions = FirebaseOptions(
  apiKey: "AIzaSyC0rFOiAx5LEpT-6s9Bc8sxNtc59RfsOcM",
  authDomain: "u-coffee.firebaseapp.com",
  databaseURL: "https://u-coffee-default-rtdb.firebaseio.com",
  projectId: "u-coffee",
  storageBucket: "u-coffee.firebasestorage.app",
  messagingSenderId: "971000964907",
  appId: "1:971000964907:web:b1e9271ca53fbfff6ac76e",
  measurementId: "G-M5HM5H2D75"
);

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting('ru_RU', null);
  await Firebase.initializeApp(options: firebaseOptions);
  runApp(const MockApp());
}

// ==========================================
// Модели и Стейт (Синхронизация Firebase Firestore)
// ==========================================

enum ShiftType { none, full, morning, evening }
enum PrefType { none, ready, readyAfter15, readyBefore15, notReady }

class AppState extends ChangeNotifier {
  final List<String> baristas = ['Юрий', 'Валерия', 'Дарьяна', 'Анастасия'];
  
  // Ставки бариста (можно вынести в отдельную коллекцию в Firebase позже)
  final Map<String, double> rates = {
    'Юрий': 350,
    'Валерия': 300,
    'Дарьяна': 280,
    'Анастасия': 280,
  };

  Map<String, Map<String, ShiftType>> shifts = {};
  Map<String, Map<String, PrefType>> prefs = {};
  List<String> auditLogs = [];
  
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  AppState() {
    _initStreams();
  }

  void _initStreams() {
    // 1. Слушаем смены онлайн
    _db.collection('settings').doc('shifts').snapshots().listen((snap) {
      if (snap.exists) {
        final data = snap.data() as Map<String, dynamic>;
        shifts.clear();
        data.forEach((barista, datesMap) {
          shifts[barista] = {};
          (datesMap as Map<String, dynamic>).forEach((date, typeIndex) {
            shifts[barista]![date] = ShiftType.values[(typeIndex as num).toInt()];
          });
        });
        notifyListeners();
      }
    });

    // 2. Слушаем пожелания онлайн
    _db.collection('settings').doc('prefs').snapshots().listen((snap) {
      if (snap.exists) {
        final data = snap.data() as Map<String, dynamic>;
        prefs.clear();
        data.forEach((barista, datesMap) {
          prefs[barista] = {};
          (datesMap as Map<String, dynamic>).forEach((date, typeIndex) {
            prefs[barista]![date] = PrefType.values[(typeIndex as num).toInt()];
          });
        });
        notifyListeners();
      }
    });

    // 3. Слушаем историю изменений
    _db.collection('logs').orderBy('time', descending: true).limit(30).snapshots().listen((snap) {
      auditLogs = snap.docs.map((doc) => doc.data()['text'] as String).toList();
      notifyListeners();
    });
  }

  String _dateKey(DateTime d) => DateFormat('yyyy-MM-dd').format(d);

  Future<void> toggleShift(String barista, DateTime date) async {
    String key = _dateKey(date);
    ShiftType current = shifts[barista]?[key] ?? ShiftType.none;
    ShiftType next;
    String actionName;

    switch (current) {
      case ShiftType.none: next = ShiftType.full; actionName = 'Полная смена'; break;
      case ShiftType.full: next = ShiftType.morning; actionName = 'Утро'; break;
      case ShiftType.morning: next = ShiftType.evening; actionName = 'Вечер'; break;
      case ShiftType.evening: next = ShiftType.none; actionName = 'Снята смена'; break;
    }

    if (!shifts.containsKey(barista)) shifts[barista] = {};
    shifts[barista]![key] = next;
    notifyListeners();

    // Исправленное сохранение через точечную нотацию (dot notation)
    await _db.collection('settings').doc('shifts').set({
      '$barista.$key': next.index
    }, SetOptions(merge: true));

    final timeStr = DateFormat('HH:mm').format(DateTime.now());
    final dateStr = DateFormat('dd.MM').format(date);
    
    await _db.collection('logs').add({
      'text': '$timeStr - $barista: $actionName на $dateStr',
      'time': FieldValue.serverTimestamp(),
    });
  }

  Future<void> togglePref(String barista, DateTime date) async {
    String key = _dateKey(date);
    PrefType current = prefs[barista]?[key] ?? PrefType.none;
    PrefType next;

    switch (current) {
      case PrefType.none: next = PrefType.ready; break;
      case PrefType.ready: next = PrefType.readyAfter15; break;
      case PrefType.readyAfter15: next = PrefType.readyBefore15; break;
      case PrefType.readyBefore15: next = PrefType.notReady; break;
      case PrefType.notReady: next = PrefType.none; break;
    }

    if (!prefs.containsKey(barista)) prefs[barista] = {};
    prefs[barista]![key] = next;
    notifyListeners();

    await _db.collection('settings').doc('prefs').set({
      '$barista.$key': next.index
    }, SetOptions(merge: true));
  }

  ShiftType getShift(String barista, DateTime date) => shifts[barista]?[_dateKey(date)] ?? ShiftType.none;
  PrefType getPref(String barista, DateTime date) => prefs[barista]?[_dateKey(date)] ?? PrefType.none;

  double getHoursForMonth(String barista, DateTime month) {
    if (!shifts.containsKey(barista)) return 0;
    double totalHours = 0;
    shifts[barista]!.forEach((dateStr, type) {
      DateTime d = DateTime.parse(dateStr);
      if (d.month == month.month && d.year == month.year) {
        if (type == ShiftType.full) totalHours += 10;
        if (type == ShiftType.morning || type == ShiftType.evening) totalHours += 5;
      }
    });
    return totalHours;
  }

  double getSalaryForMonth(String barista, DateTime month) {
    double hours = getHoursForMonth(barista, month);
    double rate = rates[barista] ?? 250.0;
    return hours * rate;
  }

  int getFullShiftsCount(String barista, DateTime month) {
    if (!shifts.containsKey(barista)) return 0;
    int count = 0;
    shifts[barista]!.forEach((dateStr, type) {
      DateTime d = DateTime.parse(dateStr);
      if (d.month == month.month && d.year == month.year && type == ShiftType.full) count++;
    });
    return count;
  }
}

// ==========================================
// Основной UI (Material 3 Coffee Theme)
// ==========================================

class MockApp extends StatelessWidget {
  const MockApp({super.key});
  @override
  Widget build(BuildContext context) {
    return AppStateProvider(
      state: AppState(),
      child: MaterialApp(
        title: 'Ю Кофе (Онлайн)',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          useMaterial3: true,
          colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF4E342E)),
          scaffoldBackgroundColor: const Color(0xFFFFF8E1),
          appBarTheme: const AppBarTheme(
            centerTitle: true,
            backgroundColor: Color(0xFF4E342E),
            foregroundColor: Colors.white,
            elevation: 0,
          ),
        ),
        home: const MainScreen(),
      ),
    );
  }
}

class AppStateProvider extends InheritedNotifier<AppState> {
  const AppStateProvider({Key? key, required AppState state, required Widget child}) 
      : super(key: key, notifier: state, child: child);

  static AppState of(BuildContext context) => context.dependOnInheritedWidgetOfExactType<AppStateProvider>()!.notifier!;
}

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});
  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  int _currentIndex = 0;
  final screens = const [ScheduleScreen(), ReportScreen(), PreferencesScreen()];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(child: screens[_currentIndex]), 
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentIndex,
        onTap: (i) => setState(() => _currentIndex = i),
        selectedItemColor: const Color(0xFF4E342E),
        unselectedItemColor: Colors.grey,
        backgroundColor: const Color(0xFFFFF8E1),
        type: BottomNavigationBarType.fixed, 
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.calendar_month), label: 'График'),
          BottomNavigationBarItem(icon: Icon(Icons.analytics), label: 'Итоги'),
          BottomNavigationBarItem(icon: Icon(Icons.favorite), label: 'Пожелания'),
        ],
      ),
    );
  }
}

// ==========================================
// ЭКРАНЫ
// ==========================================

class ScheduleScreen extends StatefulWidget {
  const ScheduleScreen({super.key});
  @override
  State<ScheduleScreen> createState() => _ScheduleScreenState();
}

class _ScheduleScreenState extends State<ScheduleScreen> {
  DateTime _selectedMonth = DateTime(DateTime.now().year, DateTime.now().month);
  int _selectedWeek = 0;

  @override
  Widget build(BuildContext context) {
    final state = AppStateProvider.of(context);
    final daysToRender = _getDaysInWeek(_selectedMonth, _selectedWeek);
    final monthName = DateFormat('LLLL yyyy', 'ru_RU').format(_selectedMonth);

    return Column(
      children: [
        _buildHeader(monthName),
        _buildLegend(),
        Expanded(child: _buildGrid(state, daysToRender)),
        _buildLogPanel(state),
      ],
    );
  }

  Widget _buildHeader(String monthName) {
    return Container(
      color: Colors.brown.shade50,
      padding: const EdgeInsets.all(8),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              IconButton(icon: const Icon(Icons.chevron_left), onPressed: () => setState(() => _selectedMonth = DateTime(_selectedMonth.year, _selectedMonth.month - 1))),
              Text(monthName.toUpperCase(), style: const TextStyle(fontWeight: FontWeight.bold)),
              IconButton(icon: const Icon(Icons.chevron_right), onPressed: () => setState(() => _selectedMonth = DateTime(_selectedMonth.year, _selectedMonth.month + 1))),
            ],
          ),
          Wrap(
            spacing: 8,
            children: List.generate(5, (index) => ChoiceChip(
              label: Text('Н. ${index + 1}'),
              selected: _selectedWeek == index,
              onSelected: (_) => setState(() => _selectedWeek = index),
            )),
          )
        ],
      ),
    );
  }

  Widget _buildLegend() {
    return Padding(
      padding: const EdgeInsets.all(8.0),
      child: Wrap(
        spacing: 12,
        children: [
          _dot(Colors.green, '10ч'), _dot(Colors.yellow, 'Утро'), _dot(Colors.purple, 'Вечер'),
        ],
      ),
    );
  }

  Widget _dot(Color c, String t) => Row(mainAxisSize: MainAxisSize.min, children: [
    Container(width: 10, height: 10, decoration: BoxDecoration(color: c, shape: BoxShape.circle)),
    const SizedBox(width: 4), Text(t, style: const TextStyle(fontSize: 10))
  ]);

  Widget _buildGrid(AppState state, List<DateTime> days) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: SingleChildScrollView(
        child: Table(
          defaultColumnWidth: const FixedColumnWidth(55),
          columnWidths: const {0: FixedColumnWidth(100)},
          border: TableBorder.all(color: Colors.brown.shade100),
          children: [
            TableRow(children: [
              const Center(child: Text('Бариста')),
              ...days.map((d) => Center(child: Text(DateFormat('EE\ndd', 'ru_RU').format(d), textAlign: TextAlign.center)))
            ]),
            ...state.baristas.map((barista) => TableRow(children: [
              Padding(padding: const EdgeInsets.all(8.0), child: Text(barista, style: const TextStyle(fontWeight: FontWeight.bold))),
              ...days.map((date) {
                ShiftType type = state.getShift(barista, date);
                return InkWell(
                  onTap: () => state.toggleShift(barista, date),
                  child: Container(
                    height: 50,
                    margin: const EdgeInsets.all(2),
                    decoration: BoxDecoration(
                      color: _getColorForShift(type),
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                );
              })
            ]))
          ],
        ),
      ),
    );
  }

  Widget _buildLogPanel(AppState state) {
    return Container(
      height: 120,
      color: Colors.white,
      child: ListView.builder(
        itemCount: state.auditLogs.length,
        itemBuilder: (context, i) => Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
          child: Text(state.auditLogs[i], style: const TextStyle(fontSize: 10, color: Colors.grey)),
        ),
      ),
    );
  }

  Color _getColorForShift(ShiftType t) {
    if (t == ShiftType.full) return Colors.green.shade300;
    if (t == ShiftType.morning) return Colors.yellow.shade300;
    if (t == ShiftType.evening) return Colors.purple.shade200;
    return Colors.transparent;
  }

  List<DateTime> _getDaysInWeek(DateTime month, int week) {
    int start = week * 7 + 1;
    int last = DateTime(month.year, month.month + 1, 0).day;
    List<DateTime> days = [];
    for (int i = start; i < start + 7 && i <= last; i++) {
      days.add(DateTime(month.year, month.month, i));
    }
    return days;
  }
}

class ReportScreen extends StatelessWidget {
  const ReportScreen({super.key});
  @override
  Widget build(BuildContext context) {
    final state = AppStateProvider.of(context);
    final month = DateTime.now();
    return Scaffold(
      appBar: AppBar(title: const Text('Итоги (Деньги и Часы)')),
      body: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: state.baristas.length,
        itemBuilder: (context, i) {
          String b = state.baristas[i];
          double h = state.getHoursForMonth(b, month);
          double s = state.getSalaryForMonth(b, month);
          return Card(
            child: ListTile(
              title: Text(b, style: const TextStyle(fontWeight: FontWeight.bold)),
              subtitle: Text('Отработано: ${h.toStringAsFixed(0)} ч.'),
              trailing: Text('${s.toStringAsFixed(0)} ₽', style: const TextStyle(fontSize: 20, color: Colors.green, fontWeight: FontWeight.bold)),
            ),
          );
        },
      ),
    );
  }
}

class PreferencesScreen extends StatefulWidget {
  const PreferencesScreen({super.key});
  @override
  State<PreferencesScreen> createState() => _PreferencesScreenState();
}

class _PreferencesScreenState extends State<PreferencesScreen> {
  String? _barista;
  @override
  Widget build(BuildContext context) {
    final state = AppStateProvider.of(context);
    _barista ??= state.baristas.first;
    final days = _getDaysForPrefs(DateTime.now());
    return Scaffold(
      appBar: AppBar(title: const Text('Мои пожелания')),
      body: Column(
        children: [
          DropdownButton<String>(
            value: _barista,
            items: state.baristas.map((b) => DropdownMenuItem(value: b, child: Text(b))).toList(),
            onChanged: (v) => setState(() => _barista = v),
          ),
          Expanded(
            child: ListView.builder(
              itemCount: days.length,
              itemBuilder: (context, i) {
                final d = days[i];
                PrefType p = state.getPref(_barista!, d);
                return ListTile(
                  title: Text(DateFormat('EEEE, dd.MM').format(d)),
                  trailing: _prefIcon(p),
                  onTap: () => state.togglePref(_barista!, d),
                );
              },
            ),
          )
        ],
      ),
    );
  }

  Widget _prefIcon(PrefType p) {
    if (p == PrefType.ready) return const Icon(Icons.check_circle, color: Colors.green);
    if (p == PrefType.notReady) return const Icon(Icons.cancel, color: Colors.red);
    return const Icon(Icons.radio_button_unchecked, color: Colors.grey);
  }

  List<DateTime> _getDaysForPrefs(DateTime m) {
    return List.generate(14, (i) => DateTime.now().add(Duration(days: i)));
  }
}
