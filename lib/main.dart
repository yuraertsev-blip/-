import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

const firebaseOptions = FirebaseOptions(
  apiKey: "AIzaSyC0rFOiAx5LEpT-6s9Bc8sxNtc59RfsOcM",
  authDomain: "u-coffee.firebaseapp.com",
  projectId: "u-coffee",
  storageBucket: "u-coffee.firebasestorage.app",
  messagingSenderId: "971000964907",
  appId: "1:971000964907:web:b1e9271ca53fbfff6ac76e",
);

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting('ru_RU', null);
  await Firebase.initializeApp(options: firebaseOptions);
  runApp(const App());
}

// ================= ENUMS =================

enum ShiftType { none, full, morning, evening }
enum PrefType { none, ready, readyAfter15, readyBefore15, notReady }

// ================= STATE =================

class AppState extends ChangeNotifier {
  final db = FirebaseFirestore.instance;

  final baristas = ['Юрий', 'Валерия', 'Дарьяна', 'Анастасия'];

  Map<String, Map<String, ShiftType>> shifts = {};
  Map<String, Map<String, PrefType>> prefs = {};

  AppState() {
    _init();
  }

  void _init() {
    db.collection('settings').doc('shifts').snapshots().listen((snap) {
      if (!snap.exists) return;

      final data = snap.data() as Map<String, dynamic>;
      final newData = <String, Map<String, ShiftType>>{};

      data.forEach((barista, dates) {
        newData[barista] = {};
        (dates as Map<String, dynamic>).forEach((date, value) {
          newData[barista]![date] = ShiftType.values[value];
        });
      });

      shifts = newData;
      notifyListeners();
    });

    db.collection('settings').doc('prefs').snapshots().listen((snap) {
      if (!snap.exists) return;

      final data = snap.data() as Map<String, dynamic>;
      final newData = <String, Map<String, PrefType>>{};

      data.forEach((barista, dates) {
        newData[barista] = {};
        (dates as Map<String, dynamic>).forEach((date, value) {
          newData[barista]![date] = PrefType.values[value];
        });
      });

      prefs = newData;
      notifyListeners();
    });
  }

  String key(DateTime d) => DateFormat('yyyy-MM-dd').format(d);

  Future<void> toggleShift(String barista, DateTime date) async {
    final k = key(date);
    final current = shifts[barista]?[k] ?? ShiftType.none;
    final next = ShiftType.values[(current.index + 1) % ShiftType.values.length];

    shifts.putIfAbsent(barista, () => {});
    shifts[barista]![k] = next;

    notifyListeners();

    await db.collection('settings').doc('shifts').set({
      '$barista.$k': next.index
    }, SetOptions(merge: true));
  }

  Future<void> togglePref(String barista, DateTime date) async {
    final k = key(date);
    final current = prefs[barista]?[k] ?? PrefType.none;
    final next = PrefType.values[(current.index + 1) % PrefType.values.length];

    prefs.putIfAbsent(barista, () => {});
    prefs[barista]![k] = next;

    notifyListeners();

    await db.collection('settings').doc('prefs').set({
      '$barista.$k': next.index
    }, SetOptions(merge: true));
  }

  ShiftType getShift(String b, DateTime d) =>
      shifts[b]?[key(d)] ?? ShiftType.none;

  PrefType getPref(String b, DateTime d) =>
      prefs[b]?[key(d)] ?? PrefType.none;
}

// ================= APP =================

class App extends StatelessWidget {
  const App({super.key});

  @override
  Widget build(BuildContext context) {
    return AppProvider(
      state: AppState(),
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        home: const ScheduleScreen(),
      ),
    );
  }
}

class AppProvider extends InheritedNotifier<AppState> {
  const AppProvider({super.key, required AppState state, required Widget child})
      : super(notifier: state, child: child);

  static AppState of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<AppProvider>()!.notifier!;
}

// ================= UI =================

class ScheduleScreen extends StatelessWidget {
  const ScheduleScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final state = AppProvider.of(context);
    final today = DateTime.now();

    final days = List.generate(
      DateTime(today.year, today.month + 1, 0).day,
      (i) => DateTime(today.year, today.month, i + 1),
    );

    return Scaffold(
      appBar: AppBar(title: const Text('График')),
      body: ListView(
        children: state.baristas.map((barista) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.all(8),
                child: Text(barista,
                    style: const TextStyle(fontWeight: FontWeight.bold)),
              ),
              Wrap(
                children: days.map((date) {
                  final type = state.getShift(barista, date);

                  Color color;
                  switch (type) {
                    case ShiftType.full:
                      color = Colors.green;
                      break;
                    case ShiftType.morning:
                      color = Colors.yellow;
                      break;
                    case ShiftType.evening:
                      color = Colors.purple;
                      break;
                    default:
                      color = Colors.grey.shade200;
                  }

                  return GestureDetector(
                    onTap: () => state.toggleShift(barista, date),
                    child: Container(
                      width: 40,
                      height: 40,
                      margin: const EdgeInsets.all(2),
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: color,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text('${date.day}',
                          style: const TextStyle(fontSize: 12)),
                    ),
                  );
                }).toList(),
              ),
              const Divider()
            ],
          );
        }).toList(),
      ),
    );
  }
}
