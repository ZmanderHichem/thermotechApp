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

class _RdvSuggererState extends State<RdvSuggerer> with SingleTickerProviderStateMixin {
  final CollectionReference _rdvSuggererCollection =
      FirebaseFirestore.instance.collection('rdv_suggerer');
  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );
    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeInOut),
    );
    _animationController.forward();
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder(
      stream: _rdvSuggererCollection.snapshots(),
      builder: (context, AsyncSnapshot<QuerySnapshot> snapshot) {
        if (snapshot.hasError) {
          return ErrorDisplay(error: snapshot.error.toString());
        }

        if (snapshot.connectionState == ConnectionState.waiting) {
          return const LoadingDisplay();
        }

        final documents = snapshot.data!.docs;

        if (documents.isEmpty) {
          return const EmptyStateDisplay();
        }

        return FutureBuilder(
          future: Future.wait(documents.map((doc) async {
            final recordsSnapshot = await doc.reference
                .collection('records')
                .orderBy('timestamp', descending: true)
                .get();
            final latestTimestamp = recordsSnapshot.docs.isNotEmpty
                ? recordsSnapshot.docs.first['timestamp']
                : null;
            return {
              'doc': doc,
              'latestTimestamp': latestTimestamp,
            };
          }).toList()),
          builder: (context, AsyncSnapshot<List<Map<String, dynamic>>> sortedSnapshot) {
            if (sortedSnapshot.hasError) {
              return ErrorDisplay(error: sortedSnapshot.error.toString());
            }

            if (sortedSnapshot.connectionState == ConnectionState.waiting) {
              return const LoadingDisplay();
            }

            final sortedDocuments = sortedSnapshot.data!..sort((a, b) {
              final aTimestamp = a['latestTimestamp'];
              final bTimestamp = b['latestTimestamp'];
              if (aTimestamp == null && bTimestamp == null) return 0;
              if (aTimestamp == null) return 1;
              if (bTimestamp == null) return -1;
              return bTimestamp.compareTo(aTimestamp);
            });

            return FadeTransition(
              opacity: _fadeAnimation,
              child: ListView.builder(
                padding: const EdgeInsets.all(16),
                itemCount: sortedDocuments.length,
                itemBuilder: (context, index) {
                  final doc = sortedDocuments[index]['doc'];
                  final latestTimestamp = sortedDocuments[index]['latestTimestamp'];
                  final contactName = doc['contactName'] ?? 'Nom introuvable';
                  final tel = doc['tel'];
                  final data = doc.data() as Map<String, dynamic>;
                  final note = data['note'] as String? ?? '';

                  return Hero(
                    tag: 'suggestion_${doc.id}',
                    child: SuggestionCard(
                      contactName: contactName,
                      phoneNumber: tel,
                      note: note,
                      latestTimestamp: latestTimestamp != null
                          ? DateTime.fromMillisecondsSinceEpoch(latestTimestamp)
                          : null,
                      onEdit: () => _editName(context, doc, contactName, tel),
                      onSaveNote: (newNote) => _saveNote(doc.reference, newNote),
                      onShowRecordings: () => _showRecordings(context, doc.reference),
                      onAddAppointment: () => _addAppointment(context, contactName, tel),
                      onDelete: () => _deleteDocument(context, doc, tel),
                    ),
                  );
                },
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _editName(BuildContext context, DocumentSnapshot doc,
      String currentName, String tel) async {
    final nameController = TextEditingController(text: currentName);
    return showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Modifier le nom'),
        content: TextField(
          controller: nameController,
          decoration: const InputDecoration(labelText: 'Nouveau nom'),
          autofocus: true,
          textCapitalization: TextCapitalization.words,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Annuler'),
          ),
          ElevatedButton(
            onPressed: () async {
              final newName = nameController.text.trim();
              if (newName.isNotEmpty) {
                try {
                  await FirebaseFirestore.instance.runTransaction((transaction) async {
                    transaction.update(doc.reference, {'contactName': newName});
                    final clientSnapshot = await FirebaseFirestore.instance
                        .collection('clients')
                        .where('numero_telephone', isEqualTo: tel)
                        .get();
                    if (clientSnapshot.docs.isNotEmpty) {
                      transaction.update(
                          clientSnapshot.docs.first.reference, {'nom_client': newName});
                    }
                  });
                  if (mounted) {
                    Navigator.pop(context);
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Nom modifié avec succès'),
                        behavior: SnackBarBehavior.floating,
                      ),
                    );
                  }
                } catch (e) {
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('Erreur: $e'),
                        backgroundColor: Colors.red,
                        behavior: SnackBarBehavior.floating,
                      ),
                    );
                  }
                }
              }
            },
            child: const Text('Enregistrer'),
          ),
        ],
      ),
    );
  }

  Future<void> _saveNote(DocumentReference docRef, String note) async {
    try {
      await docRef.update({'note': note.trim()});
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Note enregistrée'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erreur: $e'),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  Future<void> _showRecordings(
      BuildContext context, DocumentReference docRef) async {
    final recordsSnapshot = await docRef.collection('records').get();
    if (mounted) {
      showModalBottomSheet(
        context: context,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        builder: (context) => Container(
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
                child: recordsSnapshot.docs.isEmpty
                    ? const Center(
                        child: Text('Aucun enregistrement disponible'),
                      )
                    : ListView.builder(
                        itemCount: recordsSnapshot.docs.length,
                        itemBuilder: (context, index) {
                          final record = recordsSnapshot.docs[index];
                          return AudioPlayerTile(
                            url: record['url'],
                            timestamp: DateTime.fromMillisecondsSinceEpoch(
                                record['timestamp']),
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
      );
    }
  }

  void _addAppointment(BuildContext context, String name, String tel) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => AddRdvPage(name: name, tel: tel),
      ),
    );
  }

  Future<void> _deleteDocument(
      BuildContext context, DocumentSnapshot doc, String tel) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Confirmer la suppression'),
        content: const Text('Voulez-vous vraiment supprimer ce rendez-vous ?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Annuler'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            child: const Text('Supprimer'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        final querySnapshot = await FirebaseFirestore.instance
            .collection('rdv_suggerer')
            .where('tel', isEqualTo: tel)
            .get();

        for (var document in querySnapshot.docs) {
          final recordsSnapshot =
              await document.reference.collection('records').get();
          for (var record in recordsSnapshot.docs) {
            await FirebaseStorage.instance.refFromURL(record['url']).delete();
            await record.reference.delete();
          }
          await document.reference.delete();
        }

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Rendez-vous supprimé'),
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Erreur: $e'),
              backgroundColor: Colors.red,
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      }
    }
  }
}

class ErrorDisplay extends StatelessWidget {
  final String error;

  const ErrorDisplay({super.key, required this.error});

  @override
  Widget build(BuildContext context) {
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
            error,
            style: Theme.of(context).textTheme.bodyMedium,
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

class LoadingDisplay extends StatelessWidget {
  const LoadingDisplay({super.key});

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: CircularProgressIndicator(),
    );
  }
}

class EmptyStateDisplay extends StatelessWidget {
  const EmptyStateDisplay({super.key});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.calendar_today, size: 48, color: Colors.grey),
          const SizedBox(height: 16),
          Text(
            'Aucun rendez-vous suggéré',
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  color: Colors.grey[600],
                ),
          ),
          const SizedBox(height: 24),
          ElevatedButton.icon(
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => AddRdvPage(
                    name: 'Nom introuvable',
                    tel: 'tel introuvable',
                  ),
                ),
              );
            },
            icon: const Icon(Icons.add),
            label: const Text('Ajouter un rendez-vous'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Theme.of(context).primaryColor,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(
                horizontal: 24,
                vertical: 12,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class SuggestionCard extends StatelessWidget {
  final String contactName;
  final String phoneNumber;
  final String note;
  final DateTime? latestTimestamp;
  final VoidCallback onEdit;
  final Function(String) onSaveNote;
  final VoidCallback onShowRecordings;
  final VoidCallback onAddAppointment;
  final VoidCallback onDelete;

  const SuggestionCard({
    super.key,
    required this.contactName,
    required this.phoneNumber,
    required this.note,
    required this.latestTimestamp,
    required this.onEdit,
    required this.onSaveNote,
    required this.onShowRecordings,
    required this.onAddAppointment,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final noteController = TextEditingController(text: note);

    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ListTile(
            title: Row(
              children: [
                Expanded(
                  child: Text(
                    contactName,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 18,
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.edit),
                  onPressed: onEdit,
                  tooltip: 'Modifier le nom',
                ),
              ],
            ),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                InkWell(
                  onTap: () {
                    Clipboard.setData(ClipboardData(text: phoneNumber));
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Numéro copié dans le presse-papier'),
                        behavior: SnackBarBehavior.floating,
                      ),
                    );
                  },
                  child: Row(
                    children: [
                      const Icon(Icons.phone, size: 16),
                      const SizedBox(width: 8),
                      Text(phoneNumber),
                    ],
                  ),
                ),
                if (latestTimestamp != null) ...[
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      const Icon(Icons.access_time, size: 16),
                      const SizedBox(width: 8),
                      Text(
                        'Dernier enregistrement: ${_formatDate(latestTimestamp!)}',
                        style: TextStyle(color: Colors.grey[600]),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: TextField(
              controller: noteController,
              decoration: const InputDecoration(
                labelText: 'Note',
                border: OutlineInputBorder(),
              ),
              maxLines: 2,
            ),
          ),
          ButtonBar(
            alignment: MainAxisAlignment.spaceEvenly,
            children: [
              TextButton.icon(
                icon: const Icon(Icons.save),
                label: const Text('Enregistrer'),
                onPressed: () => onSaveNote(noteController.text),
              ),
              TextButton.icon(
                icon: const Icon(Icons.mic),
                label: const Text('Écouter'),
                onPressed: onShowRecordings,
              ),
            ],
          ),
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.all(8),
            child: Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    icon: const Icon(Icons.add),
                    label: const Text('Ajouter RDV'),
                    onPressed: onAddAppointment,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green,
                      foregroundColor: Colors.white,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: ElevatedButton.icon(
                    icon: const Icon(Icons.delete),
                    label: const Text('Supprimer'),
                    onPressed: onDelete,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.red,
                      foregroundColor: Colors.white,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _formatDate(DateTime date) {
    return '${date.day}/${date.month}/${date.year} ${date.hour}:${date.minute.toString().padLeft(2, '0')}';
  }
}