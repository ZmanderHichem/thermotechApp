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
  final AudioPlayer _audioPlayer = AudioPlayer(); // Add this line

  @override
  void dispose() {
    _audioPlayer.dispose(); // Dispose the audio player
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Search Clients'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(8.0),
        child: Column(
          children: <Widget>[
            TextField(
              controller: _searchController,
              decoration: const InputDecoration(
                labelText: 'Enter Client Phone Number',
                border: OutlineInputBorder(),
              ),
              onChanged: (value) {
                setState(() {});
              },
            ),
            const SizedBox(height: 20),
            Expanded(
              child: StreamBuilder<QuerySnapshot>(
                stream: _firestore
                    .collection('clients')
                    .where('numero_telephone',
                        isEqualTo: _searchController.text)
                    .snapshots(),
                builder: (context, snapshot) {
                  if (!snapshot.hasData) {
                    return const Center(child: CircularProgressIndicator());
                  }

                  final clients = snapshot.data!.docs;
                  return ListView.builder(
                    itemCount: clients.length,
                    itemBuilder: (context, index) {
                      final client = clients[index];
                      return Container(
                        child: ListTile(
                          title: Text(client['nom_client']), // Client nom_client
                          subtitle: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('Phone Number: ${client['numero_telephone']}'),
                              Wrap(
                                spacing: 8, // Space between buttons
                                children: [
                                  ElevatedButton(
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: Colors.orange, 
                                      foregroundColor: Colors.white,
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(10),
                                      ),
                                      padding: const EdgeInsets.symmetric(horizontal: 10,),
                                      textStyle: const TextStyle(fontSize: 16),
                                    ),
                                    onPressed: () async {
                                      final QuerySnapshot recordsSnapshot = await _firestore
                                          .collection('clients')
                                          .doc(client['numero_telephone'])
                                          .collection('records')
                                          .get();
                                      showDialog(
                                        context: context,
                                        builder: (BuildContext context) {
                                          return AlertDialog(
                                            title: const Text('Enregistrements du client'),
                                            content: SingleChildScrollView(
                                              child: Column(
                                                children: recordsSnapshot.docs.map((doc) {
                                                  final timestamp = (doc['timestamp']);
                                                  final date = DateTime.fromMillisecondsSinceEpoch(timestamp);

                                                  return AudioPlayerTile(
                                                    url: doc['url'],
                                                    timestamp: date,
                                                  );
                                                }).toList(),
                                              ),
                                            ),
                                          );
                                        },
                                      );
                                    },
                                    child: const Text('Voir enregistrements'),
                                  ),
                                  ElevatedButton(
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: Colors.green, 
                                      foregroundColor: Colors.white,
                                      
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(10),
                                      ),
                                      padding: const EdgeInsets.symmetric(horizontal: 30),
                                      textStyle: const TextStyle(fontSize: 16),

                                    ),
                                    onPressed: () {
                                      final phoneNumber = client['numero_telephone'];
                                      final Uri phoneUri = Uri(scheme: 'tel', path: phoneNumber);
                                      print(phoneUri);
                                      print(phoneNumber);
                                      launchUrl(phoneUri);
                                    },
                                    child: const Text('Appeler'),
                                  ),
                                ],
                              ),
                            ],
                          ),
                          onTap: () async {
                            final QuerySnapshot historySnapshot = await _firestore
                                .collection('clients')
                                .doc(client['numero_telephone'])
                                .collection('historique')
                                .get();
                            if (historySnapshot.docs.isEmpty) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('No history found for this client'),
                                ),
                              );
                            } else {
                              showDialog(
                                context: context,
                                builder: (BuildContext context) {
                                  return AlertDialog(
                                    title: const Text('Historique des Réparations'),
                                    content: SingleChildScrollView(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: historySnapshot.docs.map((doc) {
                                          final data = doc.data() as Map<String, dynamic>;
                                          final dateEntree = data['date_entree'] as Timestamp?;
                                          final dateSortie = data['date_sortie'] as Timestamp?;
                                          
                                          return Card(
                                            margin: const EdgeInsets.only(bottom: 8),
                                            child: Padding(
                                              padding: const EdgeInsets.all(8.0),
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
                                                  const SizedBox(height: 4),
                                                  Text('Marque: ${data['marque'] ?? 'N/A'}'),
                                                  Text('Panne: ${data['panne'] ?? 'N/A'}'),
                                                  Text('Réparation: ${data['reparation'] ?? 'N/A'}'),
                                                  if (dateEntree != null)
                                                    Text(
                                                      'Entrée: ${DateFormat('dd/MM/yyyy HH:mm').format(dateEntree.toDate())}',
                                                      style: TextStyle(color: Colors.grey[600]),
                                                    ),
                                                  if (dateSortie != null)
                                                    Text(
                                                      'Sortie: ${DateFormat('dd/MM/yyyy HH:mm').format(dateSortie.toDate())}',
                                                      style: TextStyle(color: Colors.grey[600]),
                                                    ),
                                                ],
                                              ),
                                            ),
                                          );
                                        }).toList(),
                                      ),
                                    ),
                                    actions: <Widget>[
                                      TextButton(
                                        child: const Text('Fermer'),
                                        onPressed: () {
                                          Navigator.of(context).pop();
                                        },
                                      ),
                                    ],
                                  );
                                },
                              );
                            }
                          },
                        ),
                      );
                    },
                  );
                }
              ),
            ),
          ],
        ),
      ),
    );
  }
}


