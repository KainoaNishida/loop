import SwiftUI
import MinderCore

struct LoopPalette {
    var primary: Color
    var secondary: Color
    var tertiary: Color
    var warning: Color
    var completion: Color

    var swatches: [Color] {
        [primary, secondary, tertiary, warning, completion]
    }
}

extension AppColorScheme {
    var palette: LoopPalette {
        switch self {
        case .ocean:
            return LoopPalette(
                primary: Color(red: 0.0, green: 0.38, blue: 0.82),
                secondary: Color(red: 0.43, green: 0.28, blue: 0.70),
                tertiary: Color(red: 0.05, green: 0.46, blue: 0.43),
                warning: Color(red: 0.70, green: 0.33, blue: 0.04),
                completion: Color(red: 0.13, green: 0.50, blue: 0.22)
            )
        case .forest:
            return LoopPalette(
                primary: Color(red: 0.12, green: 0.43, blue: 0.26),
                secondary: Color(red: 0.23, green: 0.36, blue: 0.59),
                tertiary: Color(red: 0.53, green: 0.38, blue: 0.12),
                warning: Color(red: 0.73, green: 0.41, blue: 0.05),
                completion: Color(red: 0.05, green: 0.46, blue: 0.43)
            )
        case .plum:
            return LoopPalette(
                primary: Color(red: 0.42, green: 0.25, blue: 0.64),
                secondary: Color(red: 0.70, green: 0.22, blue: 0.46),
                tertiary: Color(red: 0.10, green: 0.41, blue: 0.58),
                warning: Color(red: 0.74, green: 0.43, blue: 0.03),
                completion: Color(red: 0.12, green: 0.48, blue: 0.31)
            )
        case .ember:
            return LoopPalette(
                primary: Color(red: 0.73, green: 0.29, blue: 0.08),
                secondary: Color(red: 0.60, green: 0.20, blue: 0.16),
                tertiary: Color(red: 0.08, green: 0.43, blue: 0.47),
                warning: Color(red: 0.82, green: 0.50, blue: 0.08),
                completion: Color(red: 0.14, green: 0.48, blue: 0.26)
            )
        case .graphite:
            return LoopPalette(
                primary: Color(red: 0.27, green: 0.31, blue: 0.35),
                secondary: Color(red: 0.20, green: 0.39, blue: 0.50),
                tertiary: Color(red: 0.38, green: 0.31, blue: 0.53),
                warning: Color(red: 0.68, green: 0.45, blue: 0.12),
                completion: Color(red: 0.22, green: 0.46, blue: 0.31)
            )
        }
    }
}

private struct LoopPaletteEnvironmentKey: EnvironmentKey {
    static let defaultValue = AppColorScheme.ocean.palette
}

extension EnvironmentValues {
    var loopPalette: LoopPalette {
        get { self[LoopPaletteEnvironmentKey.self] }
        set { self[LoopPaletteEnvironmentKey.self] = newValue }
    }
}
