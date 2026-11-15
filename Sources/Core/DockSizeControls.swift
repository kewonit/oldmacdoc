import Foundation

/// The Size and Magnification sliders in the settings panel. They're independent: moving one never
/// moves the other.
///
/// - Size ends at the largest icon size that fits across the screen with the apps in the dock (past
///   that the dock can't grow), so the knob never sits beyond what's shown.
/// - Magnification has a fixed range. Its far left means no magnification; elsewhere it's the size an
///   icon grows to under the pointer. One set below the icon size simply shows no magnification.
struct DockSizeControls: Equatable {
    let sizeRange: ClosedRange<Double>
    /// The icon size as shown: the setting, or the largest size that fits if that's smaller.
    let size: Double
    /// Where the Magnification knob sits: `offPosition` when magnification is off.
    let magnification: Double

    /// Magnification's range: the far left (one point below the smallest magnified size) is off.
    static let offPosition = AppSettings.magnifiedSizeRange.lowerBound - 1
    static let magnificationRange = offPosition...AppSettings.magnifiedSizeRange.upperBound

    var magnificationIsOff: Bool { magnification <= Self.offPosition }

    /// - Parameter largestFitting: the largest icon size that fits on screen now (nil when unknown).
    init(settings s: AppSettings, largestFitting: Double?) {
        let range = AppSettings.iconSizeRange
        let largest = max(min(range.upperBound, largestFitting ?? range.upperBound), range.lowerBound / 2 + 8)
        sizeRange = min(range.lowerBound, largest - 8)...largest
        size = min(max(s.iconSize, sizeRange.lowerBound), largest)
        magnification = s.magnification ? min(max(s.magnifiedSize, AppSettings.magnifiedSizeRange.lowerBound),
                                              AppSettings.magnifiedSizeRange.upperBound) : Self.offPosition
    }

    /// Settings with the icon size at `value` (whole points). Magnification is left as it is.
    static func settingSize(_ value: Double, in s: AppSettings) -> AppSettings {
        var new = s
        new.iconSize = value.rounded()
        return new
    }

    /// Settings with the Magnification knob at `value`: the far left turns magnification off and keeps
    /// the last magnified size for when it's turned on again. The icon size is left as it is.
    static func settingMagnification(_ value: Double, in s: AppSettings) -> AppSettings {
        var new = s
        let value = value.rounded()
        new.magnification = value > offPosition
        if new.magnification { new.magnifiedSize = value }
        return new
    }

    /// What the readout next to a slider says.
    static func readout(_ value: Double) -> String { "\(Int(value.rounded())) pt" }
    var magnificationReadout: String { magnificationIsOff ? "Off" : Self.readout(magnification) }
}
