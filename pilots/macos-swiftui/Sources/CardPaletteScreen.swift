import SwiftUI

struct Swatch: Identifiable {
    let name: String
    let hex: String
    let color: Color

    var id: String { name }
}

private let swatches = [
    Swatch(name: "Brass", hex: "#B5A642", color: Color(red: 0xB5 / 255, green: 0xA6 / 255, blue: 0x42 / 255)),
    Swatch(name: "Teal", hex: "#2A7F8E", color: Color(red: 0x2A / 255, green: 0x7F / 255, blue: 0x8E / 255)),
    Swatch(name: "Coral", hex: "#E4694F", color: Color(red: 0xE4 / 255, green: 0x69 / 255, blue: 0x4F / 255)),
    Swatch(name: "Plum", hex: "#6B3FA0", color: Color(red: 0x6B / 255, green: 0x3F / 255, blue: 0xA0 / 255)),
    Swatch(name: "Moss", hex: "#5B7F3A", color: Color(red: 0x5B / 255, green: 0x7F / 255, blue: 0x3A / 255)),
    Swatch(name: "Slate", hex: "#4A5568", color: Color(red: 0x4A / 255, green: 0x55 / 255, blue: 0x68 / 255)),
]

struct CardPaletteScreen: View {
    let style = CardStyle.shipped

    var body: some View {
        ScrollView {
            VStack(spacing: style.spacing) {
                ForEach(swatches) { swatch in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(swatch.name)
                            .font(.headline)
                        Text(swatch.hex)
                            .font(.subheadline)
                    }
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(style.padding)
                    .background(swatch.color, in: RoundedRectangle(cornerRadius: style.cornerRadius))
                }
            }
            .padding(.horizontal)
        }
    }
}
