import AppKit
import PacemarkCore
import SwiftUI

struct MenuBarMeterTuning {
    enum LabelWeight: String, CaseIterable {
        case regular, semibold, bold

        var fontWeight: NSFont.Weight {
            switch self {
            case .regular: .regular
            case .semibold: .semibold
            case .bold: .bold
            }
        }
    }

    enum IconSize: Int, CaseIterable {
        case base = 100, plus10 = 110, plus20 = 120, plus30 = 130, plus40 = 140, plus50 = 150, plus60 = 160

        var factor: CGFloat { CGFloat(rawValue) / 100 }

        var title: String {
            self == .base ? "Base" : "+\(rawValue - IconSize.base.rawValue)%"
        }
    }

    enum TextSize: String, CaseIterable {
        case small, medium, large, xl

        var title: String {
            switch self {
            case .small: "S"
            case .medium: "M"
            case .large: "L"
            case .xl: "XL"
            }
        }

        var capHeightRatio: CGFloat {
            switch self {
            case .small: 0.17
            case .medium: 0.20
            case .large: 0.23
            case .xl: 0.25
            }
        }
    }

    static let ringWidths: [Double] = [1, 1.25, 1.5, 2, 2.5]
    static let markScales: [Double] = [0.60, 0.70, 0.75, 0.80, 0.85]
    static let defaults = Self()

    var showNumber = false
    var labelWeight = LabelWeight.semibold
    var showPaceTick = true
    var ringLineWidth: Double = 1.25
    var markScale = 0.70
    var iconSize = IconSize.plus20
    var textSize = TextSize.medium
}

struct MenuBarMeterControls: DynamicProperty {
    private static let showNumberKey = "t3.menuBar.showNumber"
    private static let labelWeightKey = "t3.menuBar.labelWeight"
    private static let ringLineWidthKey = "t3.menuBar.ringLineWidth"
    private static let markScaleKey = "t3.menuBar.markScale"
    private static let iconSizeKey = "t3.menuBar.iconSize"
    private static let textSizeKey = "t3.menuBar.textSize"

    static func seedMenuBarDemo(defaults: UserDefaults, showNumber: Bool = false) {
        defaults.set(showNumber, forKey: showNumberKey)
        defaults.set(MenuBarMeterTuning.LabelWeight.regular.rawValue, forKey: labelWeightKey)
        defaults.set(1.0, forKey: ringLineWidthKey)
        defaults.set(MenuBarMeterTuning.defaults.markScale, forKey: markScaleKey)
        defaults.set(MenuBarMeterTuning.IconSize.plus20.rawValue, forKey: iconSizeKey)
        defaults.set(MenuBarMeterTuning.TextSize.medium.rawValue, forKey: textSizeKey)
    }

    @AppStorage(showNumberKey) var showNumber = MenuBarMeterTuning.defaults.showNumber
    @AppStorage(labelWeightKey) var labelWeight = MenuBarMeterTuning.defaults.labelWeight
    @AppStorage("t3.menuBar.showPaceTick") var showPaceTick = MenuBarMeterTuning.defaults.showPaceTick
    @AppStorage(ringLineWidthKey) var ringLineWidth = MenuBarMeterTuning.defaults.ringLineWidth
    @AppStorage(markScaleKey) var markScale = MenuBarMeterTuning.defaults.markScale
    @AppStorage(iconSizeKey) var iconSize = MenuBarMeterTuning.defaults.iconSize
    @AppStorage(textSizeKey) var textSize = MenuBarMeterTuning.defaults.textSize

    var tuning: MenuBarMeterTuning {
        let defaults = MenuBarMeterTuning.defaults
        return MenuBarMeterTuning(
            showNumber: showNumber,
            labelWeight: labelWeight,
            showPaceTick: showPaceTick,
            ringLineWidth: MenuBarMeterTuning.ringWidths.contains(ringLineWidth) ? ringLineWidth : defaults.ringLineWidth,
            markScale: MenuBarMeterTuning.markScales.contains(markScale) ? markScale : defaults.markScale,
            iconSize: iconSize,
            textSize: textSize
        )
    }
}
