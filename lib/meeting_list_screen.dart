import 'package:flutter/material.dart';
import 'package:annapurna_securemeet_flutter/services/api_service.dart';

class MeetingListScreen extends StatefulWidget {
  const MeetingListScreen({super.key});

  @override
  _MeetingListScreenState createState() => _MeetingListScreenState();
}

class _MeetingListScreenState extends State<MeetingListScreen> {
  List<dynamic> _meetings = [];
  String? _selectedUserId;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final args = ModalRoute.of(context)?.settings.arguments as String?;
    _selectedUserId = args ?? 'User1';
    _fetchMeetings();
  }

  Future<void> _fetchMeetings() async {
    try {
      final meetings = await ApiService.getMeetings();
      setState(() {
        _meetings = meetings;
      });
    } catch (e) {
      print('Error fetching meetings: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Meeting List')),
      body: ListView.builder(
        itemCount: _meetings.length,
        itemBuilder: (context, index) {
          final meeting = _meetings[index];
          return ListTile(
            title: Text(meeting['title']),
            subtitle: Text('Code: ${meeting['code']}'),
            onTap: () {
              Navigator.pushNamed(
                context,
                '/meeting_details',
                arguments: _selectedUserId,
              );
            },
          );
        },
      ),
    );
  }
}