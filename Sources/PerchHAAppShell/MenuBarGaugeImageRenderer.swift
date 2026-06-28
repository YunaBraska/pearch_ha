import AppKit
import PerchHACore

@MainActor
public protocol PerchHAStatusItemGaugeImageRendering {
    func image(for item: RenderedMenuBarItem) -> NSImage?
}

@MainActor
public struct PerchHAStatusItemGaugePalette {
    public let normal: NSColor
    public let warning: NSColor
    public let critical: NSColor
    public let track: NSColor

    public init(normal: NSColor, warning: NSColor, critical: NSColor, track: NSColor) {
        self.normal = normal
        self.warning = warning
        self.critical = critical
        self.track = track
    }

    public static var system: PerchHAStatusItemGaugePalette {
        PerchHAStatusItemGaugePalette(
            normal: .controlAccentColor,
            warning: .systemOrange,
            critical: .systemRed,
            track: .tertiaryLabelColor
        )
    }
}

@MainActor
public struct PerchHAStatusItemGaugeImageRenderer: PerchHAStatusItemGaugeImageRendering {
    public let size: NSSize
    public let palette: PerchHAStatusItemGaugePalette

    public init(
        size: NSSize = NSSize(width: 24, height: 18),
        palette: PerchHAStatusItemGaugePalette = .system
    ) {
        self.size = size
        self.palette = palette
    }

    public func image(for item: RenderedMenuBarItem) -> NSImage? {
        guard let gauge = item.gauge, item.style != .text else {
            return nil
        }

        guard let bitmap = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: Int(size.width.rounded(.up)),
            pixelsHigh: Int(size.height.rounded(.up)),
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ) else {
            return nil
        }

        bitmap.size = size
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
        drawGauge(
            style: item.style,
            gauge: gauge,
            severity: item.severity,
            in: NSRect(origin: .zero, size: size)
        )
        NSGraphicsContext.current?.flushGraphics()
        NSGraphicsContext.restoreGraphicsState()

        let image = NSImage(size: size)
        image.addRepresentation(bitmap)
        image.isTemplate = false
        return image
    }

    public func foregroundColor(for severity: ValueSeverity) -> NSColor {
        switch severity {
        case .normal:
            palette.normal
        case .warning:
            palette.warning
        case .critical:
            palette.critical
        }
    }

    private func drawGauge(
        style: MenuBarDisplayStyle,
        gauge: MenuBarGauge,
        severity: ValueSeverity,
        in bounds: NSRect
    ) {
        NSColor.clear.setFill()
        bounds.fill()
        switch style {
        case .text:
            break
        case .bar:
            drawBar(gauge: gauge, severity: severity, in: bounds)
        case .battery:
            drawBattery(gauge: gauge, severity: severity, in: bounds)
        case .ring:
            drawRing(gauge: gauge, severity: severity, in: bounds)
        }
    }

    private func drawBar(gauge: MenuBarGauge, severity: ValueSeverity, in bounds: NSRect) {
        let rect = NSRect(
            x: bounds.minX + 2,
            y: bounds.midY - 3,
            width: max(1, bounds.width - 4),
            height: 6
        )
        fillRounded(rect, color: palette.track)
        let fillWidth = max(0, min(rect.width, rect.width * gauge.percent / 100.0))
        guard fillWidth > 0 else {
            return
        }
        fillRounded(
            NSRect(x: rect.minX, y: rect.minY, width: fillWidth, height: rect.height),
            color: foregroundColor(for: severity)
        )
    }

    private func drawBattery(gauge: MenuBarGauge, severity: ValueSeverity, in bounds: NSRect) {
        let body = NSRect(x: bounds.minX + 1.5, y: bounds.midY - 5, width: bounds.width - 6, height: 10)
        let cap = NSRect(x: body.maxX + 1, y: bounds.midY - 2, width: 2, height: 4)
        let bodyPath = NSBezierPath(roundedRect: body, xRadius: 2, yRadius: 2)
        palette.track.setStroke()
        bodyPath.lineWidth = 1.5
        bodyPath.stroke()
        fillRounded(cap, color: palette.track)

        let interior = body.insetBy(dx: 2.5, dy: 2.5)
        let fillWidth = max(0, min(interior.width, interior.width * gauge.percent / 100.0))
        guard fillWidth > 0 else {
            return
        }
        fillRounded(
            NSRect(x: interior.minX, y: interior.minY, width: fillWidth, height: interior.height),
            color: foregroundColor(for: severity)
        )
    }

    private func drawRing(gauge: MenuBarGauge, severity: ValueSeverity, in bounds: NSRect) {
        let center = NSPoint(x: bounds.midX, y: bounds.midY)
        let radius = max(2, min(bounds.width, bounds.height) / 2 - 3)
        let trackPath = NSBezierPath()
        trackPath.appendArc(withCenter: center, radius: radius, startAngle: 0, endAngle: 360)
        palette.track.setStroke()
        trackPath.lineWidth = 3
        trackPath.stroke()

        guard gauge.percent > 0 else {
            return
        }
        let endAngle = 90 - min(100, max(0, gauge.percent)) / 100 * 360
        let valuePath = NSBezierPath()
        valuePath.appendArc(withCenter: center, radius: radius, startAngle: 90, endAngle: endAngle, clockwise: true)
        valuePath.lineCapStyle = .round
        foregroundColor(for: severity).setStroke()
        valuePath.lineWidth = 3
        valuePath.stroke()
    }

    private func fillRounded(_ rect: NSRect, color: NSColor) {
        color.setFill()
        NSBezierPath(roundedRect: rect, xRadius: rect.height / 2, yRadius: rect.height / 2).fill()
    }
}
