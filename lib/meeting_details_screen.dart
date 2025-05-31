import 'package:flutter/material.dart';
import 'package:annapurna_securemeet_flutter/services/api_service.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:url_launcher/url_launcher.dart';

class MeetingDetailsScreen extends StatefulWidget {
  const MeetingDetailsScreen({super.key});

  @override
  _MeetingDetailsScreenState createState() => _MeetingDetailsScreenState();
}

class _MeetingDetailsScreenState extends State<MeetingDetailsScreen> {
  final TextEditingController _messageController = TextEditingController();
  final TextEditingController _noteController = TextEditingController();
  List<dynamic> _messages = [];
  List<dynamic> _files = [];
  List<dynamic> _notes = [];
  String? _selectedUserId;
  final String _meetingCode = 'CONSTANT';
  Map<String, RTCPeerConnection> _peerConnections = {}; // One per remote user
  RTCVideoRenderer _localRenderer = RTCVideoRenderer();
  Map<String, RTCVideoRenderer> _remoteRenderers = {};
  Map<String, String> _participants = {}; // Map socketId to userId
  bool _isJoined = false;
  bool _isMicMuted = false;
  bool _isCameraOff = false;
  MediaStream? _localStream;

  @override
  void initState() {
    super.initState();
    _initRenderers();
    ApiService.initSocket();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final args = ModalRoute.of(context)?.settings.arguments as String?;
    _selectedUserId = args ?? 'User1';
    _fetchInitialData();
    _setupWebSocketListeners();
    _joinMeeting();
  }

  Future<void> _initRenderers() async {
    await _localRenderer.initialize();
    setState(() {});
  }

  Future<RTCPeerConnection> _createPeerConnection(String remoteSocketId) async {
    final configuration = {
      'iceServers': [
        {'urls': 'stun:stun.l.google.com:19302'},
        // Public TURN server for testing (replace with your own for production)
        {
          'urls': 'turn:turn.example.com:3478',
          'username': 'testuser',
          'credential': 'testpassword',
        },
      ],
    };

    final peerConnection = await createPeerConnection(configuration);

    peerConnection.onIceCandidate = (RTCIceCandidate? candidate) {
      if (candidate != null) {
        ApiService.socket!.emit('ice-candidate', {
          'candidate': candidate.toMap(),
          'toSocketId': remoteSocketId,
        });
      }
    };

    peerConnection.onTrack = (RTCTrackEvent event) {
      if (event.track.kind == 'video' && event.receiver?.track != null) {
        final trackId = event.receiver!.track!.id ?? 'remote-${DateTime.now().millisecondsSinceEpoch}';
        setState(() {
          _remoteRenderers[trackId] = RTCVideoRenderer();
          _initRemoteRenderer(event.receiver!.track!, trackId);
        });
      }
    };

    peerConnection.onConnectionState = (RTCPeerConnectionState state) {
      print('Connection state for $remoteSocketId: $state');
      if (state == RTCPeerConnectionState.RTCPeerConnectionStateDisconnected) {
        setState(() {
          _remoteRenderers.removeWhere((key, value) => true);
        });
      }
    };

    return peerConnection;
  }

  Future<void> _initRemoteRenderer(MediaStreamTrack track, String trackId) async {
    final renderer = _remoteRenderers[trackId]!;
    await renderer.initialize();
    final stream = await createLocalMediaStream(trackId);
    stream.addTrack(track);
    renderer.srcObject = stream;
    setState(() {});
  }

  Future<void> _joinMeeting() async {
    try {
      final mediaConstraints = {
        'audio': true,
        'video': {
          'facingMode': 'user',
        },
      };
      _localStream = await navigator.mediaDevices.getUserMedia(mediaConstraints);
      _localRenderer.srcObject = _localStream;

      ApiService.socket!.emit('join-meeting', {
        'userId': _selectedUserId,
        'meetingCode': _meetingCode,
      });

      setState(() {
        _isJoined = true;
      });
    } catch (e) {
      print('Error joining meeting: $e');
    }
  }

