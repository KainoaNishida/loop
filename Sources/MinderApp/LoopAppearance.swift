import SwiftUI
import MinderCore

struct LoopPalette {
    var primary: Color
    var secondary: Color { primary }
    var tertiary: Color { primary }
    var warning: Color { primary }
    var completion: Color { primary }

    var swatches: [Color] {
        [primary]
    }
}

extension AppColorScheme {
    var palette: LoopPalette {
        switch self {
        case .ocean:
            return LoopPalette(primary: Color(red: 0.0, green: 0.38, blue: 0.82))
        case .forest:
            return LoopPalette(primary: Color(red: 0.12, green: 0.43, blue: 0.26))
        case .plum:
            return LoopPalette(primary: Color(red: 0.42, green: 0.25, blue: 0.64))
        case .ember:
            return LoopPalette(primary: Color(red: 0.73, green: 0.29, blue: 0.08))
        case .graphite:
            return LoopPalette(primary: Color(red: 0.27, green: 0.31, blue: 0.35))
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
