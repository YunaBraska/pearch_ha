import AppKit
import PearchHACore
import PearchHAUI
import PearchHAPersistence
import SwiftUI
import XCTest

@MainActor
final class PearchHAContrastTests: XCTestCase {
    func testAccentForegroundIsReadableOnContentAndAccentChips() throws {
        PearchHATheme.apply(accentColor: .homeAssistantBlue)
        defer { PearchHATheme.apply(accentColor: .homeAssistantBlue) }
        for scheme in [ColorScheme.light, .dark] {
            for increasedContrast in [false, true] {
                let palette = PearchHATheme.Dashboard.palette(scheme, increasedContrast: increasedContrast)
                let foreground = try components(palette.accentPrimary)
                XCTAssertEqual(try components(palette.chartPrimary), foreground)
                for background in try backgrounds(palette) {
                    XCTAssertGreaterThanOrEqual(contrast(foreground, over: background), increasedContrast ? 7 : 4.5)
                }
            }
        }
    }

    func testCustomAccentsRemainReadableAndIncreaseContrastNeverWeakensThem() throws {
        defer { PearchHATheme.apply(accentColor: .homeAssistantBlue) }
        let accents = PearchHAAccentColor.swatches.map(\.color) + [
            PearchHAAccentColor(red: 0, green: 0, blue: 0),
            PearchHAAccentColor(red: 1, green: 1, blue: 1),
            PearchHAAccentColor(red: 1, green: 0.7, blue: 0.3, alpha: 0.35),
            PearchHAAccentColor(red: 0.2, green: 0.8, blue: 0.6, alpha: 0)
        ]
        for accent in accents {
            PearchHATheme.apply(accentColor: accent)
            for scheme in [ColorScheme.light, .dark] {
                let normal = PearchHATheme.Dashboard.palette(scheme)
                let increased = PearchHATheme.Dashboard.palette(scheme, increasedContrast: true)
                let foreground = try components(normal.accentPrimary)
                let increasedForeground = try components(increased.accentPrimary)
                let normalBackgrounds = try backgrounds(normal)
                let increasedBackgrounds = try backgrounds(increased)
                for (background, increasedBackground) in zip(normalBackgrounds, increasedBackgrounds) {
                    let normalRatio = contrast(foreground, over: background)
                    XCTAssertGreaterThanOrEqual(normalRatio, 4.5)
                    XCTAssertGreaterThanOrEqual(contrast(increasedForeground, over: increasedBackground), normalRatio)
                }
            }
        }
    }

    func testReadableForegroundLeavesRawAccentAndSavedColorUnchanged() throws {
        let accent = PearchHAAccentColor(red: 0.2, green: 0.8, blue: 0.6, alpha: 0.35)
        let configuration = PearchHAConfiguration(accentColor: accent)
        PearchHATheme.apply(accentColor: accent)
        defer { PearchHATheme.apply(accentColor: .homeAssistantBlue) }

        for scheme in [ColorScheme.light, .dark] {
            _ = PearchHATheme.Dashboard.palette(scheme, increasedContrast: true)
        }

        let expected = try components(PearchHATheme.color(for: accent))
        XCTAssertEqual(try components(PearchHATheme.accent), expected)
        let restored = try JSONDecoder().decode(PearchHAConfiguration.self, from: JSONEncoder().encode(configuration))
        XCTAssertEqual(restored.accentColor, accent)
    }

    func testProminentAccentFillsHaveReadableWhiteOrBlackLabels() throws {
        PearchHATheme.apply(accentColor: .homeAssistantBlue)
        defer { PearchHATheme.apply(accentColor: .homeAssistantBlue) }
        for scheme in [ColorScheme.light, .dark] {
            for increasedContrast in [false, true] {
                let palette = PearchHATheme.Dashboard.palette(scheme, increasedContrast: increasedContrast)
                let fill = try components(palette.accentPrimary)
                let label = try components(scheme == .dark ? Color.black : Color.white)
                for surface in try [palette.surfaceRoot, palette.surfacePanel, palette.surfacePanelElevated].map(components) {
                    XCTAssertGreaterThanOrEqual(contrast(label, over: composite(fill, over: surface)), 4.5)
                }
            }
        }
    }

    private func backgrounds(_ palette: PearchHATheme.DashboardPalette) throws -> [[Double]] {
        let surfaces = try [palette.surfaceRoot, palette.surfacePanel, palette.surfacePanelElevated].map(components)
        let selectedFill = try components(palette.surfaceControlActive)
        let hoverFill = try components(PearchHATheme.accent.opacity(0.16))
        let derivedFill = try components(palette.accentPrimary.opacity(0.16))
        return surfaces.flatMap { surface in
            [surface, composite(selectedFill, over: surface), composite(hoverFill, over: surface),
             composite(derivedFill, over: surface)]
        }
    }

    private func components(_ color: Color) throws -> [Double] {
        let native = try XCTUnwrap(NSColor(color).usingColorSpace(.sRGB))
        return [native.redComponent, native.greenComponent, native.blueComponent, native.alphaComponent]
    }

    private func composite(_ foreground: [Double], over background: [Double]) -> [Double] {
        (0..<3).map { foreground[$0] * foreground[3] + background[$0] * (1 - foreground[3]) } + [1]
    }

    private func contrast(_ foreground: [Double], over background: [Double]) -> Double {
        let luminances = [composite(foreground, over: background), background].map { color in
            zip(color.prefix(3), [0.2126, 0.7152, 0.0722]).reduce(0.0) { result, channel in
                let value = channel.0 <= 0.04045 ? channel.0 / 12.92 : pow((channel.0 + 0.055) / 1.055, 2.4)
                return result + value * channel.1
            }
        }
        return (max(luminances[0], luminances[1]) + 0.05) / (min(luminances[0], luminances[1]) + 0.05)
    }
}
