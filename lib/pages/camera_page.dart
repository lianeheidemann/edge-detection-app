import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';

import 'result_page.dart';

class CameraPage extends StatefulWidget {
  const CameraPage({super.key});

  @override
  State<CameraPage> createState() => _CameraPageState();
}

class _CameraPageState extends State<CameraPage> {
  CameraController? _cameraController;
  List<CameraDescription> _cameras = const [];
  int _selectedCameraIndex = 0;
  bool _isLoading = true;
  bool _isCapturing = false;
  bool _isSwitchingCamera = false;
  bool _isPickingImage = false;
  bool _isTogglingFlash = false;
  FlashMode _flashMode = FlashMode.off;
  String _errorMessage = '';

  @override
  void initState() {
    super.initState();
    _initializeCamera();
  }

  Future<void> _initializeCamera() async {
    if (mounted) {
      setState(() {
        _isLoading = true;
        _errorMessage = '';
      });
    }
    try {
      _cameras = await availableCameras();
      if (_cameras.isEmpty) {
        throw CameraException('cameraNotFound', 'No camera was found.');
      }
      final backCameraIndex = _cameras.indexWhere(
        (camera) => camera.lensDirection == CameraLensDirection.back,
      );
      _selectedCameraIndex = backCameraIndex >= 0 ? backCameraIndex : 0;
      final controller = CameraController(
        _cameras[_selectedCameraIndex],
        ResolutionPreset.high,
        enableAudio: false,
      );
      await controller.initialize();
      if (!mounted) {
        await controller.dispose();
        return;
      }
      await _cameraController?.dispose();
      setState(() {
        _cameraController = controller;
        _flashMode = FlashMode.off;
        _isLoading = false;
      });
    } on CameraException catch (error) {
      if (!mounted) return;
      setState(() {
        _errorMessage = error.code == 'CameraAccessDenied'
            ? 'Allow camera access in the device settings.'
            : (error.description ?? 'Could not open the camera.');
        _isLoading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _errorMessage = 'Could not open the camera.';
        _isLoading = false;
      });
    }
  }

  Future<void> _switchCamera() async {
    if (_isSwitchingCamera || _cameras.length < 2) return;

    final currentDirection = _cameras[_selectedCameraIndex].lensDirection;
    final targetDirection = currentDirection == CameraLensDirection.back
        ? CameraLensDirection.front
        : CameraLensDirection.back;
    final nextIndex = _cameras.indexWhere(
      (camera) => camera.lensDirection == targetDirection,
    );
    if (nextIndex < 0) return;

    final oldController = _cameraController;
    setState(() {
      _isSwitchingCamera = true;
      _cameraController = null;
    });
    await oldController?.dispose();
    try {
      final newController = CameraController(
        _cameras[nextIndex],
        ResolutionPreset.high,
        enableAudio: false,
      );
      await newController.initialize();
      if (!mounted) {
        await newController.dispose();
        return;
      }
      setState(() {
        _cameraController = newController;
        _selectedCameraIndex = nextIndex;
        _flashMode = FlashMode.off;
      });
    } on CameraException {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not switch cameras.')),
        );
      }
      await _initializeCamera();
    } finally {
      if (mounted) setState(() => _isSwitchingCamera = false);
    }
  }

  static const List<FlashMode> _flashModeCycle = [
    FlashMode.off,
    FlashMode.auto,
    FlashMode.torch,
  ];

  Future<void> _toggleFlash() async {
    final controller = _cameraController;
    if (controller == null || _isTogglingFlash) return;

    final currentIndex = _flashModeCycle.indexOf(_flashMode);
    final newMode =
        _flashModeCycle[(currentIndex + 1) % _flashModeCycle.length];
    setState(() => _isTogglingFlash = true);
    try {
      await controller.setFlashMode(newMode);
      if (!mounted) return;
      setState(() => _flashMode = newMode);
    } on CameraException {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Flash not available on this camera.'),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isTogglingFlash = false);
    }
  }

  Future<void> _pickFromGallery() async {
    if (_isPickingImage || _isCapturing || _isSwitchingCamera) return;
    setState(() => _isPickingImage = true);
    try {
      final image = await ImagePicker().pickImage(source: ImageSource.gallery);
      if (image == null || !mounted) return;
      await Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => ResultPage(imagePath: image.path)),
      );
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not open the photo gallery.')),
        );
      }
    } finally {
      if (mounted) setState(() => _isPickingImage = false);
    }
  }

  Future<void> _takePhoto() async {
    final controller = _cameraController;
    if (controller == null ||
        !controller.value.isInitialized ||
        _isCapturing ||
        _isSwitchingCamera ||
        _isPickingImage) {
      return;
    }
    setState(() => _isCapturing = true);
    try {
      final photo = await controller.takePicture();
      if (_cameras[_selectedCameraIndex].lensDirection ==
          CameraLensDirection.front) {
        await _unmirrorFrontPhoto(photo.path);
      }
      if (!mounted) return;
      await Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => ResultPage(imagePath: photo.path)),
      );
    } on CameraException {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not capture the photo.')),
        );
      }
    } finally {
      if (mounted) setState(() => _isCapturing = false);
    }
  }

  Future<void> _unmirrorFrontPhoto(String path) async {
    try {
      final file = File(path);
      final decoded = img.decodeImage(await file.readAsBytes());
      if (decoded == null) return;
      final flipped = img.flipHorizontal(decoded);
      await file.writeAsBytes(img.encodeJpg(flipped));
    } catch (_) {
      // Keep the original (mirrored) photo if flipping fails.
    }
  }

  @override
  void dispose() {
    _cameraController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(),
              SizedBox(height: 18),
              Text('Preparing the camera…'),
            ],
          ),
        ),
      );
    }
    if (_errorMessage.isNotEmpty) return _buildError(context);

    return Scaffold(
      backgroundColor: const Color(0xFF11111C),
      body: SafeArea(
        child: Column(
          children: [
            _CameraHeader(
              flashMode: _flashMode,
              canToggleFlash: _cameraController != null && !_isTogglingFlash,
              onToggleFlash: _toggleFlash,
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(28),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      if (_cameraController != null)
                        FittedBox(
                          fit: BoxFit.cover,
                          child: SizedBox(
                            width: _cameraController!
                                .value
                                .previewSize!
                                .height,
                            height: _cameraController!
                                .value
                                .previewSize!
                                .width,
                            child: CameraPreview(_cameraController!),
                          ),
                        )
                      else
                        const ColoredBox(
                          color: Colors.black,
                          child: Center(child: CircularProgressIndicator()),
                        ),
                      const IgnorePointer(child: _FocusGuide()),
                    ],
                  ),
                ),
              ),
            ),
            _CaptureControls(
              isCapturing: _isCapturing,
              isBusy: _isSwitchingCamera || _isPickingImage,
              canSwitchCamera: _cameras.length > 1,
              onCapture: _takePhoto,
              onGallery: _pickFromGallery,
              onSwitchCamera: _switchCamera,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildError(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.no_photography_outlined,
                  size: 52,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(height: 20),
                Text(
                  'Camera unavailable',
                  style: Theme.of(context).textTheme.headlineSmall
                      ?.copyWith(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 10),
                Text(_errorMessage, textAlign: TextAlign.center),
                const SizedBox(height: 24),
                FilledButton.icon(
                  onPressed: _initializeCamera,
                  icon: const Icon(Icons.refresh),
                  label: const Text('Try again'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _CameraHeader extends StatelessWidget {
  const _CameraHeader({
    required this.flashMode,
    required this.canToggleFlash,
    required this.onToggleFlash,
  });

  final FlashMode flashMode;
  final bool canToggleFlash;
  final VoidCallback onToggleFlash;

  @override
  Widget build(BuildContext context) {
    final (icon, label) = switch (flashMode) {
      FlashMode.auto => (Icons.flash_auto, 'Flash auto · tap to turn on'),
      FlashMode.always ||
      FlashMode.torch => (Icons.flash_on, 'Flash on · tap to turn off'),
      FlashMode.off => (Icons.flash_off, 'Flash off · tap for auto'),
    };
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 16),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Image.asset(
              'assets/icons/app-icon.png',
              width: 48,
              height: 48,
              fit: BoxFit.cover,
            ),
          ),
          const SizedBox(width: 12),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Edge Detection',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 19,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                SizedBox(height: 2),
                Text(
                  'Image processing',
                  style: TextStyle(color: Color(0xFFA8A8BA), fontSize: 13),
                ),
              ],
            ),
          ),
          _SecondaryCameraButton(
            icon: icon,
            label: label,
            onPressed: canToggleFlash ? onToggleFlash : null,
          ),
        ],
      ),
    );
  }
}

class _CaptureControls extends StatelessWidget {
  const _CaptureControls({
    required this.isCapturing,
    required this.isBusy,
    required this.canSwitchCamera,
    required this.onCapture,
    required this.onGallery,
    required this.onSwitchCamera,
  });

  final bool isCapturing;
  final bool isBusy;
  final bool canSwitchCamera;
  final VoidCallback onCapture;
  final VoidCallback onGallery;
  final VoidCallback onSwitchCamera;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 18, 24, 24),
      child: Column(
        children: [
          const Text(
            'Frame the object and keep the phone steady',
            textAlign: TextAlign.center,
            style: TextStyle(color: Color(0xFFC6C6D4), fontSize: 13),
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _SecondaryCameraButton(
                icon: Icons.photo_library_outlined,
                label: 'Gallery',
                onPressed: isBusy || isCapturing ? null : onGallery,
              ),
              Semantics(
                button: true,
                label: isCapturing ? 'Capturing photo' : 'Take photo',
                child: GestureDetector(
                  onTap: isCapturing || isBusy ? null : onCapture,
                  child: Container(
                    width: 72,
                    height: 72,
                    padding: const EdgeInsets.all(5),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 3),
                    ),
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: isCapturing
                            ? const Color(0xFFAAA7E8)
                            : const Color(0xFF6C63FF),
                      ),
                      child: isCapturing
                          ? const Padding(
                              padding: EdgeInsets.all(16),
                              child: CircularProgressIndicator(
                                color: Colors.white,
                                strokeWidth: 2.5,
                              ),
                            )
                          : const Icon(
                              Icons.camera_alt_rounded,
                              color: Colors.white,
                              size: 27,
                            ),
                    ),
                  ),
                ),
              ),
              _SecondaryCameraButton(
                icon: Icons.cameraswitch_outlined,
                label: 'Switch camera',
                onPressed: canSwitchCamera && !isBusy && !isCapturing
                    ? onSwitchCamera
                    : null,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SecondaryCameraButton extends StatelessWidget {
  const _SecondaryCameraButton({
    required this.icon,
    required this.label,
    required this.onPressed,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return IconButton.filledTonal(
      tooltip: label,
      onPressed: onPressed,
      icon: Icon(icon),
      color: Colors.white,
      style: IconButton.styleFrom(
        backgroundColor: const Color(0xFF2A2A3A),
        disabledBackgroundColor: const Color(0xFF242432),
        minimumSize: const Size(52, 52),
      ),
    );
  }
}

class _FocusGuide extends StatelessWidget {
  const _FocusGuide();

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width * .66;
    return Center(
      child: SizedBox(
        width: width,
        height: width,
        child: CustomPaint(painter: _CornerPainter()),
      ),
    );
  }
}

class _CornerPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white.withValues(alpha: .9)
      ..strokeWidth = 3
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    const length = 30.0;
    final path = Path()
      ..moveTo(0, length)
      ..lineTo(0, 0)
      ..lineTo(length, 0)
      ..moveTo(size.width - length, 0)
      ..lineTo(size.width, 0)
      ..lineTo(size.width, length)
      ..moveTo(size.width, size.height - length)
      ..lineTo(size.width, size.height)
      ..lineTo(size.width - length, size.height)
      ..moveTo(length, size.height)
      ..lineTo(0, size.height)
      ..lineTo(0, size.height - length);
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
