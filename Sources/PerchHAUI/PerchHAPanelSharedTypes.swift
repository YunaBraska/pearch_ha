import Foundation
import AppKit
import Combine
import SwiftUI
import UniformTypeIdentifiers
import PerchHACore
import PerchHASupport

public enum SelectionDragItem: Equatable, Sendable {
    case room(RoomID)
    case entity(EntityID)
}

public enum SelectionDropTranslation: Equatable, Sendable {
    case room(source: RoomID, target: RoomID, placement: SelectionDropPlacement)
    case entity(source: EntityID, target: EntityID, placement: SelectionDropPlacement)
    case unsupported
}

enum MenuBarTotalMode: Hashable {
    case none
    case absolute
    case entity(EntityID)
}

struct SanitizedCustomAction {
    let action: EntityCustomAction
    let protectedValueUpserts: [ProtectedActionValueReference: String]
}

struct SanitizedActionValue {
    let value: [String: ActionValue]
    let protectedValueUpserts: [ProtectedActionValueReference: String]
}

struct SanitizedScalarActionValue {
    let value: ActionValue
    let protectedValueUpserts: [ProtectedActionValueReference: String]
}

enum ProtectedActionValueSnapshot {
    case present(String)
    case missing
}

struct UnavailableProtectedActionValueStore: ProtectedActionValueStore {
    func save(_ value: String, for reference: ProtectedActionValueReference) throws {
        throw ProtectedActionValueStoreError.unavailable
    }

    func load(_ reference: ProtectedActionValueReference) throws -> String {
        throw ProtectedActionValueStoreError.unavailable
    }

    func delete(_ reference: ProtectedActionValueReference) throws {
        throw ProtectedActionValueStoreError.unavailable
    }
}

extension EntityCustomAction {
    func withServiceData(_ serviceData: [String: ActionValue]) -> EntityCustomAction {
        EntityCustomAction(
            id: id,
            entityID: entityID,
            title: title,
            action: ActionSpec(
                domain: action.domain,
                service: action.service,
                targetEntityID: action.targetEntityID,
                serviceData: serviceData
            ),
            requiresConfirmation: requiresConfirmation
        )
    }
}

extension ActionValue {
    var editorType: PerchHACustomActionServiceDataValueKind {
        switch self {
        case .number:
            .number
        case .bool:
            .bool
        case .object:
            .object
        case .array:
            .array
        case .string, .protectedString, .null:
            .string
        }
    }

    var editorText: String {
        switch self {
        case let .string(value):
            return value
        case .protectedString:
            return ""
        case let .number(value):
            if value.isFinite,
               value.rounded() == value,
               value >= Double(Int.min),
               value <= Double(Int.max) {
                return String(Int(value))
            }
            return String(value)
        case let .bool(value):
            return value ? "true" : "false"
        case let .object(values):
            return "\(values.count) field\(values.count == 1 ? "" : "s")"
        case let .array(values):
            return "\(values.count) item\(values.count == 1 ? "" : "s")"
        case .null:
            return ""
        }
    }

    var isInlineEditable: Bool {
        switch self {
        case .string, .protectedString, .number, .bool, .null:
            true
        case .object, .array:
            false
        }
    }
}

public struct SelectionDropTranslator: Sendable {
    public init() {}

    public func translate(
        source: SelectionDragItem,
        target: SelectionDragItem,
        tree: [SelectableRoom]
    ) -> SelectionDropTranslation {
        guard source != target else {
            return .unsupported
        }
        switch (source, target) {
        case let (.room(sourceID), .room(targetID)):
            return .room(
                source: sourceID,
                target: targetID,
                placement: dropPlacement(sourceID, targetID: targetID, order: tree.map(\.id))
            )
        case let (.entity(sourceID), .entity(targetID)):
            guard let room = tree.first(where: { room in
                room.entities.contains { $0.entity.id == sourceID }
                    && room.entities.contains { $0.entity.id == targetID }
            }) else {
                return .unsupported
            }
            return .entity(
                source: sourceID,
                target: targetID,
                placement: dropPlacement(sourceID, targetID: targetID, order: room.entities.map(\.entity.id))
            )
        case (.room, .entity), (.entity, .room):
            return .unsupported
        }
    }

