import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:mailer/mailer.dart';
import 'package:mailer/smtp_server/gmail.dart';
import 'package:saadoun/auth.dart';
import 'package:saadoun/contact.dart';
import 'package:saadoun/history.dart';
import 'package:saadoun/home.dart';
import 'package:saadoun/informations.dart';
import 'package:saadoun/localStorage.dart';
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
  final LStorage _lStorage = LStorage();
  UserData? _storedData;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _initializeData();
  }

  Future<void> _initializeData() async {
    setState(() => _isLoading = true);
    await _loadData();
    await _fetchData();
    if (mounted) setState(() => _isLoading = false);
  }

  Future<void> _loadData() async {
    final mapData = await _lStorage.getStoredData('userData');
    if (mapData != null) {
      setState(() => _storedData = UserMapper.mapToUserData(mapData));
    }
  }

  Future<void> _fetchData() async {
    if (_storedData?.Plate == null) return;

    try {
      final querySnapshot = await FirebaseFirestore.instance
          .collection('FACT')
          .doc(_storedData?.Plate)
          .collection('facture')
          .get();

      if (querySnapshot.docs.isEmpty) return;

      final List<Map<String, dynamic>> jsonDataList = [];
      final Map<String, dynamic> uniqueDataMap = {};

      for (var doc in querySnapshot.docs) {
        final data = doc.data();
        final dateFact = data['DATEFACT'].toString().substring(0, 10);
        data['DATEFACT'] = dateFact;

        jsonDataList.add(data);
        uniqueDataMap[data['LIBELLEARTICLE']] = data;
      }

      final jsonUniqueDataList = uniqueDataMap.values.toList();
      jsonDataList.sort((b, a) => a['DATEFACT'].compareTo(b['DATEFACT']));
      jsonUniqueDataList.sort((b, a) => a['DATEFACT'].compareTo(b['DATEFACT']));

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('factureData', jsonEncode(jsonDataList));
      await prefs.setString('factureUniqueData', jsonEncode(jsonUniqueDataList));
    } catch (e) {
      debugPrint('Error fetching data: $e');
    }
  }

  Future<void> _sendMail({
    required String recipientEmail,
    required String mailMessage,
  }) async {
    if (mailMessage.isEmpty) {
      _showErrorSnackBar('Le message ne peut pas être vide');
      return;
    }

    try {
      final message = Message()
        ..from = const Address('youssef.zmander@gmail.com', 'Problème Bosh Car')
        ..recipients.add(recipientEmail)
        ..subject = 'Panne With Boch Car service Sliti auto'
        ..text =
            'Message from ${_storedData?.Email} Immat num ${_storedData?.Plate}: $mailMessage';

      final smtpServer = gmail('youssef.zmander@gmail.com', 'bilnwrnkybqfptmf');
      await send(message, smtpServer);

      if (mounted) {
        _showSuccessSnackBar('Message envoyé avec succès');
      }
    } catch (e) {
      debugPrint('Error sending email: $e');
      _showErrorSnackBar('Erreur lors de l\'envoi du message');
    }
  }

  void _showSuccessSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          message,
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 16),
        ),
        backgroundColor: Colors.green,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
      ),
    );
  }

  void _showErrorSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          message,
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 16),
        ),
        backgroundColor: Colors.red,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
      ),
    );
  }

  Future<void> _showReportDialog() async {
    String textValue = '';
    return showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text(
            'Signaler un problème',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          ),
          content: TextField(
            onChanged: (value) => textValue = value,
            decoration: const InputDecoration(
              hintText: 'Décrivez votre problème',
              border: OutlineInputBorder(),
            ),
            maxLines: 3,
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Annuler'),
            ),
            ElevatedButton(
              onPressed: () {
                _sendMail(
                  recipientEmail: 'hafedh.zd@gmail.com',
                  mailMessage: textValue,
                );
                Navigator.of(context).pop();
              },
              child: const Text('Envoyer'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _showLogoutDialog() async {
    return showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Déconnexion'),
          content: const Text('Voulez-vous vraiment vous déconnecter ?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Annuler'),
            ),
            ElevatedButton(
              onPressed: () {
                Auth().signOut();
                Navigator.pushReplacement(
                  context,
                  MaterialPageRoute(builder: (context) => const SignIn()),
                );
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red,
                foregroundColor: Colors.white,
              ),
              child: const Text('Déconnexion'),
            ),
          ],
        );
      },
    );
  }

  final List<Widget> _pages = [
    const HomePage(),
    const RdvSuggerer(),
    const ClientSearchPage(),
    const AtelierPage(),
  ];

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        body: Center(
          child: CircularProgressIndicator(),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(
          _getPageTitle(),
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        leading: IconButton(
          icon: const Icon(
            Icons.report_problem_outlined,
            color: Colors.red,
          ),
          onPressed: _showReportDialog,
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.qr_code_scanner_outlined),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const AdminDashboard()),
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.logout_outlined),
            onPressed: _showLogoutDialog,
          ),
        ],
      ),
      body: _pages[_currentIndex],
      bottomNavigationBar: NavigationBar(
        selectedIndex: _currentIndex,
        onDestinationSelected: (index) {
          setState(() => _currentIndex = index);
        },
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.calendar_today_outlined),
            selectedIcon: Icon(Icons.calendar_today),
            label: 'RDV',
          ),
          NavigationDestination(
            icon: Icon(Icons.add_circle_outline),
            selectedIcon: Icon(Icons.add_circle),
            label: 'Ajouter',
          ),
          NavigationDestination(
            icon: Icon(Icons.people_outline),
            selectedIcon: Icon(Icons.people),
            label: 'Clients',
          ),
          NavigationDestination(
            icon: Icon(Icons.build_outlined),
            selectedIcon: Icon(Icons.build),
            label: 'Atelier',
          ),
        ],
      ),
    );
  }

  String _getPageTitle() {
    switch (_currentIndex) {
      case 0:
        return 'Rendez-vous';
      case 1:
        return 'Ajouter un RDV';
      case 2:
        return 'Clients';
      case 3:
        return 'Atelier';
      default:
        return '';
    }
  }
}