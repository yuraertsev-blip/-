import 'package:flutter/material.dart';
import '../screens/schedule_screen.dart';

class App extends StatelessWidget {
  const App({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Ю Кофе',
      debugShowCheckedModeBanner: false,
      home: const ScheduleScreen(),
    );
  }
}