    private func dropPlacement<T: Equatable>(_ sourceID: T, targetID: T, order: [T]) -> SelectionDropPlacement {
        guard let sourceIndex = order.firstIndex(of: sourceID),
              let targetIndex = order.firstIndex(of: targetID)
        else {
            return .before
        }
        return sourceIndex < targetIndex ? .after : .before
    }
}

public struct PerchHAHistoryPopoverContent: View {
    private let entityID: EntityID
    private let entityName: String
    private let valueText: String
    private let unit: String?
    private let state: PerchHAHistoryPanelState
    private let increaseContrastOverride: Bool?
    private let onOpenSettings: (() -> Void)?
    private let disabledRanges: Set<HistoryRange>
    @Binding private var selectedRange: HistoryRange
    @State private var cursorNormalizedX: Double?
    @State private var hoverReadout: String?
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast
    private static let bodyMinHeight: CGFloat = 118

    public init(
        entityID: EntityID,
        entityName: String,
        valueText: String,
        unit: String? = nil,
        state: PerchHAHistoryPanelState,
        increaseContrastOverride: Bool? = nil,
        onOpenSettings: (() -> Void)? = nil,
        disabledRanges: Set<HistoryRange> = [],
        selectedRange: Binding<HistoryRange>
    ) {
        self.entityID = entityID
        self.entityName = entityName
        self.valueText = valueText
        self.unit = unit
        self.state = state
        self.increaseContrastOverride = increaseContrastOverride
        self.onOpenSettings = onOpenSettings
        self.disabledRanges = disabledRanges
        _selectedRange = selectedRange
    }

    private var palette: PerchHATheme.DashboardPalette {
        PerchHATheme.Dashboard.palette(colorScheme)
    }

