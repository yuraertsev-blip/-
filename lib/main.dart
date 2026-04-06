import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:intl/date_symbol_data_local.dart';
void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting('ru_RU', null);
  runApp(const MockApp());
}
// ==========================================
// Модели и Стейт (Мок Базы Данных)
// ==========================================
enum ShiftType { none, full, morning, evening }
enum PrefType { none, ready, readyAfter15, readyBefore15, notReady }
class AppState extends ChangeNotifier {
  final List<String> baristas = ['Юрий', 'Валерия', 'Дарьяна', 'Анастасия'];
  final Map<String, Map<String, ShiftType>> shifts = {};
  final Map<String, Map<String, PrefType>> prefs = {};
  final List<String> auditLogs = [];
  String _dateKey(DateTime d) => DateFormat('yyyy-MM-dd').format(d);
  void toggleShift(String barista, DateTime date) {
    if (!shifts.containsKey(barista)) shifts[barista] = {};
    String key = _dateKey(date);
    ShiftType current = shifts[barista]![key] ?? ShiftType.none;
    ShiftType next;
    String actionName;
    switch (current) {
      case ShiftType.none:
        next = ShiftType.full;
        actionName = 'Полная смена';
        break;
      case ShiftType.full:
        next = ShiftType.morning;
        actionName = 'Утро';
        break;
      case ShiftType.morning:
        next = ShiftType.evening;
        actionName = 'Вечер';
        break;
      case ShiftType.evening:
        next = ShiftType.none;
        actionName = 'Снята смена';
        break;
    }
    shifts[barista]![key] = next;
    
    final timeStr = DateFormat('HH:mm').format(DateTime.now());
    final dateStr = DateFormat('dd.MM').format(date);
    auditLogs.insert(0, '$timeStr - $barista: $actionName на $dateStr');
    
    notifyListeners();
  }
  void togglePref(String barista, DateTime date) {
    if (!prefs.containsKey(barista)) prefs[barista] = {};
    String key = _dateKey(date);
    PrefType current = prefs[barista]![key] ?? PrefType.none;
    PrefType next;
    switch (current) {
      case PrefType.none:
        next = PrefType.ready;
        break;
      case PrefType.ready:
        next = PrefType.readyAfter15;
        break;
      case PrefType.readyAfter15:
        next = PrefType.readyBefore15;
        break;
      case PrefType.readyBefore15:
        next = PrefType.notReady;
        break;
      case PrefType.notReady:
        next = PrefType.none;
        break;
    }
    prefs[barista]![key] = next;
    notifyListeners();
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
  int getFullShiftsCount(String barista, DateTime month) {
    if (!shifts.containsKey(barista)) return 0;
    int count = 0;
    shifts[barista]!.forEach((dateStr, type) {
      DateTime d = DateTime.parse(dateStr);
      if (d.month == month.month && d.year == month.year && type == ShiftType.full) {
        count++;
      }
    });
    return count;
  }
}
// ==========================================
// Приложение и Навигация
// ==========================================
class MockApp extends StatelessWidget {
  const MockApp({super.key});
  @override
  Widget build(BuildContext context) {
    return AppStateProvider(
      state: AppState(),
      child: MaterialApp(
        title: 'Ю Кофе (Мобайл)',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          useMaterial3: true,
          colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF4E342E)),
          scaffoldBackgroundColor: const Color(0xFFFFF8E1),
          appBarTheme: const AppBarTheme(
            centerTitle: true, // Центрируем как в iOS
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
  const AppStateProvider({
    Key? key,
    required AppState state,
    required Widget child,
  }) : super(key: key, notifier: state, child: child);
  static AppState of(BuildContext context) {
    return context.dependOnInheritedWidgetOfExactType<AppStateProvider>()!.notifier!;
  }
}
class MainScreen extends StatefulWidget {
  const MainScreen({super.key});
  @override
  State<MainScreen> createState() => _MainScreenState();
}
class _MainScreenState extends State<MainScreen> {
  int _currentIndex = 0;
  final screens = const [
    ScheduleScreen(),
    ReportScreen(),
    PreferencesScreen(),
  ];
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(child: screens[_currentIndex]), // Защита от челок (iOS Dynamic Island и вырезов Android)
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentIndex,
        onTap: (i) => setState(() => _currentIndex = i),
        selectedItemColor: const Color(0xFF4E342E),
        unselectedItemColor: Colors.grey,
        backgroundColor: const Color(0xFFFFF8E1),
        type: BottomNavigationBarType.fixed, // Предотвращает дергание на узких экранах
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
// Утилиты для Календаря
// ==========================================
class CalendarUtils {
  static List<DateTime> getDaysInWeek(DateTime month, int weekIndex) {
    int startDay = weekIndex * 7 + 1;
    int endDay = startDay + 6;
    
    int lastDayOfMonth = DateTime(month.year, month.month + 1, 0).day;
    if (endDay > lastDayOfMonth) endDay = lastDayOfMonth;
    if (startDay > lastDayOfMonth) return []; 
    List<DateTime> days = [];
    for (int i = startDay; i <= endDay; i++) {
      days.add(DateTime(month.year, month.month, i));
    }
    return days;
  }
}
// ==========================================
// 1. Экран Графика (Оптимизированный под мобайл)
// ==========================================
class ScheduleScreen extends StatefulWidget {
  const ScheduleScreen({super.key});
  @override
  State<ScheduleScreen> createState() => _ScheduleScreenState();
}
class _ScheduleScreenState extends State<ScheduleScreen> {
  DateTime _selectedMonth = DateTime(DateTime.now().year, DateTime.now().month);
  int _selectedWeek = 0;
  void _nextMonth() => setState(() { _selectedMonth = DateTime(_selectedMonth.year, _selectedMonth.month + 1); _selectedWeek = 0; });
  void _prevMonth() => setState(() { _selectedMonth = DateTime(_selectedMonth.year, _selectedMonth.month - 1); _selectedWeek = 0; });
  void _setWeek(int index) => setState(() => _selectedWeek = index);
  @override
  Widget build(BuildContext context) {
    final state = AppStateProvider.of(context);
    final daysToRender = CalendarUtils.getDaysInWeek(_selectedMonth, _selectedWeek);
    final monthName = DateFormat('LLLL yyyy', 'ru_RU').format(_selectedMonth);
    return Column(
      children: [
        // Шапка и навигация с адаптивным Wrap
        Container(
          color: Colors.brown.shade50,
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
          child: Column(
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  IconButton(icon: const Icon(Icons.chevron_left), onPressed: _prevMonth, padding: EdgeInsets.zero, constraints: const BoxConstraints()),
                  Text(monthName.toUpperCase(), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                  IconButton(icon: const Icon(Icons.chevron_right), onPressed: _nextMonth, padding: EdgeInsets.zero, constraints: const BoxConstraints()),
                ],
              ),
              const SizedBox(height: 8),
              // Wrap для того чтобы на узких телефонах чипсы переносились на вторую строку
              Wrap(
                alignment: WrapAlignment.center,
                spacing: 8,
                runSpacing: 4,
                children: List.generate(5, (index) {
                  if (CalendarUtils.getDaysInWeek(_selectedMonth, index).isEmpty) return const SizedBox();
                  bool isSelected = _selectedWeek == index;
                  return ChoiceChip(
                    label: Text('Н. ${index + 1}', style: const TextStyle(fontSize: 12)),
                    selected: isSelected,
                    onSelected: (_) => _setWeek(index),
                    selectedColor: Colors.brown.shade200,
                    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 0),
                  );
                }),
              )
            ],
          ),
        ),
        
        // Легенда
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 4),
          child: Wrap(
            alignment: WrapAlignment.center,
            spacing: 12,
            runSpacing: 4,
            children: [
              _legendDot(Colors.green.shade400, 'Полная (10ч)'), 
              _legendDot(Colors.yellow.shade400, 'Утро (5ч)'), 
              _legendDot(Colors.purple.shade300, 'Вечер (5ч)'),
            ],
          ),
        ),
        // Сетка (Занимает 60% экрана по вертикали)
        Expanded(
          flex: 5,
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: SingleChildScrollView(
              child: Table(
                defaultColumnWidth: const FixedColumnWidth(50.0), // Чуть ужали для узких экранов
                columnWidths: const { 0: FixedColumnWidth(85.0) },
                border: TableBorder.all(color: Colors.brown.shade200, borderRadius: BorderRadius.circular(4)),
                children: [
                  TableRow(
                    decoration: BoxDecoration(color: Colors.brown.shade100),
                    children: [
                      const Center(child: Padding(padding: EdgeInsets.symmetric(vertical: 12.0), child: Text('Бариста', style: TextStyle(fontSize: 12)))),
                      ...daysToRender.map((d) => Center(child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 6.0),
                        child: Text(DateFormat('EE\ndd', 'ru_RU').format(d), textAlign: TextAlign.center, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                      )))
                    ],
                  ),
                  ...state.baristas.map((barista) {
                    return TableRow(
                      children: [
                        // InkWell для красивого "нативного" эффекта нажатия
                        InkWell(
                          onTap: () => _showEmployeeStats(context, state, barista),
                          child: Container(
                            height: 55,
                            alignment: Alignment.centerLeft,
                            padding: const EdgeInsets.only(left: 6.0),
                            child: Text(barista, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, decoration: TextDecoration.underline, color: Color(0xFF4E342E))),
                          ),
                        ),
                        ...daysToRender.map((date) {
                          ShiftType type = state.getShift(barista, date);
                          Color cellColor;
                          switch (type) {
                            case ShiftType.full: cellColor = Colors.green.shade400; break;
                            case ShiftType.morning: cellColor = Colors.yellow.shade400; break;
                            case ShiftType.evening: cellColor = Colors.purple.shade300; break;
                            case ShiftType.none: cellColor = Colors.transparent; break;
                          }
                          return InkWell(
                            onTap: () => state.toggleShift(barista, date),
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 200),
                              height: 55,
                              margin: const EdgeInsets.all(2),
                              decoration: BoxDecoration(
                                color: cellColor,
                                borderRadius: BorderRadius.circular(6), // Более скругленные углы (iOS style)
                              ),
                            ),
                          );
                        })
                      ],
                    );
                  })
                ],
              ),
            ),
          ),
        ),
        // Блок истории (Занимает 25% экрана по вертикали)
        Expanded(
          flex: 2,
          child: Container(
            margin: const EdgeInsets.only(top: 8),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
              boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10, offset: const Offset(0, -5))],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(
                  decoration: const BoxDecoration(
                    color: Color(0xFF4E342E),
                    borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
                  ),
                  padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
                  child: const Text('История изменений', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
                ),
                Expanded(
                  child: state.auditLogs.isEmpty 
                    ? const Center(child: Text('Изменений пока нет', style: TextStyle(color: Colors.grey, fontSize: 12)))
                    : ListView.separated(
                        itemCount: state.auditLogs.length,
                        separatorBuilder: (_, __) => Divider(height: 1, color: Colors.grey.shade200),
                        itemBuilder: (context, i) {
                          return Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
                            child: Text(state.auditLogs[i], style: const TextStyle(fontSize: 11, fontFamily: 'monospace')),
                          );
                        },
                      ),
                )
              ],
            ),
          ),
        )
      ],
    );
  }
  Widget _legendDot(Color color, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(width: 12, height: 12, decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(4))),
        const SizedBox(width: 4),
        Text(label, style: const TextStyle(fontSize: 10)),
      ],
    );
  }
  void _showEmployeeStats(BuildContext context, AppState state, String barista) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      isScrollControlled: true, // Позволяет шторке подстраиваться
      builder: (ctx) {
        return SafeArea(
          child: StatefulBuilder(
            builder: (BuildContext context, StateSetter setModalState) {
              return Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2)), margin: const EdgeInsets.only(bottom: 20)),
                    Text('Профиль: $barista', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 16),
                    
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        IconButton(icon: const Icon(Icons.chevron_left), onPressed: () => setModalState(() => _selectedMonth = DateTime(_selectedMonth.year, _selectedMonth.month - 1))),
                        Text(DateFormat('LLLL yyyy', 'ru_RU').format(_selectedMonth).toUpperCase(), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                        IconButton(icon: const Icon(Icons.chevron_right), onPressed: () => setModalState(() => _selectedMonth = DateTime(_selectedMonth.year, _selectedMonth.month + 1))),
                      ],
                    ),
                    
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(child: _statCard('Полных\nсмен', state.getFullShiftsCount(barista, _selectedMonth).toString(), Colors.green.shade100)),
                        const SizedBox(width: 16),
                        Expanded(child: _statCard('Всего\nчасов', state.getHoursForMonth(barista, _selectedMonth).toStringAsFixed(0), Colors.brown.shade100)),
                      ],
                    ),
                  ],
                ),
              );
            }
          ),
        );
      }
    );
  }
  Widget _statCard(String label, String value, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
      decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(16)),
      child: Column(
        children: [
          Text(value, style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w900)),
          const SizedBox(height: 4),
          Text(label, textAlign: TextAlign.center, style: const TextStyle(fontSize: 12, height: 1.2)),
        ],
      ),
    );
  }
}
// ==========================================
// 2. Экран Отчетов (Оптимизирован)
// ==========================================
class ReportScreen extends StatefulWidget {
  const ReportScreen({super.key});
  @override
  State<ReportScreen> createState() => _ReportScreenState();
}
class _ReportScreenState extends State<ReportScreen> {
  DateTime _reportMonth = DateTime(DateTime.now().year, DateTime.now().month);
  @override
  Widget build(BuildContext context) {
    final state = AppStateProvider.of(context);
    final monthName = DateFormat('LLLL yyyy', 'ru_RU').format(_reportMonth);
    return Scaffold(
      appBar: AppBar(title: const Text('Итоги за месяц')),
      body: Column(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(vertical: 8),
            decoration: BoxDecoration(
              color: Colors.brown.shade50,
              border: Border(bottom: BorderSide(color: Colors.brown.shade200)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                IconButton(icon: const Icon(Icons.chevron_left), onPressed: () => setState(()=> _reportMonth = DateTime(_reportMonth.year, _reportMonth.month-1))),
                Text(monthName.toUpperCase(), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                IconButton(icon: const Icon(Icons.chevron_right), onPressed: () => setState(()=> _reportMonth = DateTime(_reportMonth.year, _reportMonth.month+1))),
              ],
            ),
          ),
          
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.all(12),
              itemCount: state.baristas.length,
              itemBuilder: (context, i) {
                String barista = state.baristas[i];
                double hours = state.getHoursForMonth(barista, _reportMonth);
                
                return Card(
                  margin: const EdgeInsets.only(bottom: 12),
                  elevation: 2,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8.0),
                    child: ListTile(
                      leading: CircleAvatar(backgroundColor: Colors.brown.shade200, child: Text(barista[0], style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold))),
                      title: Text(barista, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                      trailing: Text('${hours.toStringAsFixed(0)} ч.', style: const TextStyle(fontSize: 22, color: Color(0xFF4E342E), fontWeight: FontWeight.w900)),
                    ),
                  ),
                );
              },
            ),
          )
        ],
      ),
    );
  }
}
// ==========================================
// 3. Экран Пожеланий (Оптимизирован)
// ==========================================
class PreferencesScreen extends StatefulWidget {
  const PreferencesScreen({super.key});
  @override
  State<PreferencesScreen> createState() => _PreferencesScreenState();
}
class _PreferencesScreenState extends State<PreferencesScreen> {
  String? _selectedBarista;
  DateTime _selectedMonth = DateTime(DateTime.now().year, DateTime.now().month);
  int _selectedWeek = 0;
  @override
  Widget build(BuildContext context) {
    final state = AppStateProvider.of(context);
    _selectedBarista ??= state.baristas.first;
    final daysToRender = CalendarUtils.getDaysInWeek(_selectedMonth, _selectedWeek);
    final monthName = DateFormat('LLLL yyyy', 'ru_RU').format(_selectedMonth);
    return Scaffold(
      appBar: AppBar(title: const Text('Мои пожелания')),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            color: Colors.white,
            child: DropdownButtonFormField<String>(
              decoration: InputDecoration(
                labelText: 'Ваш профиль', 
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8)
              ),
              value: _selectedBarista,
              items: state.baristas.map((b) => DropdownMenuItem(value: b, child: Text(b, style: const TextStyle(fontWeight: FontWeight.bold)))).toList(),
              onChanged: (val) => setState(() => _selectedBarista = val),
            ),
          ),
          
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            color: Colors.brown.shade50,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                IconButton(icon: const Icon(Icons.chevron_left), onPressed: () => setState(()=> _selectedMonth = DateTime(_selectedMonth.year, _selectedMonth.month - 1))),
                Text(monthName.toUpperCase(), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                IconButton(icon: const Icon(Icons.chevron_right), onPressed: () => setState(()=> _selectedMonth = DateTime(_selectedMonth.year, _selectedMonth.month + 1))),
              ],
            ),
          ),
          
          Container(
            padding: const EdgeInsets.only(bottom: 8),
            color: Colors.brown.shade50,
            child: Wrap(
              alignment: WrapAlignment.center,
              spacing: 8,
              runSpacing: 4,
              children: List.generate(5, (index) {
                if (CalendarUtils.getDaysInWeek(_selectedMonth, index).isEmpty) return const SizedBox();
                return ChoiceChip(
                  label: Text('Н. ${index + 1}', style: const TextStyle(fontSize: 12)),
                  selected: _selectedWeek == index,
                  selectedColor: Colors.brown.shade200,
                  onSelected: (_) => setState(() => _selectedWeek = index),
                );
              }),
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
             alignment: WrapAlignment.center,
             spacing: 12,
             runSpacing: 8,
             children: [
                _prefLegend(Colors.green.shade200, "Весь день"),
                _prefLegend(Colors.orange.shade200, "С 15:00"),
                _prefLegend(Colors.yellow.shade200, "До 15:00"),
                _prefLegend(Colors.red.shade200, "Не могу"),
             ],
          ),
          
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              itemCount: daysToRender.length,
              itemBuilder: (context, i) {
                final date = daysToRender[i];
                PrefType type = state.getPref(_selectedBarista!, date);
                
                Color bg;
                String statusText;
                switch (type) {
                  case PrefType.ready: bg = Colors.green.shade200; statusText = "Готов работать"; break;
                  case PrefType.readyAfter15: bg = Colors.orange.shade200; statusText = "Готов с 15:00"; break;
                  case PrefType.readyBefore15: bg = Colors.yellow.shade200; statusText = "Готов до 15:00"; break;
                  case PrefType.notReady: bg = Colors.red.shade200; statusText = "Не могу"; break;
                  case PrefType.none: bg = Colors.white; statusText = "Не выбрано"; break;
                }
                return Card(
                  margin: const EdgeInsets.only(bottom: 8),
                  color: bg,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                    side: type == PrefType.none ? BorderSide(color: Colors.grey.shade300) : BorderSide.none,
                  ),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(12),
                    onTap: () => state.togglePref(_selectedBarista!, date),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8.0),
                      child: ListTile(
                        title: Text(DateFormat('EEEE, dd MMMM', 'ru_RU').format(date), style: const TextStyle(fontSize: 14)),
                        trailing: Text(statusText, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                      ),
                    ),
                  ),
                );
              },
            ),
          )
        ],
      ),
    );
  }
  Widget _prefLegend(Color c, String text) {
     return Row(mainAxisSize: MainAxisSize.min, children: [
        Container(width: 14, height: 14, decoration: BoxDecoration(color: c, borderRadius: BorderRadius.circular(4))),
        const SizedBox(width: 6), Text(text, style: const TextStyle(fontSize: 11))
     ]);
  }
}
