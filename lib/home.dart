import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';

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
    return FirebaseFirestore.instance.collection('rdv').snapshots().map((snapshot) {
      return snapshot.docs.map((doc) {
        final data = doc.data();
        return Appointment.fromFirestore(data, doc.id);
      }).toList();
    });
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<Appointment>>(
      stream: _appointmentsStream,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        if (snapshot.hasError) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.error_outline, size: 48, color: Colors.red),
                const SizedBox(height: 16),
                Text(
                  'Une erreur est survenue',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 8),
                Text(
                  snapshot.error.toString(),
                  style: Theme.of(context).textTheme.bodyMedium,
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          );
        }

        final appointments = snapshot.data ?? [];

        if (appointments.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.calendar_today, size: 48, color: Colors.grey),
                const SizedBox(height: 16),
                Text(
                  'Aucun rendez-vous',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    color: Colors.grey[600],
                  ),
                ),
              ],
            ),
          );
        }

        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: appointments.length,
          itemBuilder: (context, index) {
            final appointment = appointments[index];
            return AppointmentCard(
              appointment: appointment,
              onEdit: () => _showEditAppointmentDialog(context, appointment),
              onCancel: () => _moveToCollection(appointment, 'rdv_annule'),
              onWorkshop: () => _moveToCollection(appointment, 'Atelier'),
              onComplete: () => _moveToHistorique(appointment),
            );
          },
        );
      },
    );
  }

  Future<void> _showEditAppointmentDialog(BuildContext context, Appointment appointment) async {
    final nomClientController = TextEditingController(text: appointment.nomClient);
    final numeroTelephoneController = TextEditingController(text: appointment.numeroTelephone);
    final addressController = TextEditingController(text: appointment.address);
    final typeMachineController = TextEditingController(text: appointment.typeMachine);
    final panneController = TextEditingController(text: appointment.panne);

    return showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Modifier le rendez-vous'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: nomClientController,
                decoration: const InputDecoration(labelText: 'Nom du client'),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: numeroTelephoneController,
                decoration: const InputDecoration(labelText: 'Téléphone'),
                keyboardType: TextInputType.phone,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: addressController,
                decoration: const InputDecoration(labelText: 'Adresse'),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: typeMachineController,
                decoration: const InputDecoration(labelText: 'Type d\'appareil'),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: panneController,
                decoration: const InputDecoration(labelText: 'Description de la panne'),
                maxLines: 3,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Annuler'),
          ),
          ElevatedButton(
            onPressed: () async {
              try {
                await FirebaseFirestore.instance
                    .collection('rdv')
                    .doc(appointment.id)
                    .update({
                  'nom_client': nomClientController.text,
                  'numero_telephone': numeroTelephoneController.text,
                  'address': addressController.text,
                  'type_machine': typeMachineController.text,
                  'panne': panneController.text,
                });
                if (mounted) {
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Rendez-vous modifié avec succès'),
                      backgroundColor: Colors.green,
                    ),
                  );
                }
              } catch (e) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('Erreur: ${e.toString()}'),
                    backgroundColor: Colors.red,
                  ),
                );
              }
            },
            child: const Text('Enregistrer'),
          ),
        ],
      ),
    );
  }

  Future<void> _moveToCollection(Appointment appointment, String collectionName) async {
    try {
      final batch = FirebaseFirestore.instance.batch();
      final snapshot = await FirebaseFirestore.instance
          .collection('rdv')
          .doc(appointment.id)
          .get();

      if (snapshot.exists) {
        batch.delete(snapshot.reference);
        batch.set(
          FirebaseFirestore.instance.collection(collectionName).doc(appointment.id),
          snapshot.data()!,
        );
        await batch.commit();

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                collectionName == 'rdv_annule'
                    ? 'Rendez-vous annulé'
                    : 'Déplacé vers l\'atelier',
              ),
              backgroundColor: Colors.green,
            ),
          );
        }
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Erreur: ${e.toString()}'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _moveToHistorique(Appointment appointment) async {
    try {
      final querySnapshot = await FirebaseFirestore.instance
          .collection('clients')
          .where('numero_telephone', isEqualTo: appointment.numeroTelephone)
          .get();

      if (querySnapshot.docs.isNotEmpty) {
        final clientDoc = querySnapshot.docs.first;
        final batch = FirebaseFirestore.instance.batch();

        final rdvDoc = await FirebaseFirestore.instance
            .collection('rdv')
            .doc(appointment.id)
            .get();

        if (rdvDoc.exists) {
          batch.delete(rdvDoc.reference);
          batch.set(
            clientDoc.reference.collection('historique').doc(appointment.id),
            rdvDoc.data()!,
          );
          await batch.commit();

          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Rendez-vous terminé et archivé'),
                backgroundColor: Colors.green,
              ),
            );
          }
        }
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Erreur: ${e.toString()}'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }
}

class AppointmentCard extends StatelessWidget {
  final Appointment appointment;
  final VoidCallback onEdit;
  final VoidCallback onCancel;
  final VoidCallback onWorkshop;
  final VoidCallback onComplete;

  const AppointmentCard({
    super.key,
    required this.appointment,
    required this.onEdit,
    required this.onCancel,
    required this.onWorkshop,
    required this.onComplete,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ListTile(
            title: Text(
              appointment.nomClient,
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 18,
              ),
            ),
            subtitle: Text(
              DateFormat('dd/MM/yyyy HH:mm').format(appointment.timestamp.toDate()),
              style: TextStyle(
                color: Colors.grey[600],
                fontSize: 14,
              ),
            ),
            trailing: PopupMenuButton<String>(
              icon: const Icon(Icons.more_vert),
              onSelected: (value) {
                switch (value) {
                  case 'edit':
                    onEdit();
                    break;
                  case 'cancel':
                    onCancel();
                    break;
                  case 'workshop':
                    onWorkshop();
                    break;
                  case 'complete':
                    onComplete();
                    break;
                }
              },
              itemBuilder: (context) => [
                const PopupMenuItem(
                  value: 'edit',
                  child: Row(
                    children: [
                      Icon(Icons.edit, size: 20),
                      SizedBox(width: 8),
                      Text('Modifier'),
                    ],
                  ),
                ),
                const PopupMenuItem(
                  value: 'cancel',
                  child: Row(
                    children: [
                      Icon(Icons.cancel, size: 20),
                      SizedBox(width: 8),
                      Text('Annuler'),
                    ],
                  ),
                ),
                const PopupMenuItem(
                  value: 'workshop',
                  child: Row(
                    children: [
                      Icon(Icons.build, size: 20),
                      SizedBox(width: 8),
                      Text('Atelier'),
                    ],
                  ),
                ),
                const PopupMenuItem(
                  value: 'complete',
                  child: Row(
                    children: [
                      Icon(Icons.check_circle, size: 20),
                      SizedBox(width: 8),
                      Text('Terminer'),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildInfoRow(
                  icon: Icons.phone,
                  label: 'Téléphone',
                  value: appointment.numeroTelephone,
                ),
                _buildInfoRow(
                  icon: Icons.location_on,
                  label: 'Adresse',
                  value: appointment.address,
                ),
                _buildInfoRow(
                  icon: Icons.build,
                  label: 'Appareil',
                  value: appointment.typeMachine,
                ),
                _buildInfoRow(
                  icon: Icons.error_outline,
                  label: 'Panne',
                  value: appointment.panne,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoRow({
    required IconData icon,
    required String label,
    required String value,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20, color: Colors.grey[600]),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    color: Colors.grey[600],
                    fontSize: 12,
                  ),
                ),
                Text(
                  value,
                  style: const TextStyle(fontSize: 16),
                ),
              ],
            ),
          ),
        ],
      ),
    );
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
      nomClient: data['nom_client'] ?? 'Nom non disponible',
      numeroTelephone: data['numero_telephone'] ?? 'Téléphone non disponible',
      address: data['address'] ?? 'Adresse non disponible',
      typeMachine: data['type_machine'] ?? 'Type de machine non disponible',
      panne: data['panne'] ?? 'Panne non disponible',
      timestamp: data['timestamp'] ?? Timestamp.now(),
    );
  }
}