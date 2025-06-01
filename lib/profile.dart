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
    initializeDateFormatting('fr_FR', null);
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance.collection('Atelier').snapshots(),
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

        if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.build, size: 48, color: Colors.grey),
                const SizedBox(height: 16),
                Text(
                  'Aucune machine en atelier',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    color: Colors.grey[600],
                  ),
                ),
              ],
            ),
          );
        }

        final machines = snapshot.data!.docs;
        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: machines.length,
          itemBuilder: (context, index) {
            final machine = machines[index].data() as Map<String, dynamic>;
            return RepairCard(
              machine: machine,
              machineId: machines[index].id,
              onComplete: () => _completeMachine(machines[index]),
            );
          },
        );
      },
    );
  }

  Future<void> _completeMachine(DocumentSnapshot machine) async {
    try {
      final batch = FirebaseFirestore.instance.batch();
      final machineData = machine.data() as Map<String, dynamic>;

      // 1. Ajouter à l'historique client
      final histRef = FirebaseFirestore.instance
          .collection('clients')
          .doc(machineData['numero_telephone'])
          .collection('historique')
          .doc();

      batch.set(histRef, {
        ...machineData,
        'date_entree': machineData['timestamp'],
        'date_sortie': FieldValue.serverTimestamp(),
      });

      // 2. Mettre à jour Qr-codes
      batch.update(
        FirebaseFirestore.instance.collection('Qr-codes').doc(machine.id),
        {
          'atelier': false,
          'date_sortie': FieldValue.serverTimestamp(),
        },
      );

      // 3. Mettre à jour History
      await FirebaseFirestore.instance
          .collection('Qr-codes')
          .doc(machine.id)
          .collection("History")
          .doc(machineData['uuid'].toString())
          .update({
        'atelier': false,
        'date_sortie': FieldValue.serverTimestamp(),
      });

      // 4. Supprimer de Atelier
      batch.delete(machine.reference);

      await batch.commit();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Réparation terminée et archivée !'),
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
  }
}

class RepairCard extends StatelessWidget {
  final Map<String, dynamic> machine;
  final String machineId;
  final VoidCallback onComplete;

  const RepairCard({
    super.key,
    required this.machine,
    required this.machineId,
    required this.onComplete,
  });

  @override
  Widget build(BuildContext context) {
    final timestamp = machine['timestamp'] as Timestamp?;
    final formattedDate = timestamp != null
        ? DateFormat('dd/MM/yyyy HH:mm', 'fr_FR').format(timestamp.toDate())
        : 'Date inconnue';

    final status = machine['statut'] ?? 'en_attente';
    final statusColor = _getStatusColor(status);
    final statusText = _getStatusText(status);

    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            decoration: BoxDecoration(
              color: statusColor.withOpacity(0.1),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
            ),
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Icon(Icons.build, color: statusColor),
                const SizedBox(width: 8),
                Text(
                  statusText,
                  style: TextStyle(
                    color: statusColor,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const Spacer(),
                Text(
                  formattedDate,
                  style: TextStyle(
                    color: Colors.grey[600],
                    fontSize: 14,
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  machine['nom_client'] ?? 'Client inconnu',
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 18,
                  ),
                ),
                const SizedBox(height: 16),
                _buildInfoRow(
                  icon: Icons.phone,
                  label: 'Téléphone',
                  value: machine['numero_telephone'] ?? 'Non renseigné',
                ),
                _buildInfoRow(
                  icon: Icons.build,
                  label: 'Appareil',
                  value: '${machine['type_machine'] ?? 'Non renseigné'} - ${machine['marque'] ?? ''}',
                ),
                _buildInfoRow(
                  icon: Icons.error_outline,
                  label: 'Panne',
                  value: machine['panne'] ?? 'Non renseignée',
                ),
                _buildInfoRow(
                  icon: Icons.engineering,
                  label: 'Réparation',
                  value: machine['reparation'] ?? 'En cours',
                ),
                if (machine['technicien'] != null)
                  _buildInfoRow(
                    icon: Icons.person,
                    label: 'Technicien',
                    value: machine['technicien'],
                  ),
              ],
            ),
          ),
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.all(8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () {
                    // TODO: Implémenter la modification
                  },
                  child: const Text('Modifier'),
                ),
                const SizedBox(width: 8),
                ElevatedButton.icon(
                  onPressed: onComplete,
                  icon: const Icon(Icons.check),
                  label: const Text('Terminer'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green,
                    foregroundColor: Colors.white,
                  ),
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
      padding: const EdgeInsets.only(bottom: 12),
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

  Color _getStatusColor(String status) {
    switch (status) {
      case 'en_cours':
        return Colors.orange;
      case 'termine':
        return Colors.green;
      case 'en_attente':
      default:
        return Colors.blue;
    }
  }

  String _getStatusText(String status) {
    switch (status) {
      case 'en_cours':
        return 'En cours de réparation';
      case 'termine':
        return 'Réparation terminée';
      case 'en_attente':
      default:
        return 'En attente de prise en charge';
    }
  }
}