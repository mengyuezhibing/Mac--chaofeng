import SwiftUI

// MARK: - 主题色（对应 V2.0 的界面颜色风格设置）

enum ThemeColor {
    static let choices: [(name: String, label: String, color: Color)] = [
        ("leopard", "雪豹蓝", Color(red: 0.22, green: 0.52, blue: 0.95)),
        ("teal", "青碧", Color(red: 0.13, green: 0.62, blue: 0.62)),
        ("violet", "紫藤", Color(red: 0.58, green: 0.40, blue: 0.92)),
        ("rose", "珊瑚", Color(red: 0.92, green: 0.38, blue: 0.44)),
        ("amber", "琥珀", Color(red: 0.95, green: 0.62, blue: 0.18)),
        ("graphite", "石墨", Color(red: 0.42, green: 0.45, blue: 0.50))
    ]

    static func color(named name: String) -> Color {
        choices.first { $0.name == name }?.color ?? choices[0].color
    }
}

enum AppearanceMode: String, CaseIterable, Identifiable {
    case system, light, dark
    var id: String { rawValue }
    var label: String {
        switch self {
        case .system: return "跟随系统"
        case .light: return "浅色"
        case .dark: return "深色"
        }
    }
    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
}
