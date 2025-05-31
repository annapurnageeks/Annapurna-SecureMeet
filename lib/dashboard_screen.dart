import 'package:flutter/material.dart';
import 'package:annapurna_securemeet_flutter/services/api_service.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  _DashboardScreenState createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  String _selectedUserId = 'User1';
  final List<String> _userIds = ['User1', 'User2', 'User3'];

  @override
  void initState() {
    super.initState();
    _createDefaultMeeting();
  }

  Future<void> _createDefaultMeeting() async {
    try {
      await ApiService.createMeeting('CONSTANT', 'Constant Meeting', _selectedUserId);
    } catch (e) {
      print('Meeting already exists: $e');
    }
  }

  void _logout() {
    // Placeholder for Firebase logout
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Firebase logout will be implemented later')),
    );
    Navigator.pushReplacementNamed(context, '/');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Dashboard'),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: _logout,
          ),
        ],
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              'Welcome to Annapurna SecureMeet, $_selectedUserId!',
              style: const TextStyle(fontSize: 24),
            ),
            const SizedBox(height: 20),
            DropdownButton<String>(
              value: _selectedUserId,
              items: _userIds.map((String value) {
                return DropdownMenuItem<String>(
                  value: value,
                  child: Text(value),
                );
              }).toList(),
              onChanged: (String? newValue) {
                setState(() {
                  _selectedUserId = newValue!;
                });
              },
            ),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: () {
                Navigator.pushNamed(
                  context,
                  '/meetings',
                  arguments: _selectedUserId,
                );
              },
              child: const Text('View Meetings'),
            ),
          ],
        ),
      ),
    );
  }
}