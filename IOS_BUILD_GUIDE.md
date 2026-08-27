# 🍎 iOS Build Guide for Pujakaro App

This guide will help you build the Pujakaro app for iOS using a Mac device.

## 📋 Prerequisites

- **Mac Computer** (MacBook, iMac, Mac mini, or Mac Pro)
- **macOS** (preferably latest version)
- **Xcode** (latest version from Mac App Store)
- **Apple Developer Account** (for distribution)

## 🚀 Quick Start

### 1. Transfer Project to Mac

**Option A: Using Git (Recommended)**
```bash
git clone <your-repository-url>
cd pujakaroapp
```

**Option B: Using USB/Cloud Storage**
- Copy the entire `pujakaroapp` folder to Mac

### 2. Install Required Software

#### Install Xcode
1. Open **Mac App Store**
2. Search for "Xcode"
3. Click **Install** (free, but large ~15GB)
4. Wait for download and installation to complete

#### Install Flutter
```bash
# Open Terminal on Mac
git clone https://github.com/flutter/flutter.git
export PATH="$PATH:`pwd`/flutter/bin"

# Add to PATH permanently
echo 'export PATH="$PATH:$HOME/flutter/bin"' >> ~/.zshrc
source ~/.zshrc
```

### 3. Verify Installation
```bash
flutter doctor
```

**Expected Output:**
```
Doctor summary (to see all details, run flutter doctor -v):
[✓] Flutter (Channel stable, 3.x.x, on macOS 14.x.x)
[✓] macOS version (Installed version of macOS is 14.x.x)
[✓] Xcode - develop for iOS and macOS (Xcode 15.x)
[✓] iOS toolchain - develop for iOS (Xcode 15.x)
[✓] Android toolchain - develop for Android devices
[✓] Chrome - develop for the web
[✓] VS Code (version 1.x.x)
[✓] Connected device (1 available)
[✓] Network resources

• No issues found!
```

### 4. Accept Xcode License
```bash
sudo xcodebuild -license accept
```

## 🏗️ Building Your App

### Method 1: Using the Build Script (Recommended)

```bash
# Make script executable
chmod +x build_ios.sh

# Run the build script
./build_ios.sh
```

### Method 2: Manual Commands

```bash
# Navigate to project
cd pujakaroapp

# Get dependencies
flutter pub get

# Build for iOS Simulator (testing)
flutter build ios --simulator

# Build for iOS Device (release)
flutter build ios --release

# Build IPA file (for distribution)
flutter build ipa --release
```

## 📱 Testing Your App

### Run on iOS Simulator
```bash
# List available simulators
flutter devices

# Run on specific simulator
flutter run -d "iPhone 15 Pro"
```

### Open in Xcode
```bash
open ios/Runner.xcworkspace
```

## 📦 Distribution

### For TestFlight/App Store
1. **Update Bundle Identifier** in Xcode:
   - Open `ios/Runner.xcodeproj`
   - Select "Runner" project
   - Change Bundle Identifier to something unique (e.g., `com.yourcompany.pujakaro`)

2. **Update Team ID** in `ios/ExportOptions.plist`:
   - Replace `YOUR_TEAM_ID` with your actual Apple Developer Team ID

3. **Build IPA**:
   ```bash
   flutter build ipa --release --export-options-plist=ios/ExportOptions.plist
   ```

4. **Upload to App Store Connect**:
   - Use Xcode or Application Loader
   - Or use `flutter build ipa` and upload manually

## 🔧 Troubleshooting

### Common Issues

**Issue: "No iOS development team specified"**
- Solution: Open Xcode, select Runner project, and set your Team ID

**Issue: "Failed to build iOS project"**
- Solution: Run `flutter clean` and `flutter pub get`

**Issue: "Xcode license not accepted"**
- Solution: Run `sudo xcodebuild -license accept`

**Issue: "Flutter not found"**
- Solution: Add Flutter to PATH: `export PATH="$PATH:$HOME/flutter/bin"`

### Get Help
```bash
# Check Flutter status
flutter doctor -v

# Check iOS build status
flutter build ios --verbose

# Clean and rebuild
flutter clean
flutter pub get
flutter build ios
```

## 📁 Build Outputs

After successful build, you'll find:
- **Simulator build**: `build/ios/iphonesimulator/`
- **Device build**: `build/ios/iphoneos/`
- **IPA file**: `build/ios/ipa/`

## 🎯 Next Steps

1. ✅ **Test on Simulator** - Ensure app works correctly
2. ✅ **Test on Device** - Use TestFlight for beta testing
3. ✅ **Submit to App Store** - Follow Apple's guidelines
4. ✅ **Monitor Analytics** - Track user engagement

## 📞 Support

If you encounter issues:
1. Check `flutter doctor` output
2. Review Xcode error logs
3. Check Flutter GitHub issues
4. Consult Apple Developer documentation

---

**Happy iOS Development! 🚀**




