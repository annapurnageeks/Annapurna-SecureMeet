import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:socket_io_client/socket_io_client.dart' as io;

class ApiService {
  static const String baseUrl = 'http://127.0.0.1:3001';
  static io.Socket? socket;

  static void initSocket() {
    socket = io.io(baseUrl, <String, dynamic>{
      'transports': ['websocket'],
    });
    socket!.onConnect((_) {
      print('Socket.IO connected successfully');
    });
    socket!.onConnectError((error) {
      print('Socket.IO connection error: $error');
    });
    socket!.onDisconnect((_) {
      print('Socket.IO disconnected');
    });
  }

  static void onMessage(Function(Map<String, dynamic>) callback) {
    socket!.on('message', (data) => callback(data));
  }

  static void onFile(Function(Map<String, dynamic>) callback) {
    socket!.on('file', (data) => callback(data));
  }

  static void onNote(Function(Map<String, dynamic>) callback) {
    socket!.on('note', (data) => callback(data));
  }

  static void sendMessage(String userId, String text) {
    socket!.emit('message', {
      'userId': userId,
      'text': text,
    });
  }

  static void saveNote(String userId, String meetingCode, String content) {
    socket!.emit('note', {
      'userId': userId,
      'meetingCode': meetingCode,
      'content': content,
    });
  }

  static Future<List<dynamic>> getMessages() async {
    final response = await http.get(Uri.parse('$baseUrl/messages'));
    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    }
    throw Exception('Failed to fetch messages');
  }

  static Future<Map<String, dynamic>> uploadFile(String userId, String filePath, List<int> fileBytes) async {
    var request = http.MultipartRequest('POST', Uri.parse('$baseUrl/upload'));
    request.fields['userId'] = userId;
    request.files.add(http.MultipartFile.fromBytes(
      'file',
      fileBytes,
      filename: filePath.split('/').last,
    ));

    final response = await request.send();
    if (response.statusCode == 200) {
      return jsonDecode(await response.stream.bytesToString());
    }
    throw Exception('Failed to upload file');
  }

  static Future<List<dynamic>> getFiles() async {
    final response = await http.get(Uri.parse('$baseUrl/files'));
    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    }
    throw Exception('Failed to fetch files');
  }

  static Future<Map<String, dynamic>> createMeeting(String code, String title, String createdBy) async {
    final response = await http.post(
      Uri.parse('$baseUrl/meetings'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'code': code,
        'title': title,
        'createdBy': createdBy,
      }),
    );
    if (response.statusCode == 201) {
      return jsonDecode(response.body);
    }
    throw Exception('Failed to create meeting');
  }

  static Future<List<dynamic>> getMeetings() async {
    final response = await http.get(Uri.parse('$baseUrl/meetings'));
    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    }
    throw Exception('Failed to fetch meetings');
  }

  static Future<List<dynamic>> getNotes(String meetingCode) async {
    final response = await http.get(Uri.parse('$baseUrl/notes/$meetingCode'));
    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    }
    throw Exception('Failed to fetch notes');
  }

  static Future<String> downloadFile(String fileName) async {
    final response = await http.get(Uri.parse('$baseUrl/download/$fileName'));
    if (response.statusCode == 200) {
      return '$baseUrl/uploads/$fileName'; // Return URL for web download
    }
    throw Exception('Failed to download file');
  }
}