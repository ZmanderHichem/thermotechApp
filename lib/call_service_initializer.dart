import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'call_service.dart';
import 'signin.dart';

Future<void> initializeCallService(BuildContext context, CallService callService) async {
  if (Platform.isAndroid) {
    await callService.registerReceiver();
    await callService.requestPermissions();
  }

  Timer(
    const Duration(seconds: 3),
    () => Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (context) => SignIn()),
    ),
  );
}
