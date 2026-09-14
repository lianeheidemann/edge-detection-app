import 'dart:typed_data';

import 'package:edge_detection/edge_detection.dart';
import 'package:flutter_test/flutter_test.dart';

Float32List verticalStep(int width, int height, int stepX) {
  final buffer = Float32List(width * height);
  for (int y = 0; y < height; y++) {
    for (int x = 0; x < width; x++) {
      buffer[y * width + x] = x < stepX ? 0 : 255;
    }
  }
  return buffer;
}

void main() {
  group('sobelGradients', () {
    test('reports a much stronger gradient at a step edge than in a flat '
        'region', () {
      final src = verticalStep(10, 10, 5);
      final result = sobelGradients(src, 10, 10);
      expect(
        result.magnitude[5 * 10 + 4],
        greaterThan(result.magnitude[5 * 10 + 1]),
      );
    });
  });

  group('detectEdgesFromBuffer', () {
    test('thins a vertical step edge to at most a couple pixels per row', () {
      final mask = detectEdgesFromBuffer(
        verticalStep(20, 20, 10),
        20,
        20,
        low: 30,
        high: 70,
      );
      for (int y = 2; y < 18; y++) {
        final edgesInRow = List.generate(
          20,
          (x) => mask[y * 20 + x],
        ).where((v) => v == 255).length;
        expect(edgesInRow, lessThanOrEqualTo(2));
      }
    });

    test('produces no edges for a uniform image', () {
      final flat = Float32List(400)..fillRange(0, 400, 128);
      final mask = detectEdgesFromBuffer(flat, 20, 20, low: 30, high: 70);
      expect(mask.every((v) => v == 0), isTrue);
    });

    test('detects a diagonal edge (missed by a horizontal-only diff)', () {
      final buffer = Float32List(20 * 20);
      for (int y = 0; y < 20; y++) {
        for (int x = 0; x < 20; x++) {
          buffer[y * 20 + x] = x > y ? 255 : 0;
        }
      }
      final mask = detectEdgesFromBuffer(buffer, 20, 20, low: 30, high: 70);
      expect(mask.any((v) => v == 255), isTrue);
    });
  });
}
