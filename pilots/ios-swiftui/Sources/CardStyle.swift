struct CardStyle: Equatable, Codable {
    var cornerRadius: Double
    var spacing: Double
    var padding: Double

    static let shipped = CardStyle(cornerRadius: 12, spacing: 8, padding: 16)
}
