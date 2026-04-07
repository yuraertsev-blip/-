import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

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
  
  // Добавлены ставки для подсчета зарплаты
  final Map<String, double> rates = {
    'Юрий': 350.0,
    'Валерия': 300.0,
    'Дарьяна': 280.0,
    'Анастасия': 280.0,
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
    _db.collection('logs').orderBy('time', descending: true).limit(50).snapshots().listen((snap) {
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

    // Оптимистичное обновление UI
    if (!shifts.containsKey(barista)) shifts[barista] = {};
    shifts[barista]![key] = next;
    notifyListeners();

    // ИСПРАВЛЕНИЕ: Используем точечную нотацию для сохранения вложенных полей
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

    // ИСПРАВЛЕНИЕ: Точечная нотация для пожеланий
    await _db.collection('settings').doc('prefs').set({
      '$barista.$key': next.index
    }, SetOptions(merge: true));
  }

  ShiftType getShift(String barista, DateTime date) {
    return shifts[barista]?[_dateKey(date)] ?? ShiftType.none;
  }

  PrefType getPref(String barista, DateTime date) {
    return prefs[barista]?[_dateKey(date)] ?? PrefType.none;
  }

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

  // ДОБАВЛЕНО: Расчет зарплаты
  double getSalaryForMonth(String barista, DateTime month) {
    double hours = getHoursForMonth(barista, month);
    double rate = rates[barista] ?? 250.0;
    return hours * rate;
