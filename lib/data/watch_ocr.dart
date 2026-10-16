import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

/// Plan 058 (§16.17): lee el texto de una captura del reloj en el teléfono
/// (ML Kit, modelo latino incluido en el APK; la imagen no sale del
/// teléfono). Separado para poder reemplazarlo en pruebas.
abstract class WatchTextReader {
  Future<String> read(String imagePath);
}

class MlKitWatchTextReader implements WatchTextReader {
  const MlKitWatchTextReader();

  @override
  Future<String> read(String imagePath) async {
    final recognizer = TextRecognizer(script: TextRecognitionScript.latin);
    try {
      final result =
          await recognizer.processImage(InputImage.fromFilePath(imagePath));
      return result.text;
    } finally {
      await recognizer.close();
    }
  }
}

final watchTextReaderProvider =
    Provider<WatchTextReader>((ref) => const MlKitWatchTextReader());
