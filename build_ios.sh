#!/bin/bash

echo "🚀 Starting iOS Build Process for Pujakaro App"
echo "=============================================="

# Check if Flutter is installed
if ! command -v flutter &> /dev/null; then
    echo "❌ Flutter not found. Please install Flutter first."
    echo "Run: git clone https://github.com/flutter/flutter.git"
    echo "Then add to PATH: export PATH=\"\$PATH:\$HOME/flutter/bin\""
    exit 1
fi

# Check if Xcode is installed
if ! command -v xcodebuild &> /dev/null; then
    echo "❌ Xcode not found. Please install Xcode from Mac App Store."
    exit 1
fi

echo "✅ Flutter and Xcode found"
echo ""

# Get dependencies
echo "📦 Getting Flutter dependencies..."
flutter pub get

if [ $? -ne 0 ]; then
    echo "❌ Failed to get dependencies"
    exit 1
fi

echo "✅ Dependencies installed"
echo ""

# Clean previous builds
echo "🧹 Cleaning previous builds..."
flutter clean
flutter pub get

echo "✅ Cleaned previous builds"
echo ""

# Build for iOS Simulator (for testing)
echo "📱 Building for iOS Simulator..."
flutter build ios --simulator

if [ $? -ne 0 ]; then
    echo "❌ Failed to build for simulator"
    exit 1
fi

echo "✅ Simulator build successful"
echo ""

# Build for iOS Device (Release)
echo "📱 Building for iOS Device (Release)..."
flutter build ios --release

if [ $? -ne 0 ]; then
    echo "❌ Failed to build for device"
    exit 1
fi

echo "✅ Device build successful"
echo ""

# Build IPA file
echo "📦 Building IPA file..."
flutter build ipa --release

if [ $? -ne 0 ]; then
    echo "❌ Failed to build IPA"
    exit 1
fi

echo "✅ IPA build successful"
echo ""

# Show build results
echo "🎉 Build completed successfully!"
echo ""
echo "📁 Build outputs:"
echo "   - Simulator build: build/ios/iphonesimulator/"
echo "   - Device build: build/ios/iphoneos/"
echo "   - IPA file: build/ios/ipa/"
echo ""
echo "🚀 Next steps:"
echo "   1. Test on simulator: flutter run -d 'iPhone 15 Pro'"
echo "   2. Open in Xcode: open ios/Runner.xcworkspace"
echo "   3. Upload to TestFlight/App Store"
echo ""
echo "✨ Happy coding!"




