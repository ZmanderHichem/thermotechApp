import 'package:flutter/material.dart';
import 'package:qr_code_scanner/qr_code_scanner.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';
import 'package:camera/camera.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:path_provider/path_provider.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:io';
import 'package:path/path.dart' as path;

class AdminDashboard extends StatefulWidget {
  const AdminDashboard({super.key});

  @override
  _AdminDashboardState createState() => _AdminDashboardState();
}

class _AdminDashboardState extends State<AdminDashboard> with WidgetsBindingObserver {
  final GlobalKey _qrKey = GlobalKey(debugLabel: 'QR');
  QRViewController? _qrController;
  bool _isProcessing = false;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseStorage _storage = FirebaseStorage.instance;
  List<CameraDescription>? _cameras;
  bool _hasImages = false;
  bool _isFlashOn = false;
  double _zoomLevel = 1.0;
  final double _minZoom = 1.0;
  final double _maxZoom = 5.0;
  bool _isCameraInitialized = false;
  CameraController? _cameraController;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initializeCamera();
  }

  @override
  void dispose() {
    _qrController?.dispose();
    _cameraController?.dispose();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _initializeCamera();
    }
  }

  Future<void> _initializeCamera() async {
    _cameras = await availableCameras();
    setState(() => _isCameraInitialized = true);
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

  Future<void> _pickImage(BuildContext context, String qrCode) async {
    try {
      final ImagePicker picker = ImagePicker();
      final XFile? image = await picker.pickImage(source: ImageSource.gallery);
      
      if (image == null) return;

      final file = File(image.path);
      final fileName = path.basename(file.path);
      final storageRef = _storage.ref().child('repair_images/$qrCode/$fileName');
      
      await storageRef.putFile(file);
      final imageUrl = await storageRef.getDownloadURL();
      
      await _firestore.collection('Qr-codes').doc(qrCode).update({
        'images': FieldValue.arrayUnion([imageUrl])
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Photo importée avec succès')),
        );
        await _checkForImages(qrCode);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erreur: ${e.toString()}')),
        );
      }
    }
  }

  Future<void> _takePicture(BuildContext context, String qrCode) async {
    if (_cameras == null || _cameras!.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Aucune caméra disponible')),
      );
      return;
    }

    final camera = _cameras!.first;
    _cameraController = CameraController(
      camera,
      ResolutionPreset.max,
      enableAudio: false,
    );

    try {
      await _cameraController!.initialize();
      
      if (!mounted) return;

      await showDialog(
        context: context,
        builder: (context) => StatefulBuilder(
          builder: (context, setState) {
            return Dialog(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Stack(
                    alignment: Alignment.center,
                    children: [
                      SizedBox(
                        width: MediaQuery.of(context).size.width,
                        height: MediaQuery.of(context).size.width,
                        child: CameraPreview(_cameraController!),
                      ),
                      Positioned(
                        top: 16,
                        right: 16,
                        child: Row(
                          children: [
                            IconButton(
                              icon: Icon(
                                _isFlashOn ? Icons.flash_on : Icons.flash_off,
                                color: Colors.white,
                              ),
                              onPressed: () async {
                                setState(() => _isFlashOn = !_isFlashOn);
                                await _cameraController!.setFlashMode(
                                  _isFlashOn ? FlashMode.torch : FlashMode.off,
                                );
                              },
                            ),
                            const SizedBox(width: 8),
                            IconButton(
                              icon: const Icon(Icons.flip_camera_ios, color: Colors.white),
                              onPressed: () async {
                                final newCamera = _cameras!.firstWhere(
                                  (camera) => camera.lensDirection != 
                                    _cameraController!.description.lensDirection,
                                );
                                await _cameraController!.dispose();
                                _cameraController = CameraController(
                                  newCamera,
                                  ResolutionPreset.max,
                                  enableAudio: false,
                                );
                                await _cameraController!.initialize();
                                setState(() {});
                              },
                            ),
                          ],
                        ),
                      ),
                      Positioned(
                        bottom: 16,
                        left: 0,
                        right: 0,
                        child: Column(
                          children: [
                            Slider(
                              value: _zoomLevel,
                              min: _minZoom,
                              max: _maxZoom,
                              onChanged: (value) async {
                                setState(() => _zoomLevel = value);
                                await _cameraController!.setZoomLevel(value);
                              },
                            ),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                              children: [
                                IconButton(
                                  icon: const Icon(Icons.close, color: Colors.white),
                                  onPressed: () => Navigator.pop(context),
                                ),
                                FloatingActionButton(
                                  heroTag: 'takePhoto',
                                  onPressed: () async {
                                    try {
                                      final image = await _cameraController!.takePicture();
                                      final file = File(image.path);
                                      final fileName = path.basename(file.path);
                                      final storageRef = _storage.ref()
                                        .child('repair_images/$qrCode/$fileName');
                                      
                                      await storageRef.putFile(file);
                                      final imageUrl = await storageRef.getDownloadURL();
                                      
                                      await _firestore.collection('Qr-codes')
                                        .doc(qrCode).update({
                                          'images': FieldValue.arrayUnion([imageUrl])
                                        });

                                      if (mounted) {
                                        Navigator.pop(context);
                                        ScaffoldMessenger.of(context).showSnackBar(
                                          const SnackBar(
                                            content: Text('Photo enregistrée avec succès'),
                                          ),
                                        );
                                        await _checkForImages(qrCode);
                                      }
                                    } catch (e) {
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        SnackBar(
                                          content: Text('Erreur: ${e.toString()}'),
                                        ),
                                      );
                                    }
                                  },
                                  child: const Icon(Icons.camera),
                                ),
                                IconButton(
                                  icon: const Icon(Icons.photo_library, color: Colors.white),
                                  onPressed: () {
                                    Navigator.pop(context);
                                    _pickImage(context, qrCode);
                                  },
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            );
          },
        ),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erreur: ${e.toString()}')),
      );
    } finally {
      await _cameraController?.dispose();
    }
  }

  Future<void> _showImages(BuildContext context, String qrCode) async {
    try {
      final ref = _storage.ref().child('repair_images/$qrCode');
      final result = await ref.listAll();
      
      if (result.items.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Aucune image disponible')),
        );
        return;
      }

      final imageUrls = await Future.wait(
        result.items.map((ref) => ref.getDownloadURL())
      );

      if (!mounted) return;

      showDialog(
        context: context,
        builder: (context) => Dialog(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              AppBar(
                title: const Text('Photos de la réparation'),
                automaticallyImplyLeading: false,
                actions: [
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
              Expanded(
                child: GridView.builder(
                  padding: const EdgeInsets.all(8),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
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
                            builder: (context) => ImageViewerPage(
                              imageUrl: imageUrls[index],
                            ),
                          ),
                        );
                      },
                      child: Hero(
                        tag: imageUrls[index],
                        child: Image.network(
                          imageUrls[index],
                          fit: BoxFit.cover,
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erreur: ${e.toString()}')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
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
              cutOutSize: 300,
            ),
          ),
          if (_isProcessing)
            Container(
              color: Colors.black45,
              child: const Center(
                child: CircularProgressIndicator(),
              ),
            ),
          Positioned(
            top: MediaQuery.of(context).padding.top + 16,
            left: 16,
            child: IconButton(
              icon: const Icon(Icons.arrow_back, color: Colors.white),
              onPressed: () => Navigator.pop(context),
            ),
          ),
        ],
      ),
    );
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
                                const Snack
Bar(content: Text('Réparation mise à jour avec succès!')),
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
}

class ImageViewerPage extends StatelessWidget {
  final String imageUrl;

  const ImageViewerPage({super.key, required this.imageUrl});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: Center(
        child: InteractiveViewer(
          minScale: 0.5,
          maxScale: 4.0,
          child: Hero(
            tag: imageUrl,
            child: Image.network(imageUrl),
          ),
        ),
      ),
    );
  }
}