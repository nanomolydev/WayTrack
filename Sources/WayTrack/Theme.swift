import SwiftUI

extension Color {
    init(hex: String) {
        let raw = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        let value = UInt64(raw, radix: 16) ?? 0x8E8E93
        self.init(.sRGB,
                  red: Double((value >> 16) & 0xFF) / 255,
                  green: Double((value >> 8) & 0xFF) / 255,
                  blue: Double(value & 0xFF) / 255)
    }
}

enum Theme {
    static let background = Color(hex: "0B0B10")
    static let flask = Color.white.opacity(0.05)
    static let flaskEdge = Color.white.opacity(0.12)
    static let ink = Color.white
    static let faint = Color.white.opacity(0.45)

    /// Палитра для новых задач.
    static let palette = ["FF9F0A", "0A84FF", "30D158", "BF5AF2", "FF375F", "64D2FF", "FFD60A"]

    static func opacity(for kind: SegmentKind) -> Double {
        switch kind {
        case .cycle: return 1.0
        case .rest: return 0.38
        case .pause: return 0.20
        }
    }
}

func clockString(_ minute: Int) -> String {
    let m = max(0, min(minutesInDay, minute))
    return String(format: "%d:%02d", m / 60, m % 60)
}

func currentMinute(_ date: Date = Date()) -> Int {
    let parts = Calendar.current.dateComponents([.hour, .minute], from: date)
    return (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
}
