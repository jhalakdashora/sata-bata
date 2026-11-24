import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:image_picker/image_picker.dart';
import 'package:split_app/features/receipts/domain/receipt_parser.dart';

class ScannedReceipt {
  const new({required this.imagePath, required this.draft});
  final String imagePath;
  final ReceiptDraft draft;
}

enum ReceiptSource { camera, gallery }

abstract interface class ReceiptScanner {
  /// Returns null if the user cancels picking an image.
  Future<ScannedReceipt?> scan(ReceiptSource source);
}

/// On-device OCR with Google ML Kit (free, offline, Android and iOS).
class MlKitReceiptScanner implements ReceiptScanner {
  final _picker = ImagePicker();

  @override
  Future<ScannedReceipt?> scan(ReceiptSource source) async {
    final file = await _picker.pickImage(
      source: source == ReceiptSource.camera
          ? ImageSource.camera
          : ImageSource.gallery,
      maxWidth: 2000,
      imageQuality: 85,
    );
    if (file == null) return null;

    final recognizer = TextRecognizer();
    try {
      final text = await recognizer.processImage(
        InputImage.fromFilePath(file.path),
      );
      // Sort lines top-to-bottom, then left-to-right, so "Item ... 4.50"
      // reads in receipt order even when ML Kit splits columns into blocks.
      final lines = [for (final b in text.blocks) ...b.lines]
        ..sort((a, b) {
          final dy = a.boundingBox.center.dy - b.boundingBox.center.dy;
          if (dy.abs() > a.boundingBox.height / 2) return dy.sign.toInt();
          return a.boundingBox.left.compareTo(b.boundingBox.left);
        });
      return ScannedReceipt(
        imagePath: file.path,
        draft: ReceiptParser.parse(_mergeRows(lines)),
      );
    } finally {
      await recognizer.close();
    }
  }

  /// Joins lines on the same visual row ("Lemonade" ... "3.50").
  static List<String> _mergeRows(List<TextLine> lines) {
    final rows = <String>[];
    TextLine? previous;
    for (final line in lines) {
      final sameRow =
          previous != null &&
          (line.boundingBox.center.dy - previous.boundingBox.center.dy).abs() <
              previous.boundingBox.height / 2;
      if (sameRow) {
        rows[rows.length - 1] = '${rows.last} ${line.text}';
      } else {
        rows.add(line.text);
      }
      previous = line;
    }
    return rows;
  }
}
