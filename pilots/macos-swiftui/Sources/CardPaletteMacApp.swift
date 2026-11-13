import SwiftUI

@main
struct CardPaletteMacApp: App {
    var body: some Scene {
        WindowGroup("Palette") {
            CardPaletteScreen()
                .frame(minWidth: 320, minHeight: 360)
        }
        .defaultSize(width: 420, height: 560)
    }
}
