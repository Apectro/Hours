import Foundation

enum AppearancePreference: String, Codable, CaseIterable, Hashable, Sendable, Identifiable {
    case system
    case light
    case dark

    var id: String { rawValue }

    var title: String { label(in: .device) }

    func label(in language: ExportLanguage) -> String {
        switch self {
        case .system: return language(.appearanceSystem)
        case .light: return language(.appearanceLight)
        case .dark: return language(.appearanceDark)
        }
    }
}
