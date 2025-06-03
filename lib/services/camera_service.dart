import 'dart:io';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:photo_view/photo_view.dart';
import 'package:photo_view/photo_view_gallery.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as path;
import 'package:image_cropper/image_cropper.dart';

class CameraService {
  CameraController? controller;
  List<CameraDescription>? cameras;
  int selectedCameraIndex = 0;
  double _minAvailableZoom = 1.0;
  double _maxAvailableZoom = 1.0;
  double _currentZoom = 1.0;
  double _baseScale = 1.0;
  bool _isFlashOn = false;

  Future<void> initialize() async {
    cameras = await availableCameras();
    if (cameras != null && cameras!.isNotEmpty) {
      controller = CameraController(
        cameras![selectedCameraIndex],
        ResolutionPreset.max,
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.jpeg,
      );

      await controller!.initialize();
      await _getAvailableZoomLevels();
    }
  }

  Future<void> _getAvailableZoomLevels() async {
    if (controller == null) return;

    _minAvailableZoom = await controller!.getMinZoomLevel();
    _maxAvailableZoom = await controller!.getMaxZoomLevel();
    _currentZoom = 1.0;
  }

  Future<void> setZoomLevel(double zoom) async {
    if (controller == null) return;

    zoom = zoom.clamp(_minAvailableZoom, _maxAvailableZoom);
    await controller!.setZoomLevel(zoom);
    _currentZoom = zoom;
  }

  Future<void> toggleFlash() async {
    if (controller == null) return;

    _isFlashOn = !_isFlashOn;
    await controller!.setFlashMode(
      _isFlashOn ? FlashMode.torch : FlashMode.off,
    );
  }

  Future<void> switchCamera() async {
    if (cameras == null || cameras!.isEmpty || controller == null) return;

    selectedCameraIndex = (selectedCameraIndex + 1) % cameras!.length;

    await controller!.dispose();
    controller = CameraController(
      cameras![selectedCameraIndex],
      ResolutionPreset.max,
      enableAudio: false,
      imageFormatGroup: ImageFormatGroup.jpeg,
    );

    await controller!.initialize();
    await _getAvailableZoomLevels();
  }

  Future<File?> takePicture() async {
    if (controller == null || !controller!.value.isInitialized) return null;

    try {
      final XFile image = await controller!.takePicture();
      final directory = await getTemporaryDirectory();
      final String fileName = path.basename(image.path);
      final File savedImage = File('${directory.path}/$fileName');
      await File(image.path).copy(savedImage.path);
      return savedImage;
    } catch (e) {
      debugPrint('Error taking picture: $e');
      return null;
    }
  }

  Future<File?> pickImage() async {
    try {
      final ImagePicker picker = ImagePicker();
      final XFile? image = await picker.pickImage(source: ImageSource.gallery);
      if (image == null) return null;

      final directory = await getTemporaryDirectory();
      final String fileName = path.basename(image.path);
      final File savedImage = File('${directory.path}/$fileName');
      await File(image.path).copy(savedImage.path);
      return savedImage;
    } catch (e) {
      debugPrint('Error picking image: $e');
      return null;
    }
  }

  Future<File?> cropImage(File imageFile) async {
    try {
      final croppedFile = await ImageCropper().cropImage(
        sourcePath: imageFile.path,
        aspectRatioPresets: [
          CropAspectRatioPreset.square,
          CropAspectRatioPreset.ratio3x2,
          CropAspectRatioPreset.original,
          CropAspectRatioPreset.ratio4x3,
          CropAspectRatioPreset.ratio16x9
        ],
        uiSettings: [
          AndroidUiSettings(
            toolbarTitle: 'Recadrer l\'image',
            toolbarColor: Colors.blue,
            toolbarWidgetColor: Colors.white,
            initAspectRatio: CropAspectRatioPreset.original,
            lockAspectRatio: false,
          ),
          IOSUiSettings(
            title: 'Recadrer l\'image',
          ),
        ],
      );

      if (croppedFile == null) return null;
      return File(croppedFile.path);
    } catch (e) {
      debugPrint('Error cropping image: $e');
      return null;
    }
  }

  void dispose() {
    controller?.dispose();
  }

  double get currentZoom => _currentZoom;
  double get minZoom => _minAvailableZoom;
  double get maxZoom => _maxAvailableZoom;
  bool get isFlashOn => _isFlashOn;
  bool get isCameraInitialized => controller?.value.isInitialized ?? false;
  bool get hasMultipleCameras => cameras != null && cameras!.length > 1;
}

class ImageGalleryView extends StatelessWidget {
  final List<String> imageUrls;
  final int initialIndex;

  const ImageGalleryView({
    super.key,
    required this.imageUrls,
    this.initialIndex = 0,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          PhotoViewGallery.builder(
            scrollPhysics: const BouncingScrollPhysics(),
            builder: (BuildContext context, int index) {
              return PhotoViewGalleryPageOptions(
                imageProvider: NetworkImage(imageUrls[index]),
                initialScale: PhotoViewComputedScale.contained,
                minScale: PhotoViewComputedScale.contained,
                maxScale: PhotoViewComputedScale.covered * 2,
              );
            },
            itemCount: imageUrls.length,
            loadingBuilder: (context, event) => Center(
              child: SizedBox(
                width: 20.0,
                height: 20.0,
                child: CircularProgressIndicator(
                  value: event == null
                      ? 0
                      : event.cumulativeBytesLoaded / event.expectedTotalBytes!,
                ),
              ),
            ),
            backgroundDecoration: const BoxDecoration(color: Colors.black),
            pageController: PageController(initialPage: initialIndex),
          ),
          Positioned(
            top: 40,
            left: 10,
            child: IconButton(
              icon: const Icon(Icons.close, color: Colors.white),
              onPressed: () => Navigator.of(context).pop(),
            ),
          ),
        ],
      ),
    );
  }
}