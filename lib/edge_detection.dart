import 'dart:math' as math;
import 'dart:typed_data';

import 'package:image/image.dart' as img;

/// Parameters for the Canny-style edge detection pipeline.
///
/// Threshold values are tuned for gradient magnitudes produced by the
/// multichannel (RGB) Sobel operator on an 8-bit image after a 5x5
/// (radius 2) Gaussian blur. For color-neutral content the multichannel
/// gradient magnitude is `sqrt(3)` times a single-channel (luminance-only)
/// Sobel magnitude, so these are scaled up from the single-channel values
/// that would otherwise apply (roughly 30/70). They are fixed constants
/// rather than user-tunable UI controls; adjust here if real-world
/// captures show too many/too few edges.
class CannyParams {
  const CannyParams({
    this.gaussianRadius = 2,
    this.lowThreshold = 50,
    this.highThreshold = 120,
  });

  final int gaussianRadius;
  final double lowThreshold;
  final double highThreshold;
}

/// Runs a Canny-style pipeline (Gaussian blur -> multichannel Sobel
/// gradients -> non-maximum suppression -> double-threshold hysteresis) on
/// [source] and returns a new binary (0/255) edge image with the same
/// dimensions and channel format as [source].
///
/// Gradients are computed from all three RGB channels (see
/// [colorSobelGradients]) rather than from luminance alone, so [source]
/// should be the original color image, not one already converted to
/// grayscale — a luminance-only gradient cannot see a boundary between two
/// iso-luminant colors (e.g. a colorful sunset sky).
img.Image detectEdges(
  img.Image source, {
  CannyParams params = const CannyParams(),
}) {
  final width = source.width;
  final height = source.height;

  final blurred = img.gaussianBlur(
    img.Image.from(source),
    radius: params.gaussianRadius,
  );
  final red = _extractChannel(blurred, (p) => p.r.toDouble());
  final green = _extractChannel(blurred, (p) => p.g.toDouble());
  final blue = _extractChannel(blurred, (p) => p.b.toDouble());

  final gradients = colorSobelGradients(red, green, blue, width, height);
  final thinned = nonMaxSuppression(
    gradients.magnitude,
    gradients.direction,
    width,
    height,
  );
  final mask = hysteresisThreshold(
    thinned,
    width,
    height,
    low: params.lowThreshold,
    high: params.highThreshold,
  );

  final edgeImage = img.Image.from(source);
  for (int y = 0; y < height; y++) {
    for (int x = 0; x < width; x++) {
      final value = mask[y * width + x];
      edgeImage.setPixelRgb(x, y, value, value, value);
    }
  }
  return edgeImage;
}

/// Row-major buffer (0-255) of one channel of [image], picked by [select].
Float32List _extractChannel(
  img.Image image,
  double Function(img.Pixel pixel) select,
) {
  final buffer = Float32List(image.width * image.height);
  for (int y = 0; y < image.height; y++) {
    for (int x = 0; x < image.width; x++) {
      buffer[y * image.width + x] = select(image.getPixel(x, y));
    }
  }
  return buffer;
}

class GradientResult {
  GradientResult(this.magnitude, this.direction);

  /// Per-pixel gradient magnitude.
  final Float32List magnitude;

  /// Per-pixel gradient direction in radians (atan2(gy, gx)).
  final Float32List direction;
}

class _RawGradients {
  _RawGradients(this.gx, this.gy);
  final Float32List gx;
  final Float32List gy;
}

/// Computes raw Sobel Gx/Gy over a flat [width]x[height] buffer.
/// Out-of-bounds samples are clamped to the nearest edge pixel so every
/// pixel, including borders, gets a real gradient value.
_RawGradients _sobelXY(Float32List src, int width, int height) {
  final gx = Float32List(width * height);
  final gy = Float32List(width * height);

  int clampX(int x) => x < 0 ? 0 : (x >= width ? width - 1 : x);
  int clampY(int y) => y < 0 ? 0 : (y >= height ? height - 1 : y);

  for (int y = 0; y < height; y++) {
    for (int x = 0; x < width; x++) {
      final tl = src[clampY(y - 1) * width + clampX(x - 1)];
      final tc = src[clampY(y - 1) * width + x];
      final tr = src[clampY(y - 1) * width + clampX(x + 1)];
      final ml = src[y * width + clampX(x - 1)];
      final mr = src[y * width + clampX(x + 1)];
      final bl = src[clampY(y + 1) * width + clampX(x - 1)];
      final bc = src[clampY(y + 1) * width + x];
      final br = src[clampY(y + 1) * width + clampX(x + 1)];

      final idx = y * width + x;
      gx[idx] = (tr + 2 * mr + br) - (tl + 2 * ml + bl);
      gy[idx] = (bl + 2 * bc + br) - (tl + 2 * tc + tr);
    }
  }
  return _RawGradients(gx, gy);
}

/// Computes Sobel Gx/Gy gradients over a flat [width]x[height] luminance
/// buffer, returning gradient magnitude and direction.
GradientResult sobelGradients(Float32List src, int width, int height) {
  final raw = _sobelXY(src, width, height);
  final magnitude = Float32List(width * height);
  final direction = Float32List(width * height);
  for (int i = 0; i < magnitude.length; i++) {
    final gx = raw.gx[i];
    final gy = raw.gy[i];
    magnitude[i] = math.sqrt(gx * gx + gy * gy);
    direction[i] = math.atan2(gy, gx);
  }
  return GradientResult(magnitude, direction);
}

/// Combines per-channel Sobel gradients into a single magnitude/direction
/// field using the Di Zenzo (1986) multichannel gradient: the direction of
/// steepest combined change across channels and its magnitude, derived
/// from the 2x2 structure tensor summed over channels. Unlike converting
/// to grayscale first, this correctly detects boundaries between
/// iso-luminant colors (e.g. a colorful sunset sky) that a luminance-only
/// gradient cannot see.
GradientResult colorSobelGradients(
  Float32List red,
  Float32List green,
  Float32List blue,
  int width,
  int height,
) {
  final r = _sobelXY(red, width, height);
  final g = _sobelXY(green, width, height);
  final b = _sobelXY(blue, width, height);

  final magnitude = Float32List(width * height);
  final direction = Float32List(width * height);
  for (int i = 0; i < magnitude.length; i++) {
    final gxx = r.gx[i] * r.gx[i] + g.gx[i] * g.gx[i] + b.gx[i] * b.gx[i];
    final gyy = r.gy[i] * r.gy[i] + g.gy[i] * g.gy[i] + b.gy[i] * b.gy[i];
    final gxy = r.gx[i] * r.gy[i] + g.gx[i] * g.gy[i] + b.gx[i] * b.gy[i];

    final diff = gxx - gyy;
    final f = 0.5 * (gxx + gyy + math.sqrt(diff * diff + 4 * gxy * gxy));

    magnitude[i] = math.sqrt(f < 0 ? 0 : f);
    direction[i] = 0.5 * math.atan2(2 * gxy, diff);
  }
  return GradientResult(magnitude, direction);
}

/// Thins edges to single-pixel width by suppressing gradient magnitudes
/// that are not local maxima along their own gradient direction.
Float32List nonMaxSuppression(
  Float32List magnitude,
  Float32List direction,
  int width,
  int height,
) {
  final out = Float32List(width * height);
  for (int y = 0; y < height; y++) {
    for (int x = 0; x < width; x++) {
      final idx = y * width + x;
      if (x == 0 || x == width - 1 || y == 0 || y == height - 1) {
        // No full 3x3 neighborhood available; keep the raw magnitude
        // rather than force-zeroing the border.
        out[idx] = magnitude[idx];
        continue;
      }

      final angleDeg = direction[idx] * 180 / math.pi;
      final a = angleDeg < 0 ? angleDeg + 180 : angleDeg;

      double n1, n2;
      if (a < 22.5 || a >= 157.5) {
        n1 = magnitude[idx - 1];
        n2 = magnitude[idx + 1];
      } else if (a < 67.5) {
        n1 = magnitude[idx - width + 1];
        n2 = magnitude[idx + width - 1];
      } else if (a < 112.5) {
        n1 = magnitude[idx - width];
        n2 = magnitude[idx + width];
      } else {
        n1 = magnitude[idx - width - 1];
        n2 = magnitude[idx + width + 1];
      }

      out[idx] = (magnitude[idx] >= n1 && magnitude[idx] >= n2)
          ? magnitude[idx]
          : 0;
    }
  }
  return out;
}

/// Double-threshold hysteresis: pixels at or above [high] are strong edges;
/// pixels at or above [low] that are 8-connected (directly or transitively)
/// to a strong edge are promoted to edges too. Everything else is
/// suppressed. Uses an explicit stack instead of recursion to stay safe on
/// large images.
Uint8List hysteresisThreshold(
  Float32List suppressed,
  int width,
  int height, {
  required double low,
  required double high,
}) {
  final result = Uint8List(width * height);
  final visited = Uint8List(width * height);
  final stack = <int>[];

  for (int i = 0; i < suppressed.length; i++) {
    if (suppressed[i] >= high) {
      result[i] = 255;
      stack.add(i);
    }
  }

  while (stack.isNotEmpty) {
    final idx = stack.removeLast();
    if (visited[idx] == 1) continue;
    visited[idx] = 1;
    final x = idx % width;
    final y = idx ~/ width;
    for (int dy = -1; dy <= 1; dy++) {
      for (int dx = -1; dx <= 1; dx++) {
        if (dx == 0 && dy == 0) continue;
        final nx = x + dx;
        final ny = y + dy;
        if (nx < 0 || nx >= width || ny < 0 || ny >= height) continue;
        final nIdx = ny * width + nx;
        if (result[nIdx] == 0 && suppressed[nIdx] >= low) {
          result[nIdx] = 255;
          stack.add(nIdx);
        }
      }
    }
  }
  return result;
}

/// Runs Sobel -> non-maximum suppression -> hysteresis on a flat luminance
/// buffer and returns a binary (0/255) edge mask of the same dimensions.
/// Exposed separately from [detectEdges] so the single-channel algorithm
/// can be unit tested without going through [img.Image] decoding/encoding.
Uint8List detectEdgesFromBuffer(
  Float32List luminance,
  int width,
  int height, {
  required double low,
  required double high,
}) {
  final gradients = sobelGradients(luminance, width, height);
  final thinned = nonMaxSuppression(
    gradients.magnitude,
    gradients.direction,
    width,
    height,
  );
  return hysteresisThreshold(thinned, width, height, low: low, high: high);
}
