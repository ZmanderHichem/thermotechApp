import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:saadoun/utils/audioPlayer.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:intl/intl.dart';

class ClientSearchPage extends StatefulWidget {
  const ClientSearchPage({super.key});

  @override
  _ClientSearchPageState createState() => _ClientSearchPageState();
}

class _ClientSearchPageState extends State<ClientSearchPage> {
  final TextEditingController _searchController = TextEditingController();
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final AudioPlayer _audioPlayer = AudioPlayer();
  bool _isSearching = false;

  @override
  void dispose() {
    _audioPlayer.dispose();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _makePhoneCall(String phoneNumber) async {
    final Uri phoneUri = Uri(scheme: 'tel', path: phoneNumber);
    if (await canLaunchUrl(phoneUri)) {
      await launchUrl(phoneUri);
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Impossible de lancer l\'appel'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  void _showRecordings(List<QueryDocumentSnapshot> records) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return Container(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Enregistrements',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 16),
              Expanded(
                child: ListView.builder(
                  itemCount: records.length,
                  itemBuilder: (context, index) {
                    final record = records[index];
                    final timestamp = DateTime.fromMillisecondsSinceEpoch(
                      record['timestamp'],
                    );
                    return AudioPlayerTile(
                      url: record['url'],
                      timestamp: timestamp,
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  void _showHistory(List<QueryDocumentSnapshot> history) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Historique des Réparations'),
          content: SizedBox(
            width: double.maxFinite,
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: history.length,
              itemBuilder: (context, index) {
                final data = history[index].data() as Map<String, dynamic>;
                final dateEntree = data['date_entree'] as Timestamp?;
                final dateSortie = data['date_sortie'] as Timestamp?;

                return Card(
                  margin: const EdgeInsets.only(bottom: 8),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Appareil: ${data['type_machine'] ?? 'N/A'}',
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                        ),
                        const SizedBox(height: 8),
                        _buildHistoryInfo('Marque', data['marque']),
                        _buildHistoryInfo('Panne', data['panne']),
                        _buildHistoryInfo('Réparation', data['reparation']),
                        if (dateEntree != null)
                          _buildHistoryDate(
                            'Entrée',
                            dateEntree.toDate(),
                            Colors.blue,
                          ),
                        if (dateSortie != null)
                          _buildHistoryDate(
                            'Sortie',
                            dateSortie.toDate(),
                            Colors.green,
                          ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Fermer'),
            ),
          ],
        );
      },
    );
  }

  Widget _buildHistoryInfo(String label, String? value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: RichText(
        text: TextSpan(
          style: const TextStyle(color: Colors.black87),
          children: [
            TextSpan(
              text: '$label: ',
              style: const TextStyle(
                fontWeight: FontWeight.w500,
                color: Colors.black54,
              ),
            ),
            TextSpan(text: value ?? 'N/A'),
          ],
        ),
      ),
    );
  }

  Widget _buildHistoryDate(String label, DateTime date, Color color) {
    return Container(
      margin: const EdgeInsets.only(top: 4),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        '$label: ${DateFormat('dd/MM/yyyy HH:mm').format(date)}',
        style: TextStyle(
          color: color,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: TextField(
            controller: _searchController,
            decoration: InputDecoration(
              labelText: 'Numéro de téléphone',
              hintText: 'Entrez le numéro du client',
              prefixIcon: const Icon(Icons.search),
              suffixIcon: _searchController.text.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.clear),
                      onPressed: () {
                        setState(() {
                          _searchController.clear();
                          _isSearching = false;
                        });
                      },
                    )
                  : null,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            keyboardType: TextInputType.phone,
            onChanged: (value) {
              setState(() {
                _isSearching = value.isNotEmpty;
              });
            },
          ),
        ),
        Expanded(
          child: !_isSearching
              ? const Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.search,
                        size: 64,
                        color: Colors.grey,
                      ),
                      SizedBox(height: 16),
                      Text(
                        'Recherchez un client par son numéro',
                        style: TextStyle(
                          fontSize: 16,
                          color: Colors.grey,
                        ),
                      ),
                    ],
                  ),
                )
              : StreamBuilder<QuerySnapshot>(
                  stream: _firestore
                      .collection('clients')
                      .where('numero_telephone',
                          isEqualTo: _searchController.text)
                      .snapshots(),
                  builder: (context, snapshot) {
                    if (snapshot.hasError) {
                      return Center(
                        child: Text('Erreur: ${snapshot.error}'),
                      );
                    }

                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return const Center(
                        child: CircularProgressIndicator(),
                      );
                    }

                    if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                      return const Center(
                        child: Text('Aucun client trouvé'),
                      );
                    }

                    return ListView.builder(
                      itemCount: snapshot.data!.docs.length,
                      itemBuilder: (context, index) {
                        final client = snapshot.data!.docs[index];
                        return Card(
                          margin: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 8,
                          ),
                          child: Column(
                            children: [
                              ListTile(
                                leading: const CircleAvatar(
                                  child: Icon(Icons.person),
                                ),
                                title: Text(
                                  client['nom_client'],
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                subtitle: Text(client['numero_telephone']),
                                trailing: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    IconButton(
                                      icon: const Icon(Icons.history),
                                      onPressed: () async {
                                        final historySnapshot = await client
                                            .reference
                                            .collection('historique')
                                            .get();
                                        if (mounted) {
                                          _showHistory(historySnapshot.docs);
                                        }
                                      },
                                    ),
                                    IconButton(
                                      icon: const Icon(Icons.phone),
                                      onPressed: () => _makePhoneCall(
                                          client['numero_telephone']),
                                    ),
                                  ],
                                ),
                              ),
                              const Divider(height: 1),
                              Padding(
                                padding: const EdgeInsets.all(8.0),
                                child: Row(
                                  children: [
                                    Expanded(
                                      child: OutlinedButton.icon(
                                        icon: const Icon(Icons.record_voice_over),
                                        label: const Text('Enregistrements'),
                                        onPressed: () async {
                                          final recordsSnapshot = await client
                                              .reference
                                              .collection('records')
                                              .get();
                                          if (mounted) {
                                            _showRecordings(recordsSnapshot.docs);
                                          }
                                        },
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
        ),
      ],
    );
  }
}