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
  String _selectedFilter = 'all';
  String _searchQuery = '';
  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    initializeDateFormatting('fr_FR', null);
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Query<Map<String, dynamic>> _buildQuery() {
    Query<Map<String, dynamic>> query = FirebaseFirestore.instance.collection('Atelier');
    
    if (_selectedFilter != 'all') {
      query = query.where('statut', isEqualTo: _selectedFilter);
    }
    
    return query.orderBy('timestamp', descending: true);
  }

  bool _filterMachine(Map<String, dynamic> machine) {
    if (_searchQuery.isEmpty) return true;
    
    final searchLower = _searchQuery.toLowerCase();
    return machine['nom_client']?.toString().toLowerCase().contains(searchLower) == true ||
           machine['numero_telephone']?.toString().toLowerCase().contains(searchLower) == true ||
           machine['type_machine']?.toString().toLowerCase().contains(searchLower) == true ||
           machine['marque']?.toString().toLowerCase().contains(searchLower) == true;
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              TextField(
                controller: _searchController,
                decoration: InputDecoration(
                  hintText: 'Rechercher...',
                  prefixIcon: const Icon(Icons.search),
                  suffixIcon: _searchQuery.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          _searchController.clear();
                          setState(() => _searchQuery = '');
                        },
                      )
                    : null,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                onChanged: (value) => setState(() => _searchQuery = value),
              ),
              const SizedBox(height: 12),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    FilterChip(
                      label: const Text('Tous'),
                      selected: _selectedFilter == 'all',
                      onSelected: (selected) {
                        setState(() => _selectedFilter = 'all');
                      },
                    ),
                    const SizedBox(width: 8),
                    FilterChip(
                      label: const Text('En attente'),
                      selected: _selectedFilter == 'en_attente',
                      onSelected: (selected) {
                        setState(() => _selectedFilter = 'en_attente');
                      },
                    ),
                    const SizedBox(width: 8),
                    FilterChip(
                      label: const Text('En cours'),
                      selected: _selectedFilter == 'en_cours',
                      onSelected: (selected) {
                        setState(() => _selectedFilter = 'en_cours');
                      },
                    ),
                    const SizedBox(width: 8),
                    FilterChip(
                      label: const Text('Terminé'),
                      selected: _selectedFilter == 'termine',
                      onSelected: (selected) {
                        setState(() => _selectedFilter = 'termine');
                      },
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: StreamBuilder<QuerySnapshot>(
            stream: _buildQuery().snapshots(),
            builder: (context, snapshot) {
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

              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }

              final machines = snapshot.data!.docs
                  .map((doc) => {'id': doc.id, ...doc.data() as Map<String, dynamic>})
                  .where(_filterMachine)
                  .toList();

              if (machines.isEmpty) {
                return Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.build,
                        size: 64,
                        color: Colors.grey[400],
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'Aucune machine en atelier',
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          color: Colors.grey[600],
                        ),
                      ),
                      if (_searchQuery.isNotEmpty || _selectedFilter != 'all')
                        TextButton(
                          onPressed: () {
                            _searchController.clear();
                            setState(() {
                              _searchQuery = '';
                              _selectedFilter = 'all';
                            });
                          },
                          child: const Text('Réinitialiser les filtres'),
                        ),
                    ],
                  ),
                );
              }

              return ListView.builder(
                padding: const EdgeInsets.all(16),
                itemCount: machines.length,
                itemBuilder: (context, index) {
                  final machine = machines[index];
                  return RepairCard(
                    machine: machine,
                    onComplete: () => _completeMachine(machine['id']),
                    onUpdateStatus: (String newStatus) => _updateStatus(machine['id'], newStatus),
                    onAssignTechnician: (String technician) => _assignTechnician(machine['id'], technician),
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }

  Future<void> _completeMachine(String machineId) async {
    try {
      final machineDoc = await FirebaseFirestore.instance
          .collection('Atelier')
          .doc(machineId)
          .get();
      
      if (!machineDoc.exists) {
        throw Exception('Machine non trouvée');
      }

      final machineData = machineDoc.data()!;
      final batch = FirebaseFirestore.instance.batch();

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
        FirebaseFirestore.instance.collection('Qr-codes').doc(machineId),
        {
          'atelier': false,
          'date_sortie': FieldValue.serverTimestamp(),
        },
      );

      // 3. Mettre à jour History
      await FirebaseFirestore.instance
          .collection('Qr-codes')
          .doc(machineId)
          .collection("History")
          .doc(machineData['uuid'].toString())
          .update({
        'atelier': false,
        'date_sortie': FieldValue.serverTimestamp(),
      });

      // 4. Supprimer de Atelier
      batch.delete(machineDoc.reference);

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

  Future<void> _updateStatus(String machineId, String newStatus) async {
    try {
      await FirebaseFirestore.instance
          .collection('Atelier')
          .doc(machineId)
          .update({'statut': newStatus});

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Statut mis à jour'),
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

  Future<void> _assignTechnician(String machineId, String technician) async {
    try {
      await FirebaseFirestore.instance
          .collection('Atelier')
          .doc(machineId)
          .update({'technicien': technician});

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Technicien assigné'),
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
  final VoidCallback onComplete;
  final Function(String) onUpdateStatus;
  final Function(String) onAssignTechnician;

  const RepairCard({
    super.key,
    required this.machine,
    required this.onComplete,
    required this.onUpdateStatus,
    required this.onAssignTechnician,
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
                const SizedBox(width: 8),
                PopupMenuButton<String>(
                  icon: const Icon(Icons.more_vert),
                  onSelected: (value) {
                    switch (value) {
                      case 'status':
                        _showStatusDialog(context);
                        break;
                      case 'technician':
                        _showTechnicianDialog(context);
                        break;
                      case 'complete':
                        _showCompleteDialog(context);
                        break;
                    }
                  },
                  itemBuilder: (context) => [
                    const PopupMenuItem(
                      value: 'status',
                      child: Row(
                        children: [
                          Icon(Icons.update),
                          SizedBox(width: 8),
                          Text('Changer le statut'),
                        ],
                      ),
                    ),
                    const PopupMenuItem(
                      value: 'technician',
                      child: Row(
                        children: [
                          Icon(Icons.person),
                          SizedBox(width: 8),
                          Text('Assigner un technicien'),
                        ],
                      ),
                    ),
                    const PopupMenuItem(
                      value: 'complete',
                      child: Row(
                        children: [
                          Icon(Icons.check_circle),
                          SizedBox(width: 8),
                          Text('Terminer la réparation'),
                        ],
                      ),
                    ),
                  ],
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
        ],
      ),
    );
  }

  void _showStatusDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Changer le statut'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.hourglass_empty),
              title: const Text('En attente'),
              onTap: () {
                onUpdateStatus('en_attente');
                Navigator.pop(context);
              },
            ),
            ListTile(
              leading: const Icon(Icons.build),
              title: const Text('En cours'),
              onTap: () {
                onUpdateStatus('en_cours');
                Navigator.pop(context);
              },
            ),
            ListTile(
              leading: const Icon(Icons.check_circle),
              title: const Text('Terminé'),
              onTap: () {
                onUpdateStatus('termine');
                Navigator.pop(context);
              },
            ),
          ],
        ),
      ),
    );
  }

  void _showTechnicianDialog(BuildContext context) {
    final technicienController = TextEditingController();
    
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Assigner un technicien'),
        content: TextField(
          controller: technicienController,
          decoration: const InputDecoration(
            labelText: 'Nom du technicien',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Annuler'),
          ),
          ElevatedButton(
            onPressed: () {
              if (technicienController.text.isNotEmpty) {
                onAssignTechnician(technicienController.text);
                Navigator.pop(context);
              }
            },
            child: const Text('Assigner'),
          ),
        ],
      ),
    );
  }

  void _showCompleteDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Terminer la réparation'),
        content: const Text('Êtes-vous sûr de vouloir terminer cette réparation ?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Annuler'),
          ),
          ElevatedButton(
            onPressed: () {
              onComplete();
              Navigator.pop(context);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.green,
              foregroundColor: Colors.white,
            ),
            child: const Text('Terminer'),
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