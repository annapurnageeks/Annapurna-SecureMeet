import 'package:flutter/material.dart';
import 'package:annapurna_securemeet_flutter/login_screen.dart';
import 'package:annapurna_securemeet_flutter/dashboard_screen.dart';
import 'package:annapurna_securemeet_flutter/meeting_list_screen.dart';
import 'package:annapurna_securemeet_flutter/meeting_details_screen.dart';
import 'package:annapurna_securemeet_flutter/services/api_service.dart';

void main() {
  ApiService.initSocket();
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Annapurna SecureMeet',
      theme: ThemeData(primarySwatch: Colors.blue),
      home: const LoginScreen(),
      routes: {
        '/dashboard': (context) => const DashboardScreen(),
        '/meetings': (context) => const MeetingListScreen(),
        '/meeting_details': (context) => const MeetingDetailsScreen(),
      },
    );
  }
}