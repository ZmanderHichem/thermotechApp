import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:saadoun/auth.dart';
import 'package:saadoun/signin.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SignUp extends StatefulWidget {
  const SignUp({super.key});

  @override
  _SignUpState createState() => _SignUpState();
}

class _SignUpState extends State<SignUp> {
  final List<String> _choices = ['nuit', 'jour'];
  late final String? _selectedChoice = "jour";

  late String? _eemail = ""; //
  late String? _uuserName = ""; //
  late String? _Tel = "";
  late String? _MDP = "";
  late String? _MDP2 = "";

  String? errorMessage = "";
  bool PassCorrect = false;
  final TextEditingController _controllerEmail = TextEditingController();

  final TextEditingController _controllerPassword = TextEditingController();
  Future<String?> getFromLocalStorage(String key) async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    return prefs.getString(key);
  }

  Future<void> addUserDataToFirestore() async {
    try {
      // Get the current authenticated user
      User? user = FirebaseAuth.instance.currentUser;
      print("user : $user");
      if (user != null) {
        // Reference to the user's document in the 'users' collection
        DocumentReference userDocRef =
            FirebaseFirestore.instance.collection('users').doc(user.uid);

        // Define user data to be stored in Firestore
        Map<String, dynamic> userData = {
          'UserName': _uuserName,
          'Email': _eemail,
          'Tel': _Tel,
          'Password': _MDP2,
          'MatType': _selectedChoice,
          // Add other user-related fields as needed
        };
        print('User data : $userData');
        // Set the data in Firestore
        await userDocRef
            .set(userData)
            .then((value) => {
                  userData = {},
                  print('User data added to Firestore for UID: ${user.uid}')
                })
            .then((value) => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => SignIn()),
                ));

        print('User data added to Firestore for UID: ${user.uid}');
      } else {
        print('User is not signed in');
      }
    } catch (e) {
      print("probleme: ${e.toString()}");
    }
  }

  Future<void> createUserwithEmailAndPassword() async {
    try {
      await Auth().createUserWithEmailAndPassword(
        email: _controllerEmail.text,
        password: _controllerPassword.text,
      );
    } on FirebaseAuthException catch (e) {
      setState(() {
        errorMessage = e.message;
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
        print("errrrrror : $errorMessage");
      });
    }
  }

  @override
  void initState() {
    super.initState();
    Auth().signOut();
    print("object");
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.only(left: 20.0, right: 20.0),
          child: SingleChildScrollView(
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.arrow_back),
                      onPressed: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(builder: (context) => SignIn()),
                        );
                      },
                    ),
                    const Text(
                      'Register Account',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 20,
                      ),
                    ),
                    const SizedBox(width: 40),
                  ],
                ),
                const SizedBox(height: 20),
                const SizedBox(height: 20),
                TextField(
                  onChanged: (String? uuserName) {
                    setState(() {
                      _uuserName = uuserName!;
                    });
                    print('user Name: $uuserName');
                  },
                  decoration: const InputDecoration(
                    labelText: 'Full Name',
                    icon: Icon(Icons.person),
                  ),
                ),
                const SizedBox(height: 20),
                TextField(
                  controller: _controllerEmail,
                  keyboardType: TextInputType.emailAddress,
                  onChanged: (String? eemail) {
                    setState(() {
                      _eemail = eemail!;
                    });
                    print('email: $eemail');
                    print('controller: $_controllerEmail.text ');
                  },
                  decoration: const InputDecoration(
                    labelText: 'Votre Email',
                    icon: Icon(Icons.email),
                  ),
                ),
                const SizedBox(height: 20),
                
                TextField(
                  onChanged: (String? Tel) {
                    setState(() {
                      _Tel = Tel!;
                    });
                    print('email: $Tel');
                  },
                  decoration: const InputDecoration(
                    labelText: 'TEL',
                    icon: Icon(Icons.phone),
                  ),
                ),
                const SizedBox(height: 20),
                TextField(
                  onChanged: (String? MDP) {
                    setState(() {
                      _MDP = MDP!;
                    });
                    print('email: $MDP');
                  },
                  obscureText: true,
                  decoration: const InputDecoration(
                    labelText: 'Password',
                    icon: Icon(Icons.lock),
                  ),
                ),
                const SizedBox(height: 20),
                TextField(
                  obscureText: true,
                  controller: _controllerPassword,
                  onChanged: (String? MDP2) {
                    setState(() {
                      if (MDP2 == _MDP) {
                        _MDP2 = MDP2!;
                        PassCorrect = true;
                      } else {
                        PassCorrect = false;
                      }
                    });
                    print('email: $MDP2');
                  },
                  decoration: const InputDecoration(
                    labelText: 'Confirm Password',
                    icon: Icon(Icons.lock),
                  ),
                ),
                const SizedBox(height: 20),
                ElevatedButton(
                  onPressed: () {
                    print('error: $errorMessage');

                    if (PassCorrect == true) {
                      print("D5all");
                      createUserwithEmailAndPassword().then((value) =>
                          {addUserDataToFirestore(), print("TLA3333")});
                      Auth().signOut();
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: const Padding(
                            padding: EdgeInsets.only(
                                bottom: 10), // Add bottom margin here
                            child: Text(
                              "compte créée",
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                              ), // Change font size here
                            ),
                          ),
                          backgroundColor: const Color.fromARGB(
                              255, 0, 184, 3), // Change background color here
                          shape: RoundedRectangleBorder(
                            borderRadius:
                                BorderRadius.circular(30), // Change shape here
                          ),
                        ),
                      );
                      /*FirebaseAuth.instance.authStateChanges().listen((User? user) {
  if (user != null) {
    // User is signed in
    print("addUserDataToFirestore");
  } else {
    // User is signed out
    print('User is signed out');
  }
}
);*/

                      PassCorrect = false;
                    } else {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: const Padding(
                            padding: EdgeInsets.only(
                                bottom: 10), // Add bottom margin here
                            child: Text(
                              "wrong password",
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                              ), // Change font size here
                            ),
                          ),
                          backgroundColor: const Color.fromARGB(
                              255, 207, 62, 52), // Change background color here
                          shape: RoundedRectangleBorder(
                            borderRadius:
                                BorderRadius.circular(30), // Change shape here
                          ),
                        ),
                      );
                      print("rodha toast:wrong password");
                    }
                  },
                  child: const Text('CONTINUE'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
