import 'dart:convert';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:http/http.dart' as http;

class StorageService {
  /// Uploads an image given either a Data URL (web) or an http(s) URL.
  /// Returns the download URL on success, or null on failure.
  static Future<String?> uploadImageFromDataUrl(String dataUrlOrUrl,
      {String? filenamePrefix}) async {
    try {
      final _storage = FirebaseStorage.instance;
      final refName =
          '${filenamePrefix ?? 'spot'}_${DateTime.now().millisecondsSinceEpoch}.jpg';
      final ref = _storage.ref().child('user_spot_photos').child(refName);

      if (dataUrlOrUrl.startsWith('data:')) {
        // Web data URL
        await ref.putString(dataUrlOrUrl, format: PutStringFormat.dataUrl);
      } else if (dataUrlOrUrl.startsWith('http')) {
        // Remote HTTP image: fetch bytes and upload
        final resp = await http.get(Uri.parse(dataUrlOrUrl));
        if (resp.statusCode != 200) return null;
        final bytes = resp.bodyBytes;
        await ref.putData(
            bytes,
            SettableMetadata(
                contentType: resp.headers['content-type'] ?? 'image/jpeg'));
      } else {
        // Unknown format: treat as bytes base64
        try {
          final bytes = base64Decode(dataUrlOrUrl);
          await ref.putData(bytes, SettableMetadata(contentType: 'image/jpeg'));
        } catch (_) {
          return null;
        }
      }

      final url = await ref.getDownloadURL();
      return url;
    } catch (e) {
      // swallow and return null on failure
      return null;
    }
  }
}
