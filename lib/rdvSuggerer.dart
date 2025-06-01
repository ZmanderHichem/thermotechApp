import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:saadoun/history.dart';
import 'utils/audioPlayer.dart';

class RdvSuggerer extends StatefulWidget {
  const RdvSuggerer({super.key});

  @override
  _RdvSuggererState createState() => _RdvSuggererState();
}

class _RdvSuggererState extends State<RdvSuggerer> {
  final CollectionReference _rdvSuggererCollection = FirebaseFirestore.instance.collection('rdv_suggerer');

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Rdv Suggerer'),
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => AddRdvPage(name: 'Nom introuvable', tel: 'tel introuvable')),
              );
            },
          ),
        ],
      ),
      body: StreamBuilder(
        stream: _rdvSuggererCollection.snapshots(),
        builder: (context, AsyncSnapshot<QuerySnapshot> snapshot) {
          if (snapshot.hasError) {
            return Center(child: Text('Error: ${snapshot.error}'));
          }
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          final documents = snapshot.data!.docs;

          return FutureBuilder(
            future: Future.wait(documents.map((doc) async {
              final recordsSnapshot = await doc.reference.collection('records').orderBy('timestamp', descending: true).get();
              final latestTimestamp = recordsSnapshot.docs.isNotEmpty ? recordsSnapshot.docs.first['timestamp'] : null;
              return {
                'doc': doc,
                'latestTimestamp': latestTimestamp,
              };
            }).toList()),
            builder: (context, AsyncSnapshot<List<Map<String, dynamic>>> snapshot) {
              if (snapshot.hasError) {
                return Center(child: Text('Error: ${snapshot.error}'));
              }
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }

              final sortedDocuments = snapshot.data!..sort((a, b) {
                final aTimestamp = a['latestTimestamp'];
                final bTimestamp = b['latestTimestamp'];
                if (aTimestamp == null && bTimestamp == null) return 0;
                if (aTimestamp == null) return 1;
                if (bTimestamp == null) return -1;
                return bTimestamp.compareTo(aTimestamp);
              });

              return ListView.builder(
                itemCount: sortedDocuments.length,
                itemBuilder: (context, index) {
                  final doc = sortedDocuments[index]['doc'];
                  final latestTimestamp = sortedDocuments[index]['latestTimestamp'];
                  final contactName = doc['contactName'] ?? 'Nom introuvable';
                  final tel = doc['tel'];
                  final data = doc.data() as Map<String, dynamic>;
                  final note = data.containsKey('note') ? data['note'] : '';

                  TextEditingController noteController = TextEditingController(text: note);

                  return Card(
                    child: Column(
                      children: [
                        ListTile(
                          title: Row(
                            children: [
                              Text(contactName),
                              IconButton(
                                icon: const Icon(Icons.edit),
                                onPressed: () {
                                  TextEditingController nameController = TextEditingController(text: contactName);
                                  showDialog(
                                    context: context,
                                    builder: (context) {
                                      return AlertDialog(
                                        title: const Text('Modifier le nom'),
                                        content: TextField(
                                          controller: nameController,
                                          decoration: const InputDecoration(labelText: 'Nouveau nom'),
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
                                              String newName = nameController.text;
                                              if (newName.isNotEmpty) {
                                                FirebaseFirestore.instance.runTransaction((transaction) async {
                                                  DocumentSnapshot freshSnap = await transaction.get(doc.reference);
                                                  transaction.update(freshSnap.reference, {'contactName': newName});
                                                  QuerySnapshot clientSnapshot = await FirebaseFirestore.instance
                                                      .collection('clients')
                                                      .where('numero_telephone', isEqualTo: tel)
                                                      .get();
                                                  if (clientSnapshot.docs.isNotEmpty) {
                                                    DocumentSnapshot clientDoc = clientSnapshot.docs.first;
                                                    transaction.update(clientDoc.reference, {'nom_client': newName});
                                                  }
                                                }).then((_) {
                                                  Navigator.of(context).pop();
                                                });
                                              }
                                            },
                                            child: const Text('Valider'),
                                          ),
                                        ],
                                      );
                                    },
                                  );
                                },
                              ),
                            ],
                          ),
                          subtitle: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              GestureDetector(
                                onTap: () {
                                  Clipboard.setData(ClipboardData(text: tel));
                                },
                                child: Text(tel),
                              ),
                              if (latestTimestamp != null)
                                Text('Dernier enregistrement: ${DateTime.fromMillisecondsSinceEpoch(latestTimestamp).toString()}'),
                              TextField(
                                controller: noteController,
                                decoration: const InputDecoration(labelText: 'Note'),
                              ),
                              ElevatedButton(
                                style: ElevatedButton.styleFrom(backgroundColor: Colors.orange),
                                onPressed: () {
                                  String note = noteController.text;
                                  if (note.isNotEmpty) {
                                    FirebaseFirestore.instance.runTransaction((transaction) async {
                                      DocumentSnapshot freshSnap = await transaction.get(doc.reference);
                                      transaction.update(freshSnap.reference, {'note': note});
                                    });
                                  }
                                },
                                child: const Text('Enregistrer Note',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                ),
                                ),
                              ),
                            ],
                          ),
                          trailing: IconButton(
                            icon: const Icon(Icons.audiotrack),
                            onPressed: () {
                              showModalBottomSheet(
                                context: context,
                                builder: (context) {
                                  return FutureBuilder(
                                    future: doc.reference.collection('records').get(),
                                    builder: (context, AsyncSnapshot<QuerySnapshot> snapshot) {
                                      if (snapshot.hasError) {
                                        return Center(child: Text('Error: ${snapshot.error}'));
                                      }
                                      if (snapshot.connectionState == ConnectionState.waiting) {
                                        return const Center(child: CircularProgressIndicator());
                                      }

                                      final records = snapshot.data!.docs;

                                      return ListView.builder(
                                        itemCount: records.length,
                                        itemBuilder: (context, index) {
                                          final record = records[index];

                                          return AudioPlayerTile(
                                            url: record['url'],
                                            timestamp: DateTime.fromMillisecondsSinceEpoch(record['timestamp']),
                                          );
                                        },
                                      );
                                    },
                                  );
                                },
                              );
                            },
                          ),
                        ),
                        OverflowBar(
                          children: [
                            ElevatedButton(
                              style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
                              onPressed: () {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (context) => AddRdvPage(
                                      name: contactName,
                                      tel: tel,
                                    ),
                                  ),
                                );
                              },
                              child: const Text(
                                'Ajouter',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                            ElevatedButton(
                              style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                              onPressed: () async {
                                bool confirmDelete = await showDialog(
                                  context: context,
                                  builder: (BuildContext context) {
                                    return AlertDialog(
                                      title: const Text('Confirm Deletion'),
                                      content: const Text('Are you sure you want to delete this item?'),
                                      actions: [
                                        TextButton(
                                          onPressed: () {
                                            Navigator.of(context).pop(false);
                                          },
                                          child: const Text('Cancel'),
                                        ),
                                        TextButton(
                                          style: TextButton.styleFrom(
                                            backgroundColor: Colors.red,
                                          ),
                                          onPressed: () {
                                            Navigator.of(context).pop(true);
                                          },
                                          child: const  Text('Supprimer',
                                          style: TextStyle(
                                            color: Colors.white,
                                            fontWeight: FontWeight.bold,
                                          ),
                                          ),
                                        ),
                                      ],
                                    );
                                  },
                                );

                                if (confirmDelete) {
                                  final querySnapshot = await FirebaseFirestore.instance
                                      .collection('rdv_suggerer')
                                      .where('tel', isEqualTo: doc['tel'])
                                      .get();
                                  for (var document in querySnapshot.docs) {
                                    // Fetch records subcollection
                                    final recordsSnapshot = await document.reference.collection('records').get();
                                    for (var record in recordsSnapshot.docs) {
                                      // Delete audio file from storage
                                      await FirebaseStorage.instance.refFromURL(record['url']).delete();
                                      // Delete record document
                                      await record.reference.delete();
                                    }
                                    // Delete main document
                                    await document.reference.delete();
                                  }
                                }
                              },
                              child: const Text('Suprimer',
                              style: TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  );
                },
              );
            },
          );
        },
      ),
    );
  }
}