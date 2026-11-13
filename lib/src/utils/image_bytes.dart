import '../models/network_entry.dart';
import 'network_formatters.dart';

/// Largest image whose bytes are kept for a preview.
const int kImageMaxBytes = 5 * 1024 * 1024;

/// Preview bytes kept across all network entries; the oldest lose theirs first.
const int kImageBudgetBytes = 50 * 1024 * 1024;

/// Bytes needed to recognise every supported signature (BMP's DIB size ends
/// at offset 18).
const int kImageSniffBytes = 18;

const _png = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A];
const _jpeg = [0xFF, 0xD8, 0xFF];
const _gif87a = [0x47, 0x49, 0x46, 0x38, 0x37, 0x61];
const _gif89a = [0x47, 0x49, 0x46, 0x38, 0x39, 0x61];
const _riff = [0x52, 0x49, 0x46, 0x46];
const _webp = [0x57, 0x45, 0x42, 0x50];
const _bm = [0x42, 0x4D];
// BITMAPCOREHEADER, OS/2 v2 and BITMAPINFOHEADER through V5. Checking the
// header size keeps a text body that happens to start with "BM" out.
const _dibHeaderSizes = {12, 16, 40, 52, 56, 64, 108, 124};

/// MIME type of an image `Image.memory` can decode, judged only by the
/// leading signature of [bytes] (never by `Content-Type`); `null` otherwise,
/// SVG included.
String? imageMimeType(List<int> bytes) {
  bool at(int offset, List<int> signature) {
    if (bytes.length < offset + signature.length) return false;
    for (var i = 0; i < signature.length; i++) {
      if (bytes[offset + i] != signature[i]) return false;
    }
    return true;
  }

  if (at(0, _png)) return 'image/png';
  if (at(0, _jpeg)) return 'image/jpeg';
  if (at(0, _gif87a) || at(0, _gif89a)) return 'image/gif';
  if (at(0, _riff) && at(8, _webp)) return 'image/webp';
  if (at(0, _bm) && bytes.length >= kImageSniffBytes) {
    final dib = bytes[14] | bytes[15] << 8 | bytes[16] << 16 | bytes[17] << 24;
    if (_dibHeaderSizes.contains(dib)) return 'image/bmp';
  }
  return null;
}

/// Body text recorded for an image. The marker keeps Resend disabled and tags
/// the body as a summary, like `[binary N bytes]`.
String imageSummary(String mime, int totalBytes) =>
    '[$mime, ${formatBytes(totalBytes)}]$kTruncatedMarker';
