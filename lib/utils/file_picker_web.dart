// Web implementation of an image file picker using dart:html
import 'dart:async';
import 'dart:html' as html;

/// Opens a native file picker (web) and returns the selected image as a Data URL
/// (e.g. "data:image/png;base64,...") or null if cancelled or error.
Future<String?> pickImageFileAsDataUrl() async {
  final uploadInput = html.FileUploadInputElement();
  uploadInput.accept = 'image/*';
  uploadInput.multiple = false;
  // Trigger the file picker
  uploadInput.click();

  final completer = Completer<String?>();

  uploadInput.onChange.listen((_) {
    final files = uploadInput.files;
    if (files == null || files.isEmpty) {
      completer.complete(null);
      return;
    }
    final file = files[0];
    final reader = html.FileReader();
    reader.readAsDataUrl(file);
    reader.onLoad.listen((_) {
      final result = reader.result;
      if (result is String) {
        completer.complete(result);
      } else {
        completer.complete(null);
      }
    });
    reader.onError.listen((_) {
      completer.complete(null);
    });
  });

  return completer.future;
}
