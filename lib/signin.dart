import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
//import 'package:flutter_application_1/mainHome.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:saadoun/auth.dart';
import 'package:saadoun/localStorage.dart';
import 'package:saadoun/mainHome.dart';
import 'package:saadoun/signup.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';

class SignIn extends StatefulWidget {
  const SignIn({super.key});

  @override
  _SignInState createState() => _SignInState();
}

class _SignInState extends State<SignIn> {
  final TextEditingController _controllerEmail = TextEditingController();
  final TextEditingController _controllerPassword = TextEditingController();

  String? errorMessage = "";
  bool isLoading = false; // Add this line
void test() async {
  final plugin = DeviceInfoPlugin();
  final android = await plugin.androidInfo;
  print(android.version.sdkInt);

  final storageStatus = android.version.sdkInt < 33
      ? await Permission.storage.request()
      : PermissionStatus.granted;

  if (storageStatus == PermissionStatus.granted) {
    print("granted");
  }
  if (storageStatus == PermissionStatus.denied) {
    print("denied");
  }
  if (storageStatus == PermissionStatus.permanentlyDenied) {
    openAppSettings();
  }
}

  Future<void> addToLocalStorage(String key, String value) async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    prefs.setString(key, value);
    print('Data added to local storage');
  }

  LStorage lStorage = LStorage();

  @override
  void initState() {
    super.initState();
    FirebaseAuth.instance.authStateChanges().listen((User? user) {
      if (user != null) {
        
        print('User is signed in');
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (context) => BottomNavigation()),
        );
      } 
    });
  }

  Future<Map<String, dynamic>> getUserData() async {
    User? user = FirebaseAuth.instance.currentUser;
    print('Userrrrrrrrrr: $user');
    print('UserrrrrrrrrrUID: ${user?.uid}');
    if (user?.uid != null) {
      DocumentSnapshot<Map<String, dynamic>> snapshot = await FirebaseFirestore
          .instance
          .collection('users')
          .doc(user?.uid)
          .get();

      if (snapshot.exists) {
        Map<String, dynamic> userData = snapshot.data()!;
        print("userDataaaaa");
        print(userData);
        return userData;
      } else {
        print('User document does not exist');
        return {};
      }
    } else {
      print('User is not signed in');
      return {};
    }
  }

  Future<void> signInWithEmailAndPassword(BuildContext context) async {
    setState(() {
      isLoading = true; // Show loading indicator
    });

    try {
      await Auth()
          .signInWithEmailAndPassword(
            email: _controllerEmail.text,
            password: _controllerPassword.text,
          )
          .then((value) => getUserData().then((userData) async {
                print('User Data: $userData');
                String jsonMap = jsonEncode(userData);
                lStorage
                    .addToLocalStorage('userData', jsonMap)
                    .then((value) => {
                          print('S7iii7'),
                        });
              }).then((value) => Navigator.push(
                    context,
                    MaterialPageRoute(builder: (context) => BottomNavigation()),
                  )));
    } on FirebaseAuthException catch (e) {
      setState(() {
        errorMessage = e.code;
        // Show SnackBar with error message

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Padding(
              padding: const EdgeInsets.only(bottom: 10), // Add bottom margin here
              child: Text(
                errorMessage!,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ), // Change font size here
              ),
            ),
            backgroundColor: const Color.fromARGB(
                255, 207, 62, 52), // Change background color here
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(30), // Change shape here
            ),
          ),
        );
      });
    } finally {
      setState(() {
        isLoading = false; // Hide loading indicator
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Stack(
          children: [
            Padding(
              padding: const EdgeInsets.only(
                  left: 20.0, right: 20.0), // Adjust the left padding as needed
              child: Column(
                children: [
                  const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        'Login',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 20,
                        ),
                      ),
                      SizedBox(width: 40),
                    ],
                  ),
                  const SizedBox(height: 100),
                  TextField(
                    controller: _controllerEmail,
                    keyboardType: TextInputType.emailAddress,
                    decoration: const InputDecoration(
                      labelText: 'Votre Email',
                      icon: Icon(Icons.email),
                    ),
                  ),
                  const SizedBox(height: 20),
                  TextField(
                    controller: _controllerPassword,
                    obscureText: true,
                    decoration: const InputDecoration(
                      labelText: 'Password',
                      icon: Icon(Icons.lock),
                    ),
                  ),
                  const SizedBox(height: 20),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      TextButton(
                        onPressed: () {
                          Auth().resetPassword(_controllerEmail.text);
                        },
                        child: const Text(
                          'Forget your Password',
                          style: TextStyle(
                            color: Colors.grey,
                          ),
                        ),
                      ),
                      ElevatedButton(
                        onPressed: () {
                          // Pass context to signInWithEmailAndPassword function
                          signInWithEmailAndPassword(context);
                        },
                        child: const Text('Log In'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  const Text(
                    "You don't have an account?",
                    style: TextStyle(
                      fontSize: 16,
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextButton(
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(builder: (context) => SignUp()),
                      );
                    },
                    child: const Text(
                      'Sign up',
                      style: TextStyle(
                        color: Colors.blue,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            if (isLoading)
              const Center(
                child: CircularProgressIndicator(), // Replace with your loading GIF if needed
              ),
          ],
        ),
      ),
    );
  }
}
