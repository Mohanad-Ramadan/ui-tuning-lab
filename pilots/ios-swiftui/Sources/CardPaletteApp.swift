import SwiftUI

@main
struct CardPaletteApp: App {
    var body: some Scene {
        WindowGroup {
            NavigationStack {
                CardPaletteScreen()
                    .navigationTitle("Palette")
            }
        }
    }
}
