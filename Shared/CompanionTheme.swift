import Foundation
import SwiftUI

struct CompanionThemeDefinition: Hashable, Identifiable {
    let id: String
    let name: String
    let primaryHex: UInt
    let secondaryHex: UInt
    let outlineHex: UInt
    let backgroundHex: UInt
    let fontStyle: String
    let animation: String
    let glow: Double
}

enum CompanionThemes {
    static let all: [CompanionThemeDefinition] = [
        .init(id: "moonlight", name: "月光蓝紫", primaryHex: 0xF2EEFF,
              secondaryHex: 0xB9ACE8, outlineHex: 0x8E72E8,
              backgroundHex: 0x110E1C, fontStyle: "rounded", animation: "breathe", glow: 0.45),
        .init(id: "warmPink", name: "暖粉", primaryHex: 0xFFF0F5,
              secondaryHex: 0xF4B6CA, outlineHex: 0xF07DA5,
              backgroundHex: 0x211017, fontStyle: "rounded", animation: "bounce", glow: 0.38),
        .init(id: "sleepIndigo", name: "睡眠靛青", primaryHex: 0xE5E9FF,
              secondaryHex: 0x97A4D8, outlineHex: 0x6472B8,
              backgroundHex: 0x090D1C, fontStyle: "light", animation: "fade", glow: 0.2),
        .init(id: "musicNeon", name: "音乐霓虹", primaryHex: 0xF4FFFF,
              secondaryHex: 0x73F4E6, outlineHex: 0xE36CFF,
              backgroundHex: 0x080B14, fontStyle: "bold", animation: "pulse", glow: 0.62),
    ]

    static func resolve(_ id: String?) -> CompanionThemeDefinition {
        all.first(where: { $0.id == id }) ?? all[0]
    }
}

extension Color {
    init(companionHex hex: UInt, alpha: Double = 1) {
        self.init(.sRGB,
                  red: Double((hex >> 16) & 0xff) / 255,
                  green: Double((hex >> 8) & 0xff) / 255,
                  blue: Double(hex & 0xff) / 255,
                  opacity: alpha)
    }
}
