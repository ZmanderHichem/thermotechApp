import 'package:flutter/services.dart';

class CallService {
  static const MethodChannel _channel =
      MethodChannel('com.example.myapp/phonecall');

  Future<void> registerReceiver() async {
    try {
      await _channel.invokeMethod('registerReceiver');
      print("Receiver Registered");
    } on PlatformException catch (e) {
      print("Failed to register receiver: ${e.message}");
    }
  }

  Future<void> requestPermissions() async {
    try {
      await _channel.invokeMethod('requestPermissions');
      print("Permissions Requested");
    } on PlatformException catch (e) {
      print("Failed to request permissions: ${e.message}");
    }
  }
}
