import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class AddRdvPage extends StatefulWidget {
  final String name;
  final String tel;

  const AddRdvPage({super.key, required this.name, required this.tel});

  @override
  _AddRdvPageState createState() => _AddRdvPageState();
}

class _AddRdvPageState extends State<AddRdvPage> {
  final TextEditingController addressController = TextEditingController();
  final TextEditingController panneController = TextEditingController();
  final TextEditingController clientNameController = TextEditingController();
  final TextEditingController clientTelController = TextEditingController(); // Added controller for phone number

  final List<String> deviceTypes = [
    'Réfrigérateur',
    'Machine à laver',
    'Lave-vaisselle',
    'Climatiseur',
    'Cafetière',
    'Robot',
  ];

  String? selectedDeviceType;

  Future<void> saveRdvToFirestore() async {
    final String clientName = widget.name == "Nom introuvable" ? clientNameController.text : widget.name;
    final String phoneNumber = widget.tel == "tel introuvable" ? clientTelController.text : widget.tel; // Updated phone number logic

    if (addressController.text.isNotEmpty &&
        selectedDeviceType != null &&
        panneController.text.isNotEmpty &&
        clientName.isNotEmpty &&
        phoneNumber.isNotEmpty) { // Added phone number validation

      // Recherche du client dans la collection "clients" par numéro de téléphone
      final DocumentReference clientRef =
          FirebaseFirestore.instance.collection('clients').doc(phoneNumber);

      final DocumentSnapshot clientSnapshot = await clientRef.get();

      if (!clientSnapshot.exists) {
        // Si le client n'existe pas, créez un nouveau document avec le num tel comme ID
        await clientRef.set({
          'nom_client': clientName,
          'numero_telephone': phoneNumber,
        });
        print('Nouveau client créé.');
      }

      // Enregistrement du RDV dans la collection "rdv"
      final Map<String, dynamic> rdvData = {
        'nom_client': clientName,
        'numero_telephone': phoneNumber,
        'address': addressController.text,
        'type_machine': selectedDeviceType,
        'panne': panneController.text,
        'timestamp': FieldValue.serverTimestamp(),
      };

      try {
        await FirebaseFirestore.instance.collection('rdv').add(rdvData);
        // Suppression du document de la collection "rdv_suggerer"
        await FirebaseFirestore.instance.collection('rdv_suggerer').doc(phoneNumber).delete();

        // Retour à la page "RdvSuggerer"
        Navigator.of(context).pop();
      } catch (e) {
        _showAlertDialog('Erreur', 'Erreur lors de l\'enregistrement du RDV.');
      }
    } else {
      _showAlertDialog('Erreur', 'Veuillez remplir tous les champs.');
    }
  }

  void _showAlertDialog(String title, String message) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text(title),
          content: Text(message),
          actions: [
            TextButton(
              child: const Text('OK'),
              onPressed: () {
                Navigator.of(context).pop();
              },
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Ajouter un RDV'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              
              if (widget.name == "Nom introuvable") ...[
                const Text('Nom du client:', style: TextStyle(fontWeight: FontWeight.bold),),
                const SizedBox(height: 16.0),
                TextField(
                  controller: clientNameController,
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                    labelText: 'Entrez le nom du client',
                  ),
                ),
              ] else ...[
                Text('Nom du client: ${widget.name}', style: const TextStyle(fontWeight: FontWeight.bold),),
              ],
              const SizedBox(height: 16.0),
              
              if (widget.tel == "tel introuvable") ...[
                const Text('Numéro de téléphone:', style: TextStyle(fontWeight: FontWeight.bold),),
                const SizedBox(height: 16.0),
                TextField(
                  controller: clientTelController,
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                    labelText: 'Entrez le numéro de téléphone',
                  ),
                ),
              ] else ...[
                Text('Numéro de téléphone: ${widget.tel}', style: const TextStyle(fontWeight: FontWeight.bold),),
              ],
              const SizedBox(height: 16.0),
              TextField(
                controller: addressController,
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  labelText: 'Adresse',
                ),
              ),
              const SizedBox(height: 16.0),
              DropdownButtonFormField<String>(
                value: selectedDeviceType,
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  labelText: 'Type d\'appareil',
                ),
                items: deviceTypes.map((String type) {
                  return DropdownMenuItem<String>(
                    value: type,
                    child: Text(type),
                  );
                }).toList(),
                onChanged: (String? newValue) {
                  setState(() {
                    selectedDeviceType = newValue;
                  });
                },
              ),
              const SizedBox(height: 16.0),
              TextField(
                controller: panneController,
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  labelText: 'Panne',
                ),
              ),
              const SizedBox(height: 24.0),
              Center(
                child: ElevatedButton(
                  onPressed: () async {
                    bool confirmSave = await showDialog(
                      context: context,
                      builder: (BuildContext context) {
                        return AlertDialog(
                          title: const Text('Confirm Save'),
                          content: const Text('Are you sure you want to save this appointment?'),
                          actions: [
                            TextButton(
                              onPressed: () {
                                Navigator.of(context).pop(false);
                              },
                              child: const Text('Cancel'),
                            ),
                            TextButton(
                              onPressed: () {
                                Navigator.of(context).pop(true);
                              },
                              child: const Text('Save'),
                            ),
                          ],
                        );
                      },
                    );

                    if (confirmSave) {
                      saveRdvToFirestore();
                    }
                  },
                  child: const Text('Confirmer'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
