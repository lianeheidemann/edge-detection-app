import 'dart:io';

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
      if (originalImage == null) throw StateError('Imagem inválida');

      final grayscale = img.grayscale(originalImage);
      final folder = File(widget.imagePath).parent.path;
      final grayscaleFile = File('$folder/grayscale.png')
        ..writeAsBytesSync(img.encodePng(grayscale));

      final edgeDetected = img.Image.from(grayscale);
      for (int y = 1; y < grayscale.height - 1; y++) {
        for (int x = 1; x < grayscale.width - 1; x++) {
          final left = grayscale.getPixel(x - 1, y).r.toInt();
          final right = grayscale.getPixel(x + 1, y).r.toInt();
          final edgeValue = (right - left).abs() > 25 ? 255 : 0;
          edgeDetected.setPixelRgb(x, y, edgeValue, edgeValue, edgeValue);
        }
      }

      final edgeFile = File('$folder/edges.png')
        ..writeAsBytesSync(img.encodePng(edgeDetected));
      if (!mounted) return;
      setState(() {
        _grayscaleImage = grayscaleFile;
        _edgeImage = edgeFile;
        _isProcessing = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _errorMessage = 'Não foi possível processar esta imagem.';
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
        title: const Text('Resultado da análise'),
        actions: [
          IconButton(
            tooltip: 'Nova foto',
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
                      'Compare as etapas',
                      style: Theme.of(context).textTheme.headlineSmall
                          ?.copyWith(
                            fontWeight: FontWeight.w800,
                            color: const Color(0xFF24243A),
                          ),
                    ),
                    const SizedBox(height: 6),
                    const Text(
                      'Veja como a imagem muda durante o processamento.',
                      style: TextStyle(color: Color(0xFF68687A)),
                    ),
                    const SizedBox(height: 20),
                    SegmentedButton<int>(
                      showSelectedIcon: false,
                      segments: const [
                        ButtonSegment(value: 0, label: Text('Original')),
                        ButtonSegment(value: 1, label: Text('Cinza')),
                        ButtonSegment(value: 2, label: Text('Bordas')),
                      ],
                      selected: {_selectedView},
                      onSelectionChanged: (selection) {
                        setState(() => _selectedView = selection.first);
                      },
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
                      label: const Text('Capturar nova imagem'),
                    ),
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
    'Imagem original',
    'Tons de cinza',
    'Bordas detectadas',
  ];
  static const _descriptions = [
    'Imagem capturada pela câmera, antes do processamento.',
    'As cores foram convertidas em intensidades de luminosidade.',
    'As mudanças mais fortes de intensidade aparecem destacadas.',
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
              selectedView == 2 ? Icons.auto_awesome : Icons.image_outlined,
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
            'Detectando bordas…',
            style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
          ),
          SizedBox(height: 6),
          Text('Isso pode levar alguns segundos.'),
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
              child: const Text('Voltar para a câmera'),
            ),
          ],
        ),
      ),
    );
  }
}
