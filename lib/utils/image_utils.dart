class ImageUtils {
  /// Normalizes image paths to ensure they have the correct format
  /// Handles cases where the path might already include 'assets/images/' or just be a filename
  static String normalizeImagePath(String? imagePath) {
    if (imagePath == null || imagePath.isEmpty) {
      return 'assets/images/satyanarayan.jpg'; // Default fallback
    }
    
    // Remove leading slashes and clean up the path
    String cleanPath = imagePath.trim();
    while (cleanPath.startsWith('/')) {
      cleanPath = cleanPath.substring(1);
    }
    
    // Handle double paths like "assets/assets/images//images/featuredPuja.jpg"
    if (cleanPath.contains('assets/assets/images//images/')) {
      cleanPath = cleanPath.replaceAll('assets/assets/images//images/', 'assets/images/');
    }
    
    // Handle double paths like "assets/images//images/featuredPuja.jpg"
    if (cleanPath.contains('assets/images//images/')) {
      cleanPath = cleanPath.replaceAll('assets/images//images/', 'assets/images/');
    }
    
    // Handle paths that start with just 'images/' (missing 'assets/')
    if (cleanPath.startsWith('images/')) {
      cleanPath = 'assets/$cleanPath';
    }
    
    // If the path already starts with 'assets/images/', return as is
    if (cleanPath.startsWith('assets/images/')) {
      return cleanPath;
    }
    
    // If it's just a filename, prepend the assets path
    return 'assets/images/$cleanPath';
  }
} 