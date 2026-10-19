import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';

/// Where [AminotesController.pickImage] gets a photo from.
enum AminotesImageSource {
  /// The phone's photos (the system photo picker on Android).
  gallery,

  /// Take a new photo.
  camera,
}

/// A photo the user picked.
@immutable
class PickedImage {
  const PickedImage({required this.bytes, required this.name, this.webUrl});

  /// The image file's contents, already scaled down.
  final Uint8List bytes;

  /// The original file name (its extension is kept).
  final String name;

  /// On the web: a `blob:` URL for the picked file.
  final String? webUrl;
}

/// Picks one photo, or returns null if the user cancelled.
typedef AminotesImagePicker = Future<PickedImage?> Function(AminotesImageSource source);

/// Photos are scaled down to this size (longest side) and re-compressed, so a
/// 12 MP camera photo becomes a few hundred KB.
const maxImageDimension = 2048.0;

/// The picker `AminotesController.pickImage` uses: the system gallery or
/// camera, scaled to [maxImageDimension] px at 85% JPEG quality.
Future<PickedImage?> defaultImagePicker(AminotesImageSource source) async {
  final file = await ImagePicker().pickImage(
    source: source == AminotesImageSource.camera ? ImageSource.camera : ImageSource.gallery,
    maxWidth: maxImageDimension,
    maxHeight: maxImageDimension,
    imageQuality: 85,
  );
  if (file == null) return null;
  return PickedImage(bytes: await file.readAsBytes(), name: file.name, webUrl: kIsWeb ? file.path : null);
}

/// A safe file extension for an image name; `jpg` if unknown.
String imageExtension(String name) {
  final extension = name.contains('.') ? name.split('.').last.toLowerCase() : '';
  return const {'jpg', 'jpeg', 'png', 'gif', 'webp', 'heic'}.contains(extension) ? extension : 'jpg';
}
