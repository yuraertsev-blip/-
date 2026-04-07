import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/enums.dart';
import '../services/firestore_service.dart';

class AppState extends ChangeNotifier {
  final service = FirestoreService();

  final List<String> baristas = ['Юрий', 'Валерия', 'Дарьяна', 'Анастасия'];

  Map<String, Map<String, ShiftType>> shifts = {};
  Map<String, Map<String, PrefType>> prefs = {};
  List<String> logs = [];

  AppState() {
    _init();
  }

  void _init() {
    service.shiftsStream().listen(_handleShifts);
    service.prefsStream().listen(_handlePrefs);
    service.logsStream().listen(_handleLogs);
  }

  void _handleShifts(snap) {
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
  }

  void _handlePrefs(snap) {
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
  }

  void _handleLogs(snap) {
    logs = snap.docs.map((e) => e['text'] as String).toList();
    notifyListeners();
  }

  String key(DateTime d) => DateFormat('yyyy-MM-dd').format(d);

  // 🚀 БЕЗ ЛАГОВ
  Future<void> toggleShift(String barista, DateTime date) async {
    final k = key(date);
    final current = shifts[barista]?[k] ?? ShiftType.none;

    final next = ShiftType.values[(current.index + 1) % ShiftType.values.length];

    shifts.putIfAbsent(barista, () => {});
    shifts[barista]![k] = next;

    notifyListeners(); // мгновенный UI

    await service.updateShift(barista, k, next.index);
  }

  Future<void> togglePref(String barista, DateTime date) async {
    final k = key(date);
    final current = prefs[barista]?[k] ?? PrefType.none;

    final next = PrefType.values[(current.index + 1) % PrefType.values.length];

    prefs.putIfAbsent(barista, () => {});
    prefs[barista]![k] = next;

    notifyListeners();

    await service.updatePref(barista, k, next.index);
  }

  ShiftType getShift(String b, DateTime d) =>
      shifts[b]?[key(d)] ?? ShiftType.none;

  PrefType getPref(String b, DateTime d) =>
      prefs[b]?[key(d)] ?? PrefType.none;
}