  String? _getOpponentSocketId() {
    final socket = ApiService.socket;
    if (socket == null) return null;
    final otherParticipants = _participants.keys.where((socketId) => socketId != socket.id).toList();
    return otherParticipants.isNotEmpty ? otherParticipants.first : null;
  }

  Future<void> _fetchInitialData() async {
    try {
      final messages = await ApiService.getMessages();
      final files = await ApiService.getFiles();
      final notes = await ApiService.getNotes(_meetingCode);
      setState(() {
        _messages = messages;
        _files = files;
        _notes = notes;
      });
    } catch (e) {
      print('Error fetching initial data: $e');
    }
  }

  void _setupWebSocketListeners() {
    ApiService.onMessage((message) {
      setState(() {
        _messages.add(message);
      });
    });

    ApiService.onFile((file) {
      setState(() {
        _files.add(file);
      });
    });

    ApiService.onNote((note) {
      setState(() {
        _notes.add(note);
      });
    });

    ApiService.socket!.on('offer', (data) {
      _handleOffer(data['sdp'], data['fromSocketId']);
    });

    ApiService.socket!.on('answer', (data) {
      _handleAnswer(data['sdp'], data['fromSocketId']);
    });

    ApiService.socket!.on('ice-candidate', (data) {
      _handleIceCandidate(data['candidate'], data['fromSocketId']);
    });

    ApiService.socket!.on('user-joined', (data) {
      final socketId = data['socketId'] as String;
      final userId = data['userId'] as String;
      print('User joined: $userId ($socketId)');
      setState(() {
        _participants[socketId] = userId;
      });

      _initiateWebRTCConnection(socketId);
    });

    ApiService.socket!.on('user-left', (data) {
      final socketId = data['socketId'] as String;
      setState(() {
        _participants.remove(socketId);
        _remoteRenderers.removeWhere((key, value) => true);
        _peerConnections.remove(socketId)?.close();
      });
    });
  }

  Future<void> _initiateWebRTCConnection(String toSocketId) async {
    try {
      final peerConnection = await _createPeerConnection(toSocketId);
      _peerConnections[toSocketId] = peerConnection;

      _localStream?.getTracks().forEach((track) {
        peerConnection.addTrack(track, _localStream!);
      });

      final offer = await peerConnection.createOffer();
      await peerConnection.setLocalDescription(offer);
      ApiService.socket!.emit('offer', {
        'sdp': offer.sdp,
        'toSocketId': toSocketId,
      });
    } catch (e) {
      print('Error initiating WebRTC connection to $toSocketId: $e');
    }
  }

  Future<void> _handleOffer(String sdp, String fromSocketId) async {
    try {
      if (!_peerConnections.containsKey(fromSocketId)) {
        final peerConnection = await _createPeerConnection(fromSocketId);
        _peerConnections[fromSocketId] = peerConnection;

        _localStream?.getTracks().forEach((track) {
          peerConnection.addTrack(track, _localStream!);
        });
      }

      final peerConnection = _peerConnections[fromSocketId]!;
      await peerConnection.setRemoteDescription(RTCSessionDescription(sdp, 'offer'));
      final answer = await peerConnection.createAnswer();
      await peerConnection.setLocalDescription(answer);
      ApiService.socket!.emit('answer', {
        'sdp': answer.sdp,
        'toSocketId': fromSocketId,
      });
    } catch (e) {
      print('Error handling offer from $fromSocketId: $e');
    }
  }

  Future<void> _handleAnswer(String sdp, String fromSocketId) async {
    try {
      final peerConnection = _peerConnections[fromSocketId];
      if (peerConnection != null) {
        await peerConnection.setRemoteDescription(RTCSessionDescription(sdp, 'answer'));
      }
    } catch (e) {
      print('Error handling answer from $fromSocketId: $e');
    }
  }

