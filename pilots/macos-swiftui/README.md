# CardPaletteMac (macOS pilot)

Tiny SwiftUI fixture for evals of the ui-tuning-lab skill. It mirrors `pilots/ios-swiftui`:
a scrolling list of cards whose corner radius, spacing, and padding come from one
declared default, `CardStyle.shipped`, shown in a single "Palette" window.

Generate and build (requires xcodegen and Xcode):

    xcodegen generate
    xcodebuild -project CardPaletteMac.xcodeproj -scheme CardPaletteMac -configuration Debug \
      -destination 'platform=macOS' -derivedDataPath build build
