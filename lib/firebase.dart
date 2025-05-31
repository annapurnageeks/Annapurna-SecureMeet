import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';

Future<void> initializeFirebase() async {
  await Firebase.initializeApp(
    options: const FirebaseOptions(
      apiKey: "AIzaSyBcd-XdV0tcEc0jKH4IbRz_vhbyGZi3mAI",
      authDomain: "annapurna-meet.firebaseapp.com",
      projectId: "annapurna-meet",
      storageBucket: "annapurna-meet.firebasestorage.app",
      messagingSenderId: "296607084312",
      appId: "1:296607084312:web:7af5e84300d358338d386d",
      measurementId: "G-XB7NP3VN0T",
    ),
  );

  // Connect to emulator if running locally
  if (true) { // You can change this to false when using real Firebase
    FirebaseAuth.instance.useAuthEmulator('localhost', 9099);
  }
}