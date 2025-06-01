import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:mailer/mailer.dart';
import 'package:mailer/smtp_server/gmail.dart';
import 'package:saadoun/auth.dart';
import 'package:saadoun/contact.dart';
import 'package:saadoun/history.dart';
import 'package:saadoun/home.dart';
import 'package:saadoun/informations.dart';
import 'package:saadoun/localStorage.dart';
import 'package:saadoun/profile.dart';
import 'package:saadoun/rdvSuggerer.dart';
import 'package:saadoun/signin.dart';
import 'package:shared_preferences/shared_preferences.dart';

class BottomNavigation extends StatefulWidget {
  const BottomNavigation({super.key});

  @override
  _BottomNavigationState createState() => _BottomNavigationState();
}

class _BottomNavigationState extends State<BottomNavigation> {
  int _currentIndex = 0;

  LStorage lStorage = LStorage();
  UserData? storedData;

  Future<void> fetchData() async {
    try {
      
      if (storedData?.Plate != null) {
        // Reference to the user's document in the 'users' collection
        QuerySnapshot<Map<String, dynamic>> querySnapshot =
            await FirebaseFirestore.instance
                .collection('FACT')
                .doc(storedData?.Plate)
                .collection('facture')
                .get();
        print('UIMATTTT: ${storedData?.Plate}');
        if (querySnapshot.docs.isEmpty) {
          print('No documents found.');
        } else {
          print('Documents found:');
          // Convert Firestore document data to JSON
          List<Map<String, dynamic>> jsonDataList = [];
          List<Map<String, dynamic>>? jsonUniqueDataList = [];
          Map<String, dynamic> uniqueDataMap = {}; // Map to store unique data

          for (QueryDocumentSnapshot<Map<String, dynamic>> doc
              in querySnapshot.docs) {
            print('Documents fffffff');
            Map<String, dynamic> data = doc.data();
            String libelleArticle = data['LIBELLEARTICLE'];

            String dateFact = data['DATEFACT'].substring(0, 10);
            // Replace Timestamp with DateTime
            data['DATEFACT'] = dateFact;

            jsonDataList.add(data);
            print("data");
            print(data);
            if (uniqueDataMap.containsKey(libelleArticle)) {
              continue;
            } else {
              jsonUniqueDataList.add(data);
              uniqueDataMap[libelleArticle] = data;
            }
          }
          jsonUniqueDataList =
              uniqueDataMap.values.cast<Map<String, dynamic>>().toList();
          jsonUniqueDataList
              .sort((b, a) => a['DATEFACT'].compareTo(b['DATEFACT']));

          jsonDataList.sort((b, a) => a['DATEFACT'].compareTo(b['DATEFACT']));
          print('sorttttttttt');
          print(jsonUniqueDataList);
          // Save JSON data to local storage
          SharedPreferences prefs = await SharedPreferences.getInstance();
          String jsonString = jsonEncode(jsonDataList);
          String jsonUniqueString = jsonEncode(jsonUniqueDataList);
          await prefs.setString('factureData', jsonString);
          await prefs.setString('factureUniqueData', jsonUniqueString);
          print('Data saved to local storage.');
          print('Data 3adeya$jsonString');
          print('Data Unique$jsonUniqueString');
        }
        print('5rjt');
        // Check if the document exists
      } else {
        print('User is not signed indaaaaata');
      }
    } catch (e) {
      print('Error retrieving data: $e');
    }
  }

  Map<String, dynamic>? mapData;
  Future<void> loadData() async {
    mapData = await lStorage.getStoredData('userData');
    if (mapData != null) {
      storedData = UserMapper.mapToUserData(mapData!);
      print('Stored Map Data: $storedData');
      // You can use storedData as needed in your widget
      setState(() {}); // Trigger a rebuild to update the UI
    }
    print('Stored Map Data: $storedData');
    // You can use storedData as needed in your widget
  }

  @override
  void initState() {
    super.initState();
    loadData().then((value) => fetchData());
  }

  final List<Widget> _pages = [
    HomePage(), // RDV page
    //AddRdvPage(), // Add page
    RdvSuggerer(),
    ClientSearchPage(), // Clients page
    AtelierPage(), // Profile page
  ];

  final List<String> _pagesTitle = [
    "RDV", // New name for Home
    "Add", // New name for History
    "Clients", // New name for Informations
    "Atelier", // Unchanged
  ];

  void _onItemTapped(int index) {
    setState(() {
      _currentIndex = index;
    });
  }

  void sendMail({
    required String recipientEmail,
    required String mailMessage,
  }) async {
    String username = 'youssef.zmander@gmail.com';
    String password = 'bilnwrnkybqfptmf';
    final smtpServer = gmail(username, password);
    final message = Message()
      ..from = Address(username, 'probleme Bosh Car')
      ..recipients.add(recipientEmail)
      ..subject = 'panne With Boch Car service Sliti auto '
      ..text =
          'Message from ${storedData?.Email} Immat num ${storedData?.Plate}: $mailMessage';

    try {
      if (mailMessage != "") {
        await send(message, smtpServer).then(
          (value) => ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Padding(
                padding: EdgeInsets.only(bottom: 10),
                child: Text(
                  "Message envoyé ",
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              backgroundColor: const Color.fromARGB(255, 0, 184, 3),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(30),
              ),
            ),
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: const Padding(
            padding: EdgeInsets.only(bottom: 10),
            child: Text(
              "Message vide non envoyée ",
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          backgroundColor: const Color.fromARGB(255, 242, 22, 22),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(30),
          ),
        ));
      }
    } catch (e) {
      if (kDebugMode) {
        print(e.toString());
      }
    }
  }
  //53581125
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          _pagesTitle[_currentIndex],
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        centerTitle: true,
        backgroundColor: Colors.blue,
        leading: IconButton(
          icon: const Icon(
            Icons.report,
            color: Color.fromARGB(255, 190, 20, 8),
            size: 30,
          ),
          onPressed: () {
            showDialog(
              context: context,
              builder: (BuildContext context) {
                String textValue = '';
                return AlertDialog(
                  title: const Text(
                    'Signaler un problem',
                    style: TextStyle(fontSize: 23, fontWeight: FontWeight.bold),
                  ),
                  content: TextField(
                    onChanged: (value) {
                      textValue = value;
                    },
                    decoration: const InputDecoration(hintText: 'Entrer text'),
                  ),
                  actions: <Widget>[
                    TextButton(
                      onPressed: () {
                        Navigator.of(context).pop();
                      },
                      child: const Text('Cancel'),
                    ),
                    TextButton(
                      onPressed: () {
                        print('Text entered: $textValue');
                        sendMail(
                            recipientEmail: 'hafedh.zd@gmail.com',
                            mailMessage: textValue);
                        Navigator.of(context).pop();
                      },
                      child: const Text('OK'),
                    ),
                  ],
                );
              },
            );
          },
        ),
        actions: <Widget>[
          IconButton(
            icon: const Icon(
                Icons.camera_alt), // Utiliser une icône pour le scanner QR code
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => AdminDashboard()),
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () {
              showDialog(
                context: context,
                builder: (BuildContext context) {
                  return AlertDialog(
                    title: const Text('Deconection'),
                    content: const Text('Confirmer la deconection'),
                    actions: <Widget>[
                      TextButton(
                        onPressed: () {
                          print('User want to logout');
                          Navigator.of(context).pop();
                        },
                        child: const Text('Cancel'),
                      ),
                      TextButton(
                        onPressed: () {
                          Auth().signOut();
                          Navigator.push(
                            context,
                            MaterialPageRoute(builder: (context) => SignIn()),
                          );
                        },
                        child: const Text('OK'),
                      ),
                    ],
                  );
                },
              );
            },
          ),
        ],
      ),
      body: _pages[_currentIndex],
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentIndex,
        type: BottomNavigationBarType.fixed,
        onTap: _onItemTapped,
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.calendar_today), // Icon for RDV
            label: 'RDV',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.add), // Icon for Add
            label: 'Add',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.group), // Icon for Clients
            label: 'Clients',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.build), // Icon for Clients
            label: 'Atelier',
          ),
        ],
      ),
    );
  }
}