  Future<void> _handleIceCandidate(Map<String, dynamic> candidateData, String fromSocketId) async {
    try {
      final peerConnection = _peerConnections[fromSocketId];
      if (peerConnection != null) {
        await peerConnection.addCandidate(
          RTCIceCandidate(candidateData['candidate'], candidateData['sdpMid'], candidateData['sdpMLineIndex']),
        );
      }
    } catch (e) {
      print('Error handling ICE candidate from $fromSocketId: $e');
    }
  }

  Future<void> _shareFile() async {
    FilePickerResult? result = await FilePicker.platform.pickFiles(
      allowMultiple: false,
      type: FileType.any,
    );
    if (result != null) {
      final fileName = result.files.single.name;
      final fileBytes = result.files.single.bytes;
      if (fileBytes != null) {
        try {
          await ApiService.uploadFile(_selectedUserId!, fileName, fileBytes);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('$fileName shared successfully!')),
          );
        } catch (e) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error uploading file: $e')),
          );
        }
      }
    }
  }

  Future<void> _downloadFile(String fileName) async {
    try {
      final url = await ApiService.downloadFile(fileName);
      final uri = Uri.parse(url);
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      } else {
        throw 'Could not launch $url';
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error downloading file: $e')),
      );
    }
  }

  void _saveNote() {
    if (_noteController.text.isNotEmpty) {
      ApiService.saveNote(_selectedUserId!, _meetingCode, _noteController.text);
      _noteController.clear();
    }
  }

  void _toggleMic() {
    setState(() {
      _isMicMuted = !_isMicMuted;
      _localStream?.getAudioTracks().forEach((track) {
        track.enabled = !_isMicMuted;
      });
    });
  }

  void _toggleCamera() {
    setState(() {
      _isCameraOff = !_isCameraOff;
      _localStream?.getVideoTracks().forEach((track) {
        track.enabled = !_isCameraOff;
      });
    });
  }

  @override
  void dispose() {
    _localRenderer.dispose();
    _remoteRenderers.values.forEach((renderer) => renderer.dispose());
    _peerConnections.forEach((key, peerConnection) => peerConnection.close());
    _localStream?.dispose();
    ApiService.socket?.disconnect();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Constant Meeting - $_selectedUserId'),
        backgroundColor: Colors.blueAccent,
      ),
      body: _isJoined
          ? Column(
              children: [
                Expanded(
                  flex: 2,
                  child: Container(
                    color: Colors.black,
                    child: Stack(
                      children: [
                        _remoteRenderers.isEmpty
                            ? const Center(child: Text('Waiting for others to join...', style: TextStyle(color: Colors.white)))
                            : GridView.builder(
                                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                                  crossAxisCount: 2,
                                  childAspectRatio: 1.5,
                                ),
                                itemCount: _remoteRenderers.length,
                                itemBuilder: (context, index) {
                                  final trackId = _remoteRenderers.keys.elementAt(index);
                                  return Padding(
                                    padding: const EdgeInsets.all(4.0),
                                    child: Container(
                                      decoration: BoxDecoration(
                                        border: Border.all(color: Colors.white),
                                      ),
                                      child: Stack(
                                        children: [
                                          RTCVideoView(_remoteRenderers[trackId]!),
                                          Positioned(
                                            top: 5,
                                            left: 5,
                                            child: Text(
                                              'User ${_participants[_getOpponentSocketId()]}',
                                              style: const TextStyle(color: Colors.white, fontSize: 12),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  );
                                },
                              ),
                        Positioned(
                          bottom: 10,
                          right: 10,
                          child: Container(
                            width: 100,
                            height: 150,
                            decoration: BoxDecoration(
                              border: Border.all(color: Colors.white),
                            ),
                            child: _localRenderer.srcObject != null
                                ? RTCVideoView(_localRenderer)
                                : const Center(child: Text('No Video', style: TextStyle(color: Colors.white))),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                Container(
                  color: Colors.grey[900],
                  padding: const EdgeInsets.symmetric(vertical: 8.0),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      IconButton(
                        icon: Icon(
                          _isMicMuted ? Icons.mic_off : Icons.mic,
                          color: _isMicMuted ? Colors.red : Colors.white,
                        ),
                        onPressed: _toggleMic,
                      ),
                      IconButton(
                        icon: Icon(
                          _isCameraOff ? Icons.videocam_off : Icons.videocam,
                          color: _isCameraOff ? Colors.red : Colors.white,
                        ),
                        onPressed: _toggleCamera,
                      ),
                      IconButton(
                        icon: const Icon(Icons.call_end, color: Colors.red),
                        onPressed: () {
                          Navigator.pop(context);
                        },
                      ),
                    ],
                  ),
                ),
                Expanded(
                  flex: 1,
                  child: DefaultTabController(
                    length: 3,
                    child: Column(
                      children: [
                        const TabBar(
                          labelColor: Colors.blueAccent,
                          unselectedLabelColor: Colors.grey,
                          indicatorColor: Colors.blueAccent,
                          tabs: [
                            Tab(text: 'Chat'),
                            Tab(text: 'Files'),
                            Tab(text: 'Notes'),
                          ],
                        ),
                        Expanded(
                          child: TabBarView(
                            children: [
                              ListView.builder(
                                itemCount: _messages.length,
                                itemBuilder: (context, index) {
                                  final message = _messages[index];
                                  return ListTile(
                                    title: Text(
                                      message['text'],
                                      style: const TextStyle(color: Colors.black87),
                                    ),
                                    subtitle: Text(
                                      'From: ${message['userId']}',
                                      style: const TextStyle(color: Colors.grey),
                                    ),
                                  );
                                },
                              ),
                              ListView.builder(
                                itemCount: _files.length,
                                itemBuilder: (context, index) {
                                  final file = _files[index];
                                  return ListTile(
                                    title: Text(file['fileName']),
                                    subtitle: Text('Shared by ${file['userId']}'),
                                    trailing: const Icon(Icons.download, color: Colors.blueAccent),
                                    onTap: () => _downloadFile(file['fileName']),
                                  );
                                },
                              ),
                              Column(
                                children: [
                                  Expanded(
                                    child: ListView.builder(
                                      itemCount: _notes.length,
                                      itemBuilder: (context, index) {
                                        final note = _notes[index];
                                        return ListTile(
                                          title: Text(note['content']),
                                          subtitle: Text('By: ${note['userId']}'),
                                        );
                                      },
                                    ),
                                  ),
                                  Padding(
                                    padding: const EdgeInsets.all(8.0),
                                    child: Row(
                                      children: [
                                        Expanded(
                                          child: TextField(
                                            controller: _noteController,
                                            decoration: const InputDecoration(
                                              hintText: 'Add a note...',
                                              border: OutlineInputBorder(),
                                              filled: true,
                                              fillColor: Colors.white,
                                            ),
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        IconButton(
                                          icon: const Icon(Icons.note_add, color: Colors.blueAccent),
                                          onPressed: _saveNote,
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(8.0),
                  child: Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _messageController,
                          decoration: const InputDecoration(
                            hintText: 'Type a message...',
                            border: OutlineInputBorder(),
                            filled: true,
                            fillColor: Colors.white,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      IconButton(
                        icon: const Icon(Icons.send, color: Colors.blueAccent),
                        onPressed: () {
                          if (_messageController.text.isNotEmpty) {
                            ApiService.sendMessage(_selectedUserId!, _messageController.text);
                            _messageController.clear();
                          }
                        },
                      ),
                      IconButton(
                        icon: const Icon(Icons.attach_file, color: Colors.blueAccent),
                        onPressed: _shareFile,
                      ),
                    ],
                  ),
                ),
              ],
            )
          : const Center(child: CircularProgressIndicator()),
    );
  }
}