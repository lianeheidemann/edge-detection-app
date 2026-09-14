import 'dart:io';

import 'package:edge_detection/edge_detection.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;

class ResultPage extends StatefulWidget {
  const ResultPage({super.key, required this.imagePath});

  final String imagePath;

  @override
  State<ResultPage> createState() => _ResultPageState();
}

class _ResultPageState extends State<ResultPage> {
  File? _grayscaleImage;
  File? _edgeImage;
  bool _isProcessing = true;
  String? _errorMessage;
  int _selectedView = 2;

  @override
  void initState() {
    super.initState();
    _processImage();
  }

  Future<void> _processImage() async {
    try {
      final originalBytes = await File(widget.imagePath).readAsBytes();
      final originalImage = img.decodeImage(originalBytes);
      if (originalImage == null) throw StateError('Invalid image');

      final grayscale = img.grayscale(img.Image.from(originalImage));
      final folder = File(widget.imagePath).parent.path;
      final grayscaleFile = File('$folder/grayscale.png')
        ..writeAsBytesSync(img.encodePng(grayscale));

      final edgePngBytes = await compute(_detectEdgesPng, originalImage);
      final edgeFile = File('$folder/edges.png')
        ..writeAsBytesSync(edgePngBytes);
      if (!mounted) return;
      setState(() {
        _grayscaleImage = grayscaleFile;
        _edgeImage = edgeFile;
        _isProcessing = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _errorMessage = 'Could not process this image.';
        _isProcessing = false;
      });
    }
  }

  List<File?> get _images => [
    File(widget.imagePath),
    _grayscaleImage,
    _edgeImage,
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Analysis results'),
        actions: [
          IconButton(
            tooltip: 'New photo',
            onPressed: () => Navigator.pop(context),
            icon: const Icon(Icons.camera_alt_outlined),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: _isProcessing
          ? const _ProcessingView()
          : _errorMessage != null
          ? _ErrorView(message: _errorMessage!)
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      'Compare the stages',
                      style: Theme.of(context).textTheme.headlineSmall
                          ?.copyWith(
                            fontWeight: FontWeight.w800,
                            color: const Color(0xFF24243A),
                          ),
                    ),
                    const SizedBox(height: 6),
                    const Text(
                      'See how the image changes during processing.',
                      style: TextStyle(color: Color(0xFF68687A)),
                    ),
                    const SizedBox(height: 20),
                    Row(
                      children: List.generate(3, (index) {
                        const labels = ['Original', 'Grayscale', 'Edges'];
                        return Expanded(
                          child: Padding(
                            padding: EdgeInsets.only(
                              right: index < 2 ? 8 : 0,
                            ),
                            child: _ResultThumbnail(
                              label: labels[index],
                              image: _images[index]!,
                              isSelected: _selectedView == index,
                              onTap: () {
                                setState(() => _selectedView = index);
                              },
                            ),
                          ),
                        );
                      }),
                    ),
                    const SizedBox(height: 20),
                    Expanded(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(24),
                        child: ColoredBox(
                          color: const Color(0xFF151520),
                          child: AnimatedSwitcher(
                            duration: const Duration(milliseconds: 220),
                            child: InteractiveViewer(
                              key: ValueKey(_selectedView),
                              minScale: 1,
                              maxScale: 4,
                              child: Center(
                                child: Image.file(
                                  _images[_selectedView]!,
                                  fit: BoxFit.contain,
                                  width: double.infinity,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    _InfoPanel(selectedView: _selectedView),
                    const SizedBox(height: 16),
                    FilledButton.icon(
                      style: FilledButton.styleFrom(
                        minimumSize: const Size.fromHeight(54),
                      ),
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.camera_alt_rounded),
                      label: const Text('Capture a new image'),
                    ),
                  ],
                ),
              ),
            ),
    );
  }
}

/// Runs the Canny-style edge detection pipeline and encodes the result as
/// PNG bytes. Must stay top-level (no closures over State/BuildContext) so
/// it can be dispatched to a background isolate via [compute].
Uint8List _detectEdgesPng(img.Image source) {
  return img.encodePng(detectEdges(source));
}

class _ResultThumbnail extends StatelessWidget {
  const _ResultThumbnail({
    required this.label,
    required this.image,
    required this.isSelected,
    required this.onTap,
  });

  final String label;
  final File image;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    return Semantics(
      button: true,
      selected: isSelected,
      label: 'Exibir $label',
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.all(3),
          decoration: BoxDecoration(
            color: isSelected ? primary : const Color(0xFFE8E8F0),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Column(
            children: [
              AspectRatio(
                aspectRatio: 1.25,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: ColoredBox(
                    color: const Color(0xFF151520),
                    child: Image.file(image, fit: BoxFit.cover),
                  ),
                ),
              ),
              const SizedBox(height: 5),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: isSelected ? Colors.white : const Color(0xFF24243A),
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 2),
            ],
          ),
        ),
      ),
    );
  }
}

class _InfoPanel extends StatelessWidget {
  const _InfoPanel({required this.selectedView});

  final int selectedView;
  static const _titles = [
    'Original image',
    'Grayscale',
    'Detected edges',
  ];
  static const _descriptions = [
    'Image captured by the camera before processing.',
    'Colors were converted into brightness intensities.',
    'The strongest intensity changes are highlighted.',
  ];

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.primaryContainer
            .withValues(alpha: .55),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Icon(
              selectedView == 2 ? Icons.search_rounded : Icons.image_outlined,
              color: Theme.of(context).colorScheme.primary,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _titles[selectedView],
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    _descriptions[selectedView],
                    style: const TextStyle(fontSize: 13, height: 1.35),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ProcessingView extends StatelessWidget {
  const _ProcessingView();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          CircularProgressIndicator(),
          SizedBox(height: 20),
          Text(
            'Detecting edges…',
            style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
          ),
          SizedBox(height: 6),
          Text('This may take a few seconds.'),
        ],
      ),
    );
  }
}

class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, size: 48),
            const SizedBox(height: 16),
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 20),
            FilledButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Back to camera'),
            ),
          ],
        ),
      ),
    );
  }
}
