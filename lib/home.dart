import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart'; // Added for date formatting

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  _HomePageState createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  Stream<List<Appointment>>? _appointmentsStream;

  @override
  void initState() {
    super.initState();
    _appointmentsStream = _fetchAppointments();
  }

  Stream<List<Appointment>> _fetchAppointments() {
    return FirebaseFirestore.instance
        .collection('rdv')
        .snapshots()
        .map((snapshot) {
      return snapshot.docs.map((doc) {
        final data = doc.data();
        return Appointment.fromFirestore(data, doc.id);
      }).toList();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Rendez-vous'),
        automaticallyImplyLeading: false, // Prevent app bar from going back
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () {
              setState(() {
                _appointmentsStream = _fetchAppointments();
              });
            },
          ),
        ],
      ),
      body: StreamBuilder<List<Appointment>>(
        stream: _appointmentsStream,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (snapshot.hasError) {
            return Center(child: Text('Error: ${snapshot.error}'));
          }

          final appointments = snapshot.data ?? [];

          return ListView.builder(
            itemCount: appointments.length,
            itemBuilder: (context, index) {
              final appointment = appointments[index];
              return Card(
                color: const Color.fromARGB(
                    255, 200, 198, 198), // Arrière-plan gris
                child: ListTile(
                  title: Text(appointment.nomClient),
                  subtitle: Text(
                    'Téléphone: ${appointment.numeroTelephone}\n'
                    'Adresse: ${appointment.address}\n'
                    'Type Machine: ${appointment.typeMachine}\n'
                    'panne: ${appointment.panne}\n'
                    'Date: ${appointment.timestamp.toDate()}',
                  ),
                  isThreeLine: true,
                  onTap: () {
                    _showPopupMenu(context, appointment);
                  },
                ),
              );
            },
          );
        },
      ),
    );
  }

  void _showPopupMenu(BuildContext context, Appointment appointment) async {
    final RenderBox? overlay =
        Overlay.of(context).context.findRenderObject() as RenderBox?;
    const RelativeRect positionData = RelativeRect.fromLTRB(
      100, // distance from the left
      100, // distance from the top
      100, // distance from the right
      100, // distance from the bottom
    );

    final List<PopupMenuEntry<String>> menuItems = [
      const PopupMenuItem<String>(
        value: 'Modifier',
        child: ListTile(
          leading: Icon(Icons.edit),
          title: Text('Modifier'),
        ),
      ),
      const PopupMenuItem<String>(
        value: 'Annuler',
        child: ListTile(
          leading: Icon(Icons.cancel),
          title: Text('Annuler'),
        ),
      ),
      const PopupMenuItem<String>(
        value: 'Atelier',
        child: ListTile(
          leading: Icon(Icons.build),
          title: Text('Atelier'),
        ),
      ),
      const PopupMenuItem<String>(
        value: 'Terminer',
        child: ListTile(
          leading: Icon(Icons.check_circle_outline),
          title: Text('Terminer'),
        ),
      ),
    ];

    final String? selectedAction = await showMenu(
      context: context,
      position: positionData,
      items: menuItems,
    );

    if (selectedAction != null) {
      switch (selectedAction) {
        case 'Modifier':
          _showEditAppointmentDialog(context, appointment);
          break;
        case 'Annuler':
          _moveToCollection(appointment, 'rdv_annule');
          break;
        case 'Atelier':
          _moveToCollection(appointment, 'Atelier');
          break;
        case 'Terminer':
          _moveToHistorique(appointment);
          break;
      }
    }
  }

  void _showEditAppointmentDialog(
      BuildContext context, Appointment appointment) {
    final nomClientController =
        TextEditingController(text: appointment.nomClient);
    final numeroTelephoneController =
        TextEditingController(text: appointment.numeroTelephone);
    final addressController = TextEditingController(text: appointment.address);
    final typeMachineController =
        TextEditingController(text: appointment.typeMachine);
    final panneController = TextEditingController(text: appointment.panne);

    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Modifier Rendez-vous'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nomClientController,
                decoration: const InputDecoration(labelText: 'Nom Client'),
              ),
              TextField(
                controller: numeroTelephoneController,
                decoration: const InputDecoration(labelText: 'Téléphone'),
              ),
              TextField(
                controller: addressController,
                decoration: const InputDecoration(labelText: 'Adresse'),
              ),
              TextField(
                controller: typeMachineController,
                decoration: const InputDecoration(labelText: 'Type Machine'),
              ),
              TextField(
                controller: panneController,
                decoration: const InputDecoration(labelText: 'panne'),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
              },
              child: const Text('Annuler'),
            ),
            ElevatedButton(
              onPressed: () {
                FirebaseFirestore.instance
                    .collection('rdv')
                    .doc(appointment.id)
                    .update({
                  'nom_client': nomClientController.text,
                  'numero_telephone': numeroTelephoneController.text,
                  'address': addressController.text,
                  'type_machine': typeMachineController.text,
                  'panne': panneController.text,
                }).then((_) {
                  Navigator.of(context).pop();
                });
              },
              child: const Text('Valider'),
            ),
          ],
        );
      },
    );
  }

  void _moveToCollection(Appointment appointment, String collectionName) {
    if (collectionName.isEmpty) {
      print('Error: Collection name is empty');
      return;
    }

    FirebaseFirestore.instance.runTransaction((transaction) async {
      final snapshot = await transaction.get(
          FirebaseFirestore.instance.collection('rdv').doc(appointment.id));
      transaction.delete(snapshot.reference);
      transaction.set(
          FirebaseFirestore.instance
              .collection(collectionName)
              .doc(appointment.id),
          snapshot.data()!);
    });
  }

  void _moveToHistorique(Appointment appointment) async {
    final querySnapshot = await FirebaseFirestore.instance
        .collection('clients')
        .where('numero_telephone', isEqualTo: appointment.numeroTelephone)
        .get();

    if (querySnapshot.docs.isNotEmpty) {
      final clientDoc = querySnapshot.docs.first;
      final clientId = clientDoc.id;

      FirebaseFirestore.instance.runTransaction((transaction) async {
        final snapshot = await transaction.get(
            FirebaseFirestore.instance.collection('rdv').doc(appointment.id));
        transaction.delete(snapshot.reference);
        transaction.set(
            FirebaseFirestore.instance
                .collection('clients')
                .doc(clientId)
                .collection('historique')
                .doc(appointment.id),
            snapshot.data()!);
      });
    } else {
      print('Client not found');
    }
  }
}

class Appointment {
  final String id;
  final String nomClient;
  final String numeroTelephone;
  final String address;
  final String typeMachine;
  final String panne;
  final Timestamp timestamp;

  Appointment({
    required this.id,
    required this.nomClient,
    required this.numeroTelephone,
    required this.address,
    required this.typeMachine,
    required this.panne,
    required this.timestamp,
  });

  factory Appointment.fromFirestore(Map<String, dynamic> data, String id) {
    return Appointment(
      id: id,
      nomClient: data.containsKey('nom_client')
          ? data['nom_client']
          : 'Nom non disponible',
      numeroTelephone: data.containsKey('numero_telephone')
          ? data['numero_telephone']
          : 'Téléphone non disponible',
      address: data.containsKey('address')
          ? data['address']
          : 'Adresse non disponible',
      typeMachine: data.containsKey('type_machine')
          ? data['type_machine']
          : 'Type de machine non disponible',
      panne: data.containsKey('panne') ? data['panne'] : 'panne non disponible',
      timestamp:
          data.containsKey('timestamp') ? data['timestamp'] : Timestamp.now(),
    );
  }
}
