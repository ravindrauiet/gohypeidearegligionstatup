import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';

/// Takes a front-camera selfie and returns compressed JPEG bytes (or null if
/// the user cancelled). Behind an interface so tests can fake the camera.
abstract class SelfiePicker {
  Future<Uint8List?> takeSelfie();
}

/// image_picker: front camera, max 720 px wide, JPEG quality 70.
class ImagePickerSelfiePicker implements SelfiePicker {
  final ImagePicker _picker;
  ImagePickerSelfiePicker([ImagePicker? picker]) : _picker = picker ?? ImagePicker();

  @override
  Future<Uint8List?> takeSelfie() async {
    final file = await _picker.pickImage(
      source: ImageSource.camera,
      preferredCameraDevice: CameraDevice.front,
      maxWidth: 720,
      maxHeight: 960,
      imageQuality: 70,
      requestFullMetadata: false,
    );
    if (file == null) return null;
    return file.readAsBytes();
  }
}
