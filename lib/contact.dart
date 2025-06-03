import 'package:flutter/material.dart';
import 'package:qr_code_scanner/qr_code_scanner.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';
import 'package:camera/camera.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:path_provider/path_provider.dart';
import 'package:image_picker/image_picker.dart';
import 'package:photo_view/photo_view.dart';
import 'package:path/path.dart' as path;
import 'dart:io';

class AdminDashboard extends StatefulWidget {
  const AdminDashboard({super.key});

  @override
  _AdminDashboardState createState() => _AdminDashboardState();
}

class _AdminDashboardState extends State<AdminDashboard> with WidgetsBindingObserver {
  final GlobalKey _qrKey = GlobalKey(debugLabel: 'QR');
  QRViewController? _qrController;
  bool _isProcessing = false;
  bool _hasImages = false;
  bool _isFlashOn = false;
  double _zoomLevel = 0.0;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseStorage _storage = FirebaseStorage.instance;
  List<CameraDescription>? _cameras;
  CameraController? _cameraController;
  int _selectedCameraIndex = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initializeCamera();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _qrController?.dispose();
    _cameraController?.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _qrController?.resumeCamera();
    } else {
      _qrController?.pauseCamera();
    }
  }

  Future<void> _initializeCamera() async {
    try {
      _cameras = await availableCameras();
      if (_cameras != null && _cameras!.isNotEmpty) {
        await _initializeCameraController(_cameras![0]);
      }
    } catch (e) {
      debugPrint('Error initializing camera: $e');
    }
  }

  Future<void> _initializeCameraController(CameraDescription camera) async {
    if (_cameraController != null) {
      await _cameraController!.dispose();
    }

    _cameraController = CameraController(
      camera,
      ResolutionPreset.max,
      enableAudio: false,
    );

    try {
      await _cameraController!.initialize();
      if (mounted) setState(() {});
    } catch (e) {
      debugPrint('Error initializing camera controller: $e');
    }
  }

  Future<void> _switchCamera() async {
    if (_cameras == null || _cameras!.isEmpty) return;

    _selectedCameraIndex = (_selectedCameraIndex + 1) % _cameras!.length;
    await _initializeCameraController(_cameras![_selectedCameraIndex]);
  }

  Future<void> _toggleFlash() async {
    try {
      if (_cameraController != null) {
        if (_isFlashOn) {
          await _cameraController!.setFlashMode(FlashMode.off);
        } else {
          await _cameraController!.setFlashMode(FlashMode.torch);
        }
        setState(() => _isFlashOn = !_isFlashOn);
      }
    } catch (e) {
      debugPrint('Error toggling flash: $e');
    }
  }

  Future<void> _setZoomLevel(double value) async {
    try {
      if (_cameraController != null) {
        await _cameraController!.setZoomLevel(value);
        setState(() => _zoomLevel = value);
      }
    } catch (e) {
      debugPrint('Error setting zoom level: $e');
    }
  }

  Future<void> _checkForImages(String qrCode) async {
    try {
      final ref = _storage.ref().child('repair_images/$qrCode');
      final result = await ref.listAll();
      setState(() => _hasImages = result.items.isNotEmpty);
    } catch (e) {
      setState(() => _hasImages = false);
    }
  }

  Future<void> _pickImage(String qrCode) async {
    final ImagePicker picker = ImagePicker();
    final XFile? image = await picker.pickImage(source: ImageSource.gallery);
    
    if (image != null) {
      await _saveImage(File(image.path), qrCode);
    }
  }

  Future<void> _saveImage(File imageFile, String qrCode) async {
    try {
      final fileName = path.basename(imageFile.path);
      final ref = _storage.ref().child('repair_images/$qrCode/$fileName');
      
      await ref.putFile(imageFile);
      final imageUrl = await ref.getDownloadURL();
      
      await _firestore.collection('Qr-codes').doc(qrCode).update({
        'images': FieldValue.arrayUnion([imageUrl])
      });

      await _checkForImages(qrCode);
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Image enregistrée avec succès')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erreur: ${e.toString()}')),
        );
      }
    }
  }

  Future<void> _showImages(String qrCode) async {
    try {
      final ref = _storage.ref().child('repair_images/$qrCode');
      final result = await ref.listAll();
      
      if (result.items.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Aucune image disponible')),
          );
        }
        return;
      }

      final imageUrls = await Future.wait(
        result.items.map((ref) => ref.getDownloadURL())
      );

      if (!mounted) return;

      await showDialog(
        context: context,
        builder: (context) => Dialog(
          backgroundColor: Colors.transparent,
          child: Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      const Text(
                        'Photos de la réparation',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const Spacer(),
                      IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: () => Navigator.pop(context),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1),
                Flexible(
                  child: GridView.builder(
                    shrinkWrap: true,
                    padding: const EdgeInsets.all(16),
                    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 3,
                      crossAxisSpacing: 8,
                      mainAxisSpacing: 8,
                    ),
                    itemCount: imageUrls.length,
                    itemBuilder: (context, index) {
                      return GestureDetector(
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => Scaffold(
                                backgroundColor: Colors.black,
                                appBar: AppBar(
                                  backgroundColor: Colors.black,
                                  foregroundColor: Colors.white,
                                ),
                                body: PhotoView(
                                  imageProvider: NetworkImage(imageUrls[index]),
                                  minScale: PhotoViewComputedScale.contained,
                                  maxScale: PhotoViewComputedScale.covered * 2,
                                ),
                              ),
                            ),
                          );
                        },
                        child: Hero(
                          tag: imageUrls[index],
                          child: Container(
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(8),
                              image: DecorationImage(
                                image: NetworkImage(imageUrls[index]),
                                fit: BoxFit.cover,
                              ),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erreur: ${e.toString()}')),
        );
      }
    }
  }

  void _onQRViewCreated(QRViewController controller) {
    _qrController = controller;
    controller.scannedDataStream.listen(_handleScan);
  }

  Future<void> _handleScan(Barcode scanData) async {
    if (_isProcessing || !mounted || scanData.code == null) return;
    setState(() => _isProcessing = true);
    await _qrController?.pauseCamera();

    try {
      final qrCode = scanData.code!;
      final doc = await _firestore.collection('Qr-codes').doc(qrCode).get();

      if (!doc.exists) {
        await _showNewRepairForm(context, qrCode);
      } else {
        if (doc.data()?['atelier'] == true) {
          await _showRepairDetails(doc);
        } else {
          await _showReturnOptions(context, qrCode);
        }
      }
      await _qrController?.resumeCamera();
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erreur: ${e.toString()}')),
      );
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  Future<void> _showNewRepairForm(BuildContext context, String qrCode) async {
    final phoneController = TextEditingController();
    final nameController = TextEditingController();
    final brandController = TextEditingController();
    final issueController = TextEditingController();
    final reparationController = TextEditingController();
    String? deviceType;
    bool isNewClient = true;
    bool isLoadingClient = false;

    Future<void> _searchClient(String phone) async {
      if (phone.length == 8) {
        setState(() => isLoadingClient = true);
        try {
          final doc = await _firestore.collection('clients').doc(phone).get();
          setState(() {
            isNewClient = !doc.exists;
            if (doc.exists) {
              nameController.text = doc['nom_client'] ?? '';
            } else {
              nameController.text = '';
            }
          });
        } catch (e) {
          print('Erreur recherche client: $e');
        } finally {
          setState(() => isLoadingClient = false);
        }
      }
    }

    await showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              title: const Text('Nouvelle Réparation'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextFormField(
                      controller: phoneController,
                      decoration: InputDecoration(
                        labelText: 'Téléphone (8 chiffres)',
                        suffixIcon: isLoadingClient
                            ? const CircularProgressIndicator()
                            : null,
                      ),
                      keyboardType: TextInputType.phone,
                      maxLength: 8,
                      onChanged: (value) async {
                        if (value.length == 8) {
                          await _searchClient(value);
                        } else {
                          setState(() => isNewClient = true);
                        }
                      },
                    ),
                    TextFormField(
                      controller: nameController,
                      decoration: InputDecoration(
                        labelText: 'Nom Client',
                        hintText: isNewClient ? 'Nouveau client' : null,
                      ),
                      enabled: isNewClient,
                    ),
                    const SizedBox(height: 16),
                    DropdownButtonFormField<String>(
                      value: deviceType,
                      decoration: const InputDecoration(
                        labelText: 'Type d\'appareil',
                        border: OutlineInputBorder(),
                      ),
                      items: [
                        'Réfrigérateur',
                        'Congélateur',
                        'Lave-linge',
                        'Lave-vaisselle',
                        'Sèche-linge',
                        'Lave-sèche-linge',
                        'Climatiseur',
                        'Micro-ondes',
                        'Four',
                        'Hotte aspirante',
                      ]
                          .map((e) => DropdownMenuItem(
                                value: e,
                                child: Text(e),
                              ))
                          .toList(),
                      onChanged: (value) => setState(() => deviceType = value),
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: brandController,
                      decoration: const InputDecoration(
                        labelText: 'Marque',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: issueController,
                      decoration: const InputDecoration(
                        labelText: 'Description de la panne',
                        border: OutlineInputBorder(),
                      ),
                      maxLines: 3,
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: reparationController,
                      decoration: const InputDecoration(
                        labelText: 'Réparation',
                        border: OutlineInputBorder(),
                        hintText: 'Décrire la réparation effectuée (optionnel)',
                      ),
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
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blue,
                    foregroundColor: Colors.white,
                  ),
                  onPressed: () async {
                    if (phoneController.text.length != 8 ||
                        nameController.text.isEmpty ||
                        deviceType == null) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                            content: Text(
                                'Veuillez remplir tous les champs obligatoires')),
                      );
                      return;
                    }

                    final repairData = {
                      'uuid': Uuid().v1(),
                      'numero_telephone': phoneController.text,
                      'nom_client': nameController.text,
                      'type_machine': deviceType,
                      'marque': brandController.text,
                      'panne': issueController.text,
                      'reparation': reparationController.text,
                      'atelier': true,
                      'timestamp': FieldValue.serverTimestamp(),
                    };

                    final batch = _firestore.batch();

                    batch.set(
                        _firestore
                            .collection('Qr-codes')
                            .doc(qrCode)
                            .collection("History")
                            .doc(repairData['uuid'].toString()),
                        repairData);
                    batch.set(_firestore.collection('Qr-codes').doc(qrCode),
                        repairData);
                    batch.set(_firestore.collection('Atelier').doc(qrCode), {
                      ...repairData,
                      'statut': 'en_attente',
                      'technicien': null,
                    });

                    batch.set(
                        _firestore
                            .collection('clients')
                            .doc(phoneController.text),
                        {
                          'nom_client': nameController.text,
                          'numero_telephone': phoneController.text,
                          'qr_associes': FieldValue.arrayUnion([qrCode]),
                        },
                        SetOptions(merge: true));

                    await batch.commit();
                    Navigator.pop(context);
                  },
                  child: const Text('Enregistrer'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _showRepairDetails(DocumentSnapshot doc) async {
    final data = doc.data() as Map<String, dynamic>?;
    final String qrCode = doc.id;
    final reparationController = TextEditingController(text: data?['reparation'] ?? '');
    final nomClientController = TextEditingController(text: data?['nom_client'] ?? '');
    final telephoneController = TextEditingController(text: data?['numero_telephone'] ?? '');
    final typeMachineController = TextEditingController(text: data?['type_machine'] ?? '');
    final marqueController = TextEditingController(text: data?['marque'] ?? '');
    final panneController = TextEditingController(text: data?['panne'] ?? '');

    await _checkForImages(qrCode);

    await showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              title: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('Détails'),
                  Row(
                    children: [
                      IconButton(
                        icon: const Icon(Icons.camera_alt),
                        onPressed: () => _takePicture(context, qrCode),
                        tooltip: 'Prendre une photo',
                      ),
                      IconButton(
                        icon: const Icon(Icons.folder),
                        onPressed: _hasImages ? () => _showImages(context, qrCode) : null,
                        tooltip: 'Voir les photos',
                      ),
                    ],
                  ),
                ],
              ),
              content: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: TextFormField(
                            controller: nomClientController,
                            decoration: const InputDecoration(
                              labelText: 'Client',
                              border: OutlineInputBorder(),
                            ),
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.edit),
                          onPressed: () async {
                            final batch = _firestore.batch();
                            batch.update(_firestore.collection('Qr-codes').doc(qrCode), {
                              'nom_client': nomClientController.text,
                            });
                            batch.update(_firestore.collection('Atelier').doc(qrCode), {
                              'nom_client': nomClientController.text,
                            });
                            _firestore
                                .collection('Qr-codes')
                                .doc(qrCode)
                                .collection("History")
                                .doc(data?['uuid'].toString())
                                .update({
                              'nom_client': nomClientController.text,
                            });
                            await batch.commit();
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('Nom client mis à jour!')),
                            );
                          },
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: TextFormField(
                            controller: telephoneController,
                            decoration: const InputDecoration(
                              labelText: 'Téléphone',
                              border: OutlineInputBorder(),
                            ),
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.edit),
                          onPressed: () async {
                            final batch = _firestore.batch();
                            batch.update(_firestore.collection('Qr-codes').doc(qrCode), {
                              'numero_telephone': telephoneController.text,
                            });
                            batch.update(_firestore.collection('Atelier').doc(qrCode), {
                              'numero_telephone': telephoneController.text,
                            });
                            _firestore
                                .collection('Qr-codes')
                                .doc(qrCode)
                                .collection("History")
                                .doc(data?['uuid'].toString())
                                .update({
                              'numero_telephone': telephoneController.text,
                            });
                            await batch.commit();
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('Numéro de téléphone mis à jour!')),
                            );
                          },
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: TextFormField(
                            controller: typeMachineController,
                            decoration: const InputDecoration(
                              labelText: 'Type d\'appareil',
                              border: OutlineInputBorder(),
                            ),
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.edit),
                          onPressed: () async {
                            final batch = _firestore.batch();
                            batch.update(_firestore.collection('Qr-codes').doc(qrCode), {
                              'type_machine': typeMachineController.text,
                            });
                            batch.update(_firestore.collection('Atelier').doc(qrCode), {
                              'type_machine': typeMachineController.text,
                            });
                            _firestore
                                .collection('Qr-codes')
                                .doc(qrCode)
                                .collection("History")
                                .doc(data?['uuid'].toString())
                                .update({
                              'type_machine': typeMachineController.text,
                            });
                            await batch.commit();
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('Type d\'appareil mis à jour!')),
                            );
                          },
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: TextFormField(
                            controller: marqueController,
                            decoration: const InputDecoration(
                              labelText: 'Marque',
                              border: OutlineInputBorder(),
                            ),
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.edit),
                          onPressed: () async {
                            final batch = _firestore.batch();
                            batch.update(_firestore.collection('Qr-codes').doc(qrCode), {
                              'marque': marqueController.text,
                            });
                            batch.update(_firestore.collection('Atelier').doc(qrCode), {
                              'marque': marqueController.text,
                            });
                            _firestore
                                .collection('Qr-codes')
                                .doc(qrCode)
                                .collection("History")
                                .doc(data?['uuid'].toString())
                                .update({
                              'marque': marqueController.text,
                            });
                            await batch.commit();
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('Marque mise à jour!')),
                            );
                          },
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: TextFormField(
                            controller: panneController,
                            decoration: const InputDecoration(
                              labelText: 'Panne',
                              border: OutlineInputBorder(),
                            ),
                            maxLines: 3,
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.edit),
                          onPressed: () async {
                            final batch = _firestore.batch();
                            batch.update(_firestore.collection('Qr-codes').doc(qrCode), {
                              'panne': panneController.text,
                            });
                            batch.update(_firestore.collection('Atelier').doc(qrCode), {
                              'panne': panneController.text,
                            });
                            _firestore
                                .collection('Qr-codes')
                                .doc(qrCode)
                                .collection("History")
                                .doc(data?['uuid'].toString())
                                .update({
                              'panne': panneController.text,
                            });
                            await batch.commit();
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('Description de la panne mise à jour!')),
                            );
                          },
                        ),
                      ],
                    ),
                    if (data?['timestamp'] != null)
                      Text(
                          'Entrée: ${DateFormat('dd/MM/yyyy HH:mm').format((data!['timestamp'] as Timestamp).toDate())}'),
                    const Divider(),
                    const Text('Réparation',
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: TextFormField(
                            controller: reparationController,
                            decoration: const InputDecoration(
                              hintText: 'Décrire la réparation effectuée',
                              border: OutlineInputBorder(),
                            ),
                            maxLines: 3,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          decoration: BoxDecoration(
                            color: Colors.green,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: IconButton(
                            icon: const Icon(Icons.save, color: Colors.white),
                            onPressed: () async {
                              final batch = _firestore.batch();

                              // Mise à jour dans Atelier
                              batch.update(_firestore.collection('Atelier').doc(qrCode), {
                                'reparation': reparationController.text,
                              });

                              // Mise à jour dans Qr-codes
                              batch.update(_firestore.collection('Qr-codes').doc(qrCode), {
                                'reparation': reparationController.text,
                              });

                              // Mise à jour dans History
                              _firestore
                                  .collection('Qr-codes')
                                  .doc(qrCode)
                                  .collection("History")
                                  .doc(data?['uuid'].toString())
                                  .update({
                                'reparation': reparationController.text,
                              });

                              await batch.commit();
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('Réparation mise à jour avec succès!')),
                              );
                            },
                            tooltip: 'Enregistrer la réparation',
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Fermer'),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green,
                  ),
                  onPressed: () async {
                    final batch = _firestore.batch();

                    // 1. Ajouter à l'historique client
                    final histRef = _firestore
                        .collection('clients')
                        .doc(data?['numero_telephone'])
                        .collection('historique')
                        .doc();

                    batch.set(histRef, {
                      ...data!,
                      'date_entree': data['timestamp'],
                      'date_sortie': FieldValue.serverTimestamp(),
                    });

                    // 2. Mettre à jour Qr-codes
                    batch.update(_firestore.collection('Qr-codes').doc(qrCode), {
                      'atelier': false,
                      'date_sortie': FieldValue.serverTimestamp(),
                    });

                    // 3. Mettre à jour History
                    _firestore
                        .collection('Qr-codes')
                        .doc(qrCode)
                        .collection("History")
                        .doc(data?['uuid'].toString())
                        .update({
                      'atelier': false,
                      'date_sortie': FieldValue.serverTimestamp(),
                    });

                    // 4. Supprimer de Atelier
                    batch.delete(_firestore.collection('Atelier').doc(qrCode));

                    try {
                      await batch.commit();
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Réparation terminée et archivée!'),
                            backgroundColor: Colors.green,
                          ),
                        );
                        Navigator.pop(context);
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
                  child: const Text('Terminer',
                      style: TextStyle(color: Colors.white)),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _showReturnOptions(BuildContext context, String qrCode) async {
    final data = await _firestore.collection('Qr-codes').doc(qrCode).get();
    return showDialog(
      context: context,
      builder: (context) => AlertDialog(
        actionsAlignment: MainAxisAlignment.center,
        contentPadding: const EdgeInsets.only(top: 20),
        actions: [
          Padding(
            padding: const EdgeInsets.only(top: 15),
            child: SizedBox(
              width: double.infinity,
              child: TextButton(
                style: TextButton.styleFrom(
                  backgroundColor: Colors.yellow,
                  
                  foregroundColor: Colors.black,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
                onPressed: () {
                  Navigator.pop(context);
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => Scaffold(
                        appBar: AppBar(title: const Text('Historique')),
                        body: StreamBuilder(
                          stream: _firestore
                              .collection('Qr-codes')
                              .doc(qrCode)
                              .collection('History')
                              .snapshots(),
                          builder: (context, snapshot) {
                            if (!snapshot.hasData)
                              return const Center(
                                  child: CircularProgressIndicator());
                            return ListView.builder(
                              itemCount: snapshot.data!.docs.length,
                              itemBuilder: (context, index) {
                                final data = snapshot.data!.docs[index].data();
                                return ListTile(
                                  title: Text(data['nom_client']),
                                  subtitle: Text(DateFormat('dd/MM/yyyy')
                                      .format((data['timestamp'] as Timestamp)
                                          .toDate())),
                                  onTap: () =>
                                      _showHistoryDetails(context, data),
                                );
                              },
                            );
                          },
                        ),
                      ),
                    ),
                  );
                },
                child: const Text('Voir l\'historique'),
              ),
            ),
          ),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: TextButton(
              style: TextButton.styleFrom(
                backgroundColor: Colors.red,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
              ),
              onPressed: () {
                _firestore
                    .collection('Qr-codes')
                    .doc(qrCode)
                    .update({'atelier': true, 'date_sortie': null});
                _firestore
                    .collection('Qr-codes')
                    .doc(qrCode)
                    .collection("History")
                    .doc(data['uuid'])
                    .update({'atelier': true, 'date_sortie': null});
                Navigator.pop(context);
                _showRepairDetails(data);
              },
              child: const Text('Retour client'),
            ),
          ),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: TextButton(
              style: TextButton.styleFrom(
                backgroundColor: Colors.green,
                foregroundColor: Colors.black,
                padding: const EdgeInsets.symmetric(vertical: 16),
              ),
              onPressed: () {
                Navigator.pop(context);
                _showNewRepairFormOfNewRepair(context, qrCode);
              },
              child: const Text('Nouvelle Réparation'),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _showNewRepairFormOfNewRepair(
      BuildContext context, String qrCode) async {
    await showDialog(
      context: context,
      builder: (context) {
        return FutureBuilder<DocumentSnapshot>(
          future: _firestore.collection('Qr-codes').doc(qrCode).get(),
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const AlertDialog(
                content: CircularProgressIndicator(),
              );
            }

            if (!snapshot.hasData || !snapshot.data!.exists) {
              Navigator.pop(context);
              return const SizedBox.shrink();
            }

            final existingData = snapshot.data!.data() as Map<String, dynamic>;
            final issueController = TextEditingController(text: "");

            return AlertDialog(
              title: const Text('Nouvelle Réparation sur le même appareil'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextFormField(
                      initialValue: existingData['numero_telephone'],
                      decoration: const InputDecoration(labelText: 'Téléphone'),
                      enabled: false,
                    ),
                    TextFormField(
                      initialValue: existingData['nom_client'],
                      decoration:
                          const InputDecoration(labelText: 'Nom Client'),
                      enabled: false,
                    ),
                    const SizedBox(height: 16),
                    DropdownButtonFormField<String>(
                      value: existingData['type_machine'],
                      decoration: const InputDecoration(
                        labelText: 'Type d\'appareil',
                        border: OutlineInputBorder(),
                      ),
                      items: [
                        'Réfrigérateur',
                        'Congélateur',
                        'Lave-linge',
                        'Lave-vaisselle',
                        'Sèche-linge',
                        'Lave-sèche-linge',
                        'Climatiseur',
                        'Micro-ondes',
                        'Four',
                        'Hotte aspirante',
                      ]
                          .map(
                              (e) => DropdownMenuItem(value: e, child: Text(e)))
                          .toList(),
                      onChanged: null,
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      initialValue: existingData['marque'],
                      decoration: const InputDecoration(labelText: 'Marque'),
                      enabled: false,
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: issueController,
                      decoration: const InputDecoration(
                        labelText: 'Description de la panne',
                        border: OutlineInputBorder(),
                      ),
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
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blue,
                    foregroundColor: Colors.white,
                  ),
                  onPressed: () async {
                    if (issueController.text.isEmpty) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                            content: Text('Veuillez décrire la panne')),
                      );
                      return;
                    }

                    final repairData = {
                      'uuid': Uuid().v1(),
                      'numero_telephone': existingData['numero_telephone'],
                      'nom_client': existingData['nom_client'],
                      'type_machine': existingData['type_machine'],
                      'marque': existingData['marque'],
                      'panne': issueController.text,
                      'reparation': '',
                      'atelier': true,
                      'timestamp': FieldValue.serverTimestamp(),
                    };

                    final batch = _firestore.batch();

                    batch.set(
                        _firestore
                            .collection('Qr-codes')
                            .doc(qrCode)
                            .collection("History")
                            .doc(repairData['uuid'].toString()),
                        repairData);

                    batch.set(_firestore.collection('Qr-codes').doc(qrCode),
                        repairData);

                    batch.set(_firestore.collection('Atelier').doc(qrCode), {
                      ...repairData,
                      'statut': 'en_attente',
                      'technicien': null,
                    });

                    await batch.commit();
                    Navigator.pop(context);
                  },
                  child: const Text('Enregistrer'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _showHistoryDetails(BuildContext context, Map<String, dynamic> data) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Détails Historique'),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Client: ${data['nom_client'] ?? 'N/A'}',
                  style: const TextStyle(fontWeight: FontWeight.bold)),
              Text('Téléphone: ${data['numero_telephone'] ?? 'N/A'}'),
              Text('Appareil: ${data['type_machine'] ?? 'N/A'}'),
              Text('Marque: ${data['marque'] ?? 'N/A'}'),
              Text('Panne: ${data['panne'] ?? 'N/A'}'),
              if (data['timestamp'] != null)
                Text(
                    'Entrée: ${DateFormat('dd/MM/yyyy HH:mm').format((data['timestamp'] as Timestamp).toDate())}'),
              const Divider(),
              const Text('Journal de Réparation',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              ...(data['journal_reparation']?.map<Widget>((log) => Card(
                        margin: const EdgeInsets.only(bottom: 8),
                        child: Padding(
                          padding: const EdgeInsets.all(8.0),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(log['etape'],
                                  style: const TextStyle(fontSize: 16)),
                              Text(
                                  '${log['technicien']} - ${DateFormat('dd/MM HH:mm').format((log['date'] as Timestamp).toDate())}',
                                  style: TextStyle(color: Colors.grey[600])),
                            ],
                          ),
                        ),
                      )) ??
                  [const Text('Aucune étape enregistrée')]),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Fermer'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Scanner QR Code'),
        actions: [
          IconButton(
            icon: Icon(_isFlashOn ? Icons.flash_on : Icons.flash_off),
            onPressed: _toggleFlash,
          ),
          IconButton(
            icon: const Icon(Icons.flip_camera_ios),
            onPressed: _switchCamera,
          ),
        ],
      ),
      body: Stack(
        children: [
          QRView(
            key: _qrKey,
            onQRViewCreated: _onQRViewCreated,
            overlay: QrScannerOverlayShape(
              borderColor: Theme.of(context).primaryColor,
              borderRadius: 10,
              borderLength: 30,
              borderWidth: 10,
              cutOutSize: MediaQuery.of(context).size.width * 0.8,
            ),
          ),
          Positioned(
            bottom: 24,
            left: 24,
            right: 24,
            child: Column(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.black54,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.zoom_in, color: Colors.white),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Slider(
                          value: _zoomLevel,
                          min: 0,
                          max: 5,
                          onChanged: _setZoomLevel,
                        ),
                      ),
                      Text(
                        '${(_zoomLevel * 100).toInt()}%',
                        style: const TextStyle(color: Colors.white),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  'Placez le QR code dans le cadre',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    shadows: [
                      Shadow(
                        color: Colors.black.withOpacity(0.5),
                        offset: const Offset(1, 1),
                        blurRadius: 2,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          if (_isProcessing)
            Container(
              color: Colors.black54,
              child: const Center(
                child: CircularProgressIndicator(),
              ),
            ),
        ],
      ),
    );
  }
}