# CardPalette (iOS pilot)

Tiny SwiftUI fixture for evals of the ui-tuning-lab skill. It mirrors `pilots/web-vite`:
a scrolling list of cards whose corner radius, spacing, and padding come from one
declared default, `CardStyle.shipped`.

Generate and build (requires xcodegen and Xcode):

    xcodegen generate
    xcodebuild -project CardPalette.xcodeproj -scheme CardPalette -configuration Debug \
      -destination 'platform=iOS Simulator,name=iPhone 18 Pro Max' -derivedDataPath build build
