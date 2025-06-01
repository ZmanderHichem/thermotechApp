import 'dart:async';
import 'package:flutter/material.dart';
import 'package:saadoun/signin.dart';
import 'package:flutter/services.dart';
import 'dart:io';

import 'package:firebase_core/firebase_core.dart';
import 'firebase_options.dart';
import 'call_service.dart'; // Import the service
import 'call_service_initializer.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Check if Firebase is already initialized
  if (Firebase.apps.isEmpty) {
    await Firebase.initializeApp(
      name: 'electrogel',
      options: DefaultFirebaseOptions.currentPlatform,
    );
  }

  runApp(MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});


  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Electrogel',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
        useMaterial3: true,
      ),
      home: MyHomePage(),
    );
  }
}

class MyHomePage extends StatefulWidget {
  const MyHomePage({super.key});

  @override
  _MyHomePageState createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  final CallService _callService = CallService();

  @override
  void initState() {
    super.initState();
    initializeCallService(context, _callService);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Image.asset(
          'lib/assets/download.gif',
          height: MediaQuery.of(context)
              .size
              .height, // Ajuste la hauteur selon l'écran
          width: MediaQuery.of(context)
              .size
              .width, // Ajuste la largeur selon l'écran
          fit: BoxFit.cover, // Adapte le GIF pour couvrir toute la zone
        ),
      ),
    );
  }
}
