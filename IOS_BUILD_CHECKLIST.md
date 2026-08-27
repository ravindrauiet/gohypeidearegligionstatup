# ✅ iOS Build Checklist

## Before You Start
- [ ] Mac computer ready
- [ ] Project files transferred to Mac
- [ ] Internet connection available

## Installation Steps
- [ ] Install Xcode from Mac App Store
- [ ] Install Flutter (if not already installed)
- [ ] Accept Xcode license: `sudo xcodebuild -license accept`
- [ ] Verify installation: `flutter doctor`

## Build Process
- [ ] Navigate to project: `cd pujakaroapp`
- [ ] Get dependencies: `flutter pub get`
- [ ] Build for simulator: `flutter build ios --simulator`
- [ ] Build for device: `flutter build ios --release`
- [ ] Build IPA: `flutter build ipa --release`

## Testing
- [ ] Test on iOS Simulator
- [ ] Verify app functionality
- [ ] Check for any crashes or errors

## Distribution (Optional)
- [ ] Update Bundle Identifier in Xcode
- [ ] Update Team ID in ExportOptions.plist
- [ ] Build final IPA with export options
- [ ] Upload to TestFlight/App Store

## Quick Commands Reference
```bash
# Check status
flutter doctor

# Build everything
./build_ios.sh

# Test on simulator
flutter run -d "iPhone 15 Pro"

# Open in Xcode
open ios/Runner.xcworkspace
```

---
**Status: [ ] Not Started | [ ] In Progress | [ ] Completed**




