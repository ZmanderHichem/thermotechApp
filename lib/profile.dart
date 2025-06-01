import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:intl/date_symbol_data_local.dart';

class AtelierPage extends StatefulWidget {
  const AtelierPage({super.key});

  @override
  _AtelierPageState createState() => _AtelierPageState();
}

class _AtelierPageState extends State<AtelierPage> {
  @override
  void initState() {
    super.initState();
    // Initialize the locale-specific data
    initializeDateFormatting('fr_FR', null);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Atelier Machines'),
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance.collection('Atelier').snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
            return const Center(child: Text('No machines found in the Atelier.'));
          }

          final machines = snapshot.data!.docs;

          return ListView.builder(
            itemCount: machines.length,
            itemBuilder: (context, index) {
              var machine = machines[index].data() as Map<String, dynamic>;

              // Debugging: print machine data and timestamp field
              print('Machine data: $machine');
              print('Timestamp field: ${machine['timestamp']}');

              // Extract fields with error handling
              String clientName =
                  machine['nom_client'] ?? 'No client name available';
              String phoneNumber =
                  machine['numero_telephone'] ?? 'No phone number available';
              String machineType =
                  machine['type_machine'] ?? 'No machine type available';
              String marque = machine['marque'] ?? 'No marque available';
              String panne = machine['panne'] ?? 'No panne available';
              String reparation = machine['reparation'] ?? 'No reparation available';
              String statut = machine['statut'] ?? 'en_attente';
              String technicien = machine['technicien'] ?? 'No technicien assigned';

              // Handle the possibility that 'timestamp' might be null or absent
              var timestampField = machine['timestamp'];
              String formattedDate;

              if (timestampField is Timestamp) {
                DateTime date = timestampField.toDate();
                formattedDate = DateFormat('yyyy-MM-dd HH:mm', 'fr_FR').format(date);
              } else if (timestampField is DateTime) {
                formattedDate =
                    DateFormat('yyyy-MM-dd HH:mm', 'fr_FR').format(timestampField);
              } else {
                formattedDate = 'No date available';
              }

              return Card(
                margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                child: ExpansionTile(
                  title: Text(
                    clientName,
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  subtitle: Text(
                    '$machineType - $marque\n'
                    'Entrée: $formattedDate',
                  ),
                  children: [
                    Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _buildInfoRow('Téléphone:', phoneNumber),
                          _buildInfoRow('Type Machine:', machineType),
                          _buildInfoRow('Marque:', marque),
                          _buildInfoRow('Panne:', panne),
                          _buildInfoRow('Réparation:', reparation),
                          _buildInfoRow('Statut:', statut),
                          _buildInfoRow('Technicien:', technicien),
                          _buildInfoRow('Date Entrée:', formattedDate),
                          const SizedBox(height: 16),
                          SizedBox(
                            width: double.infinity,
                            child: ElevatedButton(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.green,
                                padding: const EdgeInsets.symmetric(vertical: 12),
                              ),
                              onPressed: () async {
                                final batch = FirebaseFirestore.instance.batch();

                                // 1. Ajouter à l'historique client
                                final histRef = FirebaseFirestore.instance
                                    .collection('clients')
                                    .doc(machine['numero_telephone'])
                                    .collection('historique')
                                    .doc();

                                batch.set(histRef, {
                                  ...machine,
                                  'date_entree': machine['timestamp'],
                                  'date_sortie': FieldValue.serverTimestamp(),
                                });

                                // 2. Mettre à jour Qr-codes
                                batch.update(
                                    FirebaseFirestore.instance
                                        .collection('Qr-codes')
                                        .doc(machines[index].id),
                                    {
                                      'atelier': false,
                                      'date_sortie': FieldValue.serverTimestamp(),
                                    });

                                // 3. Mettre à jour History
                                FirebaseFirestore.instance
                                    .collection('Qr-codes')
                                    .doc(machines[index].id)
                                    .collection("History")
                                    .doc(machine['uuid'].toString())
                                    .update({
                                  'atelier': false,
                                  'date_sortie': FieldValue.serverTimestamp(),
                                });

                                // 4. Supprimer de Atelier
                                batch.delete(machines[index].reference);

                                try {
                                  await batch.commit();
                                  if (mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(
                                        content: Text('Réparation terminée et archivée!'),
                                        backgroundColor: Colors.green,
                                      ),
                                    );
                                  }
                                } catch (e) {
                                  if (mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                        content: Text('Erreur: ${e.toString()}'),
                                        backgroundColor: Colors.red,
                                      ),
                                    );
                                  }
                                }
                              },
                              child: const Text(
                                'Terminer la Réparation',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 100,
            child: Text(
              label,
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                color: Colors.grey,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(fontSize: 16),
            ),
          ),
        ],
      ),
    );
  }
}