    public var body: some View {
        let shape = RoundedRectangle(cornerRadius: 14, style: .continuous)
        return VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(entityName)
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(palette.textPrimary)
                    .lineLimit(1)
                Spacer(minLength: 8)
                Text(valueText)
                    .font(.system(size: 16, weight: .semibold).monospacedDigit())
                    .foregroundStyle(historyValueForegroundStyle)
                if let onOpenSettings {
                    Button(action: onOpenSettings) {
                        Image(systemName: "gearshape")
                    }
                    .buttonStyle(PerchHAIconButtonStyle())
                    .help("Entity settings")
                    .accessibilityLabel("\(entityName) settings")
                }
            }
            PerchHAHistoryRangeSegmentedControl(
                options: rangeOptions,
                selection: $selectedRange,
                disabledRanges: disabledRanges,
                accessibilityLabel: "\(entityName) history range"
            )
            historyHoverReadout
            historyBody
                .frame(minHeight: Self.bodyMinHeight, alignment: .topLeading)
        }
        .padding(14)
        .frame(width: 280)
        .environment(\.dashboardPalette, palette)
        .background {
            shape
                .fill(palette.surfacePanelElevated)
                .overlay(shape.fill(.ultraThinMaterial).opacity(0.35))
        }
        .overlay(shape.strokeBorder(palette.borderSubtle, lineWidth: 1))
        .clipShape(shape)
        .shadow(color: palette.shadowSoft, radius: 14, x: 0, y: 6)
    }

    /// The ranges offered in the segmented selector.
    private var rangeOptions: [HistoryRange] {
        var options = HistoryRange.uiSelectable
        if !options.contains(selectedRange) {
            options.append(selectedRange)
        }
        return options
    }

    @ViewBuilder
    private var historyHoverReadout: some View {
        let readout = hoverReadout ?? " "
        Text(readout)
            .font(.caption2.monospacedDigit())
            .foregroundStyle(hoverReadout == nil ? historyLabelForegroundStyle.opacity(0) : historyLabelForegroundStyle)
            .lineLimit(1)
            .frame(maxWidth: .infinity, minHeight: 14, alignment: .trailing)
            .accessibilityHidden(true)
    }

    @ViewBuilder
    private var historyBody: some View {
        switch PerchHAHistoryBodyPresentation(state: state, entityID: entityID) {
        case .hidden:
            EmptyView()
        case .loadingSkeleton:
            HistoryLoadingSkeleton()
                .accessibilityLabel("\(entityName) history loading")
        case .empty:
            Text("No history for this range")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityLabel("\(entityName) has no history for this range")
        case .noNumericData:
            Text("No history data")
                .font(.callout)
                .foregroundStyle(.secondary)
                .accessibilityLabel("\(entityName) history has no numeric data")
        case let .stateTimeline(series, segments):
            // Constant height: the state timeline plus its legend occupy a fixed
            // block so hovering the cursor never resizes the popover window.
            PerchHAHistoryStateTimelinePopoverBody(
                segments: segments,
                range: series.range,
                entityName: entityName,
                labelColor: historyLabelForegroundStyle,
                valueColor: historyValueForegroundStyle,
                onHoverReadoutChange: { hoverReadout = $0 }
            )
        case let .statistics(series, statistics):
            // Keep a constant height: always show the chart and stats, and float
            // the cursor readout as an overlay on the chart. Swapping the area
            // below the chart would resize the popover window on hover, which
            // aborts inside NSPopover's animated resize.
            VStack(alignment: .leading, spacing: 8) {
                interactiveChart(series: series)
                historyStats(statistics)
            }
        case let .unavailable(message):
            VStack(alignment: .leading, spacing: 4) {
                Label("History unavailable", systemImage: "exclamationmark.triangle")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Text("Move away and hover again to retry.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(entityName) history unavailable: \(message). Hover again to retry.")
        }
    }

    private func interactiveChart(series: HistorySeries) -> some View {
        let chartHeight: CGFloat = 80
        let peaks = Self.chartPeaks(series: series)
        return GeometryReader { proxy in
            ZStack(alignment: .topLeading) {
                if let peaks {
                    // Peak values pinned at the chart corners, iStat/Stats-style,
                    // so the range is readable without leaving the chart.
                    VStack(alignment: .trailing) {
                        Text(peaks.maximum)
                        Spacer(minLength: 0)
                        Text(peaks.minimum)
                    }
                    .font(.system(size: 9).monospacedDigit())
                    .foregroundStyle(historyLabelForegroundStyle)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .padding(2)
                    .accessibilityHidden(true)
                }
                HistorySparklineArea(series: series)
                    .fill(
                        LinearGradient(
                            colors: [palette.chartPrimary.opacity(0.22), palette.chartPrimary.opacity(0.0)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                HistorySparkline(series: series)
                    .stroke(palette.chartPrimary, style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
                if let normalizedX = cursorNormalizedX {
                    let x = proxy.size.width * CGFloat(min(max(normalizedX, 0), 1))
                    Rectangle()
                        .fill(Color.secondary.opacity(0.6))
                        .frame(width: 1)
                        .frame(maxHeight: .infinity)
                        .offset(x: x)
                }
            }
            .contentShape(Rectangle())
            .onContinuousHover { phase in
                switch phase {
                case let .active(location):
                    let width = proxy.size.width
                    let normalizedX = width > 0 ? Double(location.x / width) : nil
                    cursorNormalizedX = normalizedX
                    hoverReadout = normalizedX.flatMap { _ in cursorReadout(for: series) }
                case .ended:
                    cursorNormalizedX = nil
                    hoverReadout = nil
                }
            }
        }
        .frame(height: chartHeight)
        .accessibilityHidden(true)
        .onDisappear {
            hoverReadout = nil
        }
    }

    /// The formatted minimum and maximum of a series for the chart corner
    /// labels, or `nil` when the series has no numeric spread worth labelling.
    static func chartPeaks(series: HistorySeries) -> (minimum: String, maximum: String)? {
        let values = series.samples.compactMap(\.numericValue)
        guard let minimum = values.min(), let maximum = values.max(), minimum != maximum else {
            return nil
        }
        return (menuBarNumberLabel(minimum), menuBarNumberLabel(maximum))
    }

    private func cursorReadout(for series: HistorySeries) -> String? {
        guard let normalizedX = cursorNormalizedX,
              let sample = PerchHAHistoryCursor.nearestSample(in: series, atNormalizedX: normalizedX)
        else {
            return nil
        }
        return Self.cursorReadout(
            value: sample.value,
            unit: unit,
            timestamp: sample.timestamp,
            range: series.range
        )
    }

    static func cursorReadout(
        value: Double,
        unit: String?,
        timestamp: Date,
        range: HistoryRange? = nil,
        locale: Locale = .current,
        timeZone: TimeZone = .current
    ) -> String {
        let number = menuBarNumberLabel(value)
        let trimmedUnit = unit?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let formattedValue = trimmedUnit.isEmpty ? number : "\(number) \(trimmedUnit)"
        let formattedTimestamp = PerchHAHistoryHoverFormatting.timestamp(
            timestamp,
            range: range,
            locale: locale,
            timeZone: timeZone
        )
        return "\(formattedValue) · \(formattedTimestamp)"
    }

    private func historyStats(_ statistics: PerchHAHistoryStatistics) -> some View {
        Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 4) {
            GridRow {
                statisticLabel("Current")
                statisticValue(menuBarNumberLabel(statistics.current))
            }
            GridRow {
                statisticLabel("Min")
                statisticValue(menuBarNumberLabel(statistics.minimum))
                statisticLabel("Avg")
                statisticValue(menuBarNumberLabel(statistics.average))
                statisticLabel("Max")
                statisticValue(menuBarNumberLabel(statistics.maximum))
            }
        }
        .font(.caption)
    }

    @ViewBuilder
    private func statisticLabel(_ text: String) -> some View {
        Text(text)
            .foregroundStyle(historyLabelForegroundStyle)
    }

    @ViewBuilder
    private func statisticValue(_ text: String) -> some View {
        Text(text)
            .monospacedDigit()
            .foregroundStyle(historyValueForegroundStyle)
    }

    private var historyLabelForegroundStyle: Color {
        if isIncreasedContrast {
            return palette.textPrimary
        }
        return palette.textSecondary
    }

    private var historyValueForegroundStyle: Color {
        if isIncreasedContrast {
            return palette.textPrimary
        }
        return palette.textPrimary
    }

    private var isIncreasedContrast: Bool {
        increaseContrastOverride ?? (colorSchemeContrast == .increased)
    }
}

private struct PerchHAHistoryRangeSegmentedControl: NSViewRepresentable {
    let options: [HistoryRange]
    @Binding var selection: HistoryRange
    let disabledRanges: Set<HistoryRange>
    let accessibilityLabel: String

    func makeCoordinator() -> Coordinator {
        Coordinator(selection: $selection, options: options)
    }

    func makeNSView(context: Context) -> NSSegmentedControl {
        let control = NSSegmentedControl(labels: options.map(\.displayName), trackingMode: .selectOne, target: nil, action: nil)
        control.segmentStyle = .rounded
        control.controlSize = .small
        control.target = context.coordinator
        control.action = #selector(Coordinator.selectionChanged(_:))
        control.setAccessibilityLabel(accessibilityLabel)
        sync(control)
        return control
    }

    func updateNSView(_ nsView: NSSegmentedControl, context: Context) {
        context.coordinator.selection = $selection
        context.coordinator.options = options
        if nsView.segmentCount != options.count {
            nsView.segmentCount = options.count
            for (index, range) in options.enumerated() {
                nsView.setLabel(range.displayName, forSegment: index)
            }
        }
        nsView.setAccessibilityLabel(accessibilityLabel)
        sync(nsView)
    }

    private func sync(_ control: NSSegmentedControl) {
        for (index, range) in options.enumerated() {
            control.setSelected(range == selection, forSegment: index)
            control.setEnabled(!disabledRanges.contains(range), forSegment: index)
        }
    }

    final class Coordinator: NSObject {
        var selection: Binding<HistoryRange>
        var options: [HistoryRange]

        init(selection: Binding<HistoryRange>, options: [HistoryRange]) {
            self.selection = selection
            self.options = options
        }

        @MainActor @objc func selectionChanged(_ sender: NSSegmentedControl) {
            let index = sender.selectedSegment
            guard index >= 0, index < options.count else {
                return
            }
            selection.wrappedValue = options[index]
        }
    }
}

func menuBarNumberLabel(_ value: Double?) -> String {
    guard let value else {
        return "Off"
    }
    if value.rounded() == value {
        return "\(Int(value))"
    }
    return String(format: "%.1f", value)
}

enum PerchHASliderValueFormatting {
    static func label(for value: Double, unit: String?) -> String {
        let number = menuBarNumberLabel(value)
        let trimmedUnit = unit?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if trimmedUnit == "%" {
            return "\(number)%"
        }
        guard !trimmedUnit.isEmpty else {
            return number
        }
        return "\(number) \(trimmedUnit)"
    }

    static func accessibilityValue(for value: Double, unit: String?) -> String {
        let number = menuBarNumberLabel(value)
        let trimmedUnit = unit?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if trimmedUnit == "%" {
            return "\(number) percent"
        }
        guard !trimmedUnit.isEmpty else {
            return number
        }
        return "\(number) \(trimmedUnit)"
    }
}

public func perchHAEntityIconName(for entity: DiscoveredEntity) -> String {
    let domain = entity.id.domain
    let name = entity.name.lowercased()
    let unit = (entity.unit ?? "").lowercased()
    switch domain {
    case "light":
        return "lightbulb"
    case "switch", "input_boolean":
        return "switch.2"
    case "cover":
        return "window.shade.open"
    case "fan":
        return "fanblades"
    case "lock":
        return "lock"
    case "climate", "water_heater":
        return "thermometer"
    case "media_player":
        return "play.rectangle"
    case "binary_sensor":
        return "dot.radiowaves.left.and.right"
    case "person", "device_tracker":
        return "person"
    default:
        if name.contains("temp") || unit.contains("°") || unit == "k" {
            return "thermometer"
        }
        if name.contains("humid") || unit == "%" {
            return "humidity"
        }
        if name.contains("batt") {
            return "battery.50"
        }
        if name.contains("power") || name.contains("energy") || unit == "w" || unit == "kw" || unit == "wh" || unit == "kwh" {
            return "bolt"
        }
        if name.contains("co2") || name.contains("air") || name.contains("quality") {
            return "aqi.medium"
        }
        if name.contains("door") || name.contains("window") || name.contains("motion") {
            return "sensor"
        }
        return "gauge.medium"
    }
}

@MainActor
final class PerchHAMenuActionTarget: NSObject {
    private let action: () -> Void

    init(action: @escaping () -> Void) {
        self.action = action
    }

    @objc func performAction(_ sender: Any?) {
        action()
    }
}

extension PerchHAPanelSnapshot {
    var showsConnectedContent: Bool {
        switch phase {
        case .connectedData, .connectedEmpty:
            true
        case .firstRun, .connecting, .reconnecting, .failed, .failedStale:
            false
        }
    }
}

@MainActor
struct PerchHANativeTextField: NSViewRepresentable {
    let placeholder: String
    @Binding var text: String
    let contentType: NSTextContentType?
    let normalizeOnCommit: ((String) -> String)?
    /// When `false`, the field draws no bezel or background, so it can sit inside
    /// a custom capsule container (the panel search field) without the stock
    /// square text-field border. Defaults to `true` for the connection form.
    var isBezeled: Bool = true

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeNSView(context: Context) -> NSTextField {
        let field = NSTextField()
        configure(field)
        field.delegate = context.coordinator
        return field
    }

    func updateNSView(_ nsView: NSTextField, context: Context) {
        context.coordinator.parent = self
        configure(nsView)
        if nsView.stringValue != text {
            nsView.stringValue = text
        }
    }

    private func configure(_ field: NSTextField) {
        field.placeholderString = placeholder
        field.isEditable = true
        field.isSelectable = true
        field.isBezeled = isBezeled
        field.bezelStyle = .roundedBezel
        field.drawsBackground = isBezeled
        field.isBordered = isBezeled
        field.usesSingleLineMode = true
        field.maximumNumberOfLines = 1
        field.lineBreakMode = .byTruncatingTail
        field.focusRingType = isBezeled ? .default : .none
        field.setAccessibilityLabel(placeholder)
        if field.stringValue != text {
            field.stringValue = text
        }
        if #available(macOS 11.0, *) {
            field.contentType = contentType
        }
    }

    @MainActor
    final class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: PerchHANativeTextField

        init(parent: PerchHANativeTextField) {
            self.parent = parent
        }

        func controlTextDidChange(_ notification: Notification) {
            guard let field = notification.object as? NSTextField else {
                return
            }
            parent.text = field.stringValue
        }

        func controlTextDidEndEditing(_ notification: Notification) {
            guard let field = notification.object as? NSTextField else {
                return
            }
            commit(field)
        }

        private func commit(_ field: NSTextField) {
            let normalized = parent.normalizeOnCommit?(field.stringValue) ?? field.stringValue
            if field.stringValue != normalized {
                field.stringValue = normalized
            }
            if parent.text != normalized {
                parent.text = normalized
            }
        }
    }
}

@MainActor
struct PerchHANativeSecureField: NSViewRepresentable {
    let placeholder: String
    @Binding var text: String
    let contentType: NSTextContentType?

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeNSView(context: Context) -> NSSecureTextField {
        let field = NSSecureTextField()
        configure(field)
        field.delegate = context.coordinator
        return field
    }

    func updateNSView(_ nsView: NSSecureTextField, context: Context) {
        context.coordinator.parent = self
        configure(nsView)
        if nsView.stringValue != text {
            nsView.stringValue = text
        }
    }

    private func configure(_ field: NSSecureTextField) {
        field.placeholderString = placeholder
        field.isEditable = true
        field.isSelectable = true
        field.isBezeled = true
        field.bezelStyle = .roundedBezel
        field.drawsBackground = true
        field.usesSingleLineMode = true
        field.maximumNumberOfLines = 1
        field.lineBreakMode = .byTruncatingTail
        field.focusRingType = .default
        field.setAccessibilityLabel(placeholder)
        if field.stringValue != text {
            field.stringValue = text
        }
        if #available(macOS 11.0, *) {
            field.contentType = contentType
        }
    }

    @MainActor
    final class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: PerchHANativeSecureField

        init(parent: PerchHANativeSecureField) {
            self.parent = parent
        }

        func controlTextDidChange(_ notification: Notification) {
            guard let field = notification.object as? NSTextField else {
                return
            }
            parent.text = field.stringValue
        }
    }
}

private struct HistorySparkline: Shape {
    let series: HistorySeries

    func path(in rect: CGRect) -> Path {
        let geometry = PerchHAHistorySparklineGeometry(series: series)
        return Path { path in
            for (index, point) in geometry.points.enumerated() {
                let x = rect.minX + rect.width * CGFloat(point.x)
                let y = rect.minY + rect.height * CGFloat(point.y)
                let point = CGPoint(x: x, y: y)
                if index == 0 {
                    path.move(to: point)
                } else {
                    path.addLine(to: point)
                }
            }
        }
    }
}

private struct HistorySparklineArea: Shape {
    let series: HistorySeries

    func path(in rect: CGRect) -> Path {
        let geometry = PerchHAHistorySparklineGeometry(series: series)
        let points = geometry.points
        guard points.count > 1 else {
            return Path()
        }
        return Path { path in
            for (index, point) in points.enumerated() {
                let cgPoint = CGPoint(
                    x: rect.minX + rect.width * CGFloat(point.x),
                    y: rect.minY + rect.height * CGFloat(point.y)
                )
                if index == 0 {
                    path.move(to: cgPoint)
                } else {
                    path.addLine(to: cgPoint)
                }
            }
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
            path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
            path.closeSubpath()
        }
    }
}

struct HistoryLoadingSkeletonLayout: Equatable {
    struct StatisticRow: Equatable, Identifiable {
        let id: Int
        let labelWidth: CGFloat
        let valueWidth: CGFloat
    }

    let cornerRadius: CGFloat
    let chartHeight: CGFloat
    let statisticPlaceholderHeight: CGFloat
    let statisticRows: [StatisticRow]

    static let standard = HistoryLoadingSkeletonLayout(
        cornerRadius: 2,
        chartHeight: 46,
        statisticPlaceholderHeight: 8,
        statisticRows: (0..<4).map { row in
            StatisticRow(id: row, labelWidth: 42, valueWidth: 54)
        }
    )
}

struct PerchHACoverPositionSlider: View {
    let position: Int
    let disabled: Bool
    let accessibilityName: String
    let unit: String?
    let onCommit: (Int) -> Void

    @State private var draft: Double
    @State private var isEditing = false

    init(
        position: Int,
        disabled: Bool,
        accessibilityName: String,
        unit: String? = "%",
        onCommit: @escaping (Int) -> Void
    ) {
        self.position = position
        self.disabled = disabled
        self.accessibilityName = accessibilityName
        self.unit = unit
        self.onCommit = onCommit
        _draft = State(initialValue: Double(position))
    }

    var body: some View {
        HStack(spacing: PerchHASpacing.sm) {
            Slider(
                value: $draft,
                in: 0...100,
                step: 1,
                onEditingChanged: { editing in
                    isEditing = editing
                    if !editing {
                        onCommit(Int(draft.rounded()))
                    }
                }
            )
            .disabled(disabled)
            .accessibilityLabel(accessibilityName)
            .accessibilityValue(PerchHASliderValueFormatting.accessibilityValue(for: draft, unit: unit))
            .onChange(of: position) { newPosition in
                if !isEditing {
                    draft = Double(newPosition)
                }
            }
            Text(PerchHASliderValueFormatting.label(for: draft, unit: unit))
                .font(PerchHATypography.bodyValue())
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .frame(minWidth: 40, maxWidth: 72, alignment: .trailing)
                .accessibilityHidden(true)
        }
    }
}

struct HistoryLoadingSkeleton: View {
    let layout: HistoryLoadingSkeletonLayout

    init(layout: HistoryLoadingSkeletonLayout = .standard) {
        self.layout = layout
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            RoundedRectangle(cornerRadius: layout.cornerRadius)
                .fill(.quaternary)
                .frame(height: layout.chartHeight)
            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 4) {
                ForEach(layout.statisticRows) { row in
                    GridRow {
                        RoundedRectangle(cornerRadius: layout.cornerRadius)
                            .fill(.quaternary)
                            .frame(width: row.labelWidth, height: layout.statisticPlaceholderHeight)
                        RoundedRectangle(cornerRadius: layout.cornerRadius)
                            .fill(.quaternary)
                            .frame(width: row.valueWidth, height: layout.statisticPlaceholderHeight)
                    }
                }
            }
        }
        .accessibilityElement(children: .ignore)
    }
}

extension Double {
    func clamped(to range: ClosedRange<Double>) -> Double {
        min(max(self, range.lowerBound), range.upperBound)
    }
}

extension SelectionDragItem {
    var providerText: String {
        switch self {
        case let .room(id):
            "room:\(id.rawValue)"
        case let .entity(id):
            "entity:\(id.rawValue)"
        }
    }
}

extension MenuBarDisplayStyle {
    var displayName: String {
        switch self {
        case .text:
            "Text"
        case .bar:
            "Bar"
        case .battery:
            "Battery"
        case .ring:
            "Ring"
        }
    }
}

extension ValueThresholdDirection {
    var displayName: String {
        switch self {
        case .aboveOrEqual:
            "High"
        case .belowOrEqual:
            "Low"
        }
    }
}

extension CoverControlMode {
    var displayName: String {
        switch self {
        case .buttons:
            "Buttons"
        case .slider:
            "Slider"
        case .both:
            "Both"
        }
    }
}


extension HistoryRange {
    var displayName: String {
        switch self {
        case .hour:
            "Hour"
        case .day:
            "Day"
        case .week:
            "Week"
        case .month:
            "Month"
        }
    }

    /// The history ranges the UI offers.
    static let uiSelectable: [HistoryRange] = [.hour, .day, .week, .month]
}

public typealias PerchHABootstrapView = PerchHAPanelView

public enum PerchHAUI {
    public static let module = PerchHAModule(
        name: "PerchHAUI",
        responsibility: "SwiftUI and AppKit-facing user interface components."
    )
}
