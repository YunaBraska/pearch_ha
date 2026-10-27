import AppKit
import SwiftUI
import PearchHACore
import PearchHASupport

struct PearchHAEntityControlsButton<Label: View>: View {
    @ObservedObject var model: PearchHAPanelModel
    let entity: DiscoveredEntity
    @ViewBuilder var label: () -> Label
    @State private var isPresented = false

    var body: some View {
        Button {
            model.dismissHistoryPopover()
            isPresented = true
        } label: {
            label()
        }
            .buttonStyle(.plain)
            .help(PearchHAEntityControlField.controlHelp(for: entity) ?? "No controls available")
            .accessibilityLabel("Adjust \(entity.name)")
            .accessibilityValue(model.formattedValue(for: entity).text)
            .onChange(of: model.snapshot.historyPresentationEntityID) { id in
                if id != nil { isPresented = false }
            }
            .popover(isPresented: $isPresented, arrowEdge: .trailing) {
                PearchHAEntityControlEditor(model: model, entityID: entity.id)
            }
    }
}

/// One native editor shared by all capability-derived controls.
public struct PearchHAEntityControlEditor: View {
    @ObservedObject private var model: PearchHAPanelModel
    private let entityID: EntityID
    @Environment(\.colorScheme) private var colorScheme

    /// Creates an editor that follows live state for the selected entity.
    public init(model: PearchHAPanelModel, entityID: EntityID) {
        self.model = model
        self.entityID = entityID
    }

    public var body: some View {
        let entity = model.snapshot.availableRooms.flatMap(\.entities).first { $0.id == entityID }
        let fields = entity.map { PearchHAEntityControlField.controls(for: $0) } ?? []
        VStack(alignment: .leading, spacing: PearchHASpacing.md) {
            HStack(spacing: PearchHASpacing.sm) {
                if let entity {
                    Image(systemName: model.snapshot.effectiveMenuBarItemConfiguration(for: entity).customIconName ?? pearchHAEntityIconName(for: entity))
                        .foregroundStyle(PearchHATheme.accent)
                        .accessibilityHidden(true)
                }
                Text(entity?.name ?? entityID.rawValue).font(PearchHATypography.body().weight(.semibold))
                Spacer(minLength: 0)
                ZStack {
                    if model.snapshot.controlActionState.isRunning(for: entityID) && !model.hasRequestedControls(for: entityID) {
                        ProgressView().controlSize(.small)
                            .help("Waiting for Home Assistant")
                            .accessibilityLabel("Waiting for Home Assistant")
                    }
                }
                .frame(width: 16, height: 16)
            }
            if let current = entity?.controlAttributes?["current_temperature"]?.controlNumber {
                Text("Current temperature: \(current.formatted())\((entity?.unit ?? entity?.controlAttributes?["temperature_unit"]?.controlString).map { " " + $0 } ?? "")")
                    .font(.subheadline).foregroundStyle(.secondary)
            }
            if fields.isEmpty {
                Text("No controls available").foregroundStyle(.secondary)
            } else {
                ScrollView {
                    PearchHACard(cornerRadius: PearchHACornerRadius.card) {
                        VStack(alignment: .leading, spacing: PearchHASpacing.md) {
                            ForEach(Array(fields.enumerated()), id: \.element.id) { index, field in
                                if index > 0 { Divider().accessibilityHidden(true) }
                                PearchHAEntityControlInput(field: field, entityName: entity?.name ?? entityID.rawValue, clock: model.clock,
                                                          isRunning: model.snapshot.controlActionState.isRunning(for: entityID),
                                                          requestedValue: model.requestedControlValue(for: entityID, controlID: field.id)) { value, confirmed in
                                    model.startEntityControlValue(entityID, controlID: field.id, value: value, confirmed: confirmed)
                                }
                                .disabled(model.snapshot.connectionState != .connected || model.snapshot.controlActionState.isRunning)
                            }
                        }
                        .padding(PearchHASpacing.md)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding(2)
                }
                .frame(maxHeight: 400)
            }
            if let failure = model.snapshot.controlActionState.failureMessage(for: entityID) {
                Text(failure).foregroundStyle(.red).fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(PearchHASpacing.lg)
        .frame(width: 340)
        .fixedSize(horizontal: false, vertical: true)
        .font(PearchHATypography.body())
        .tint(PearchHATheme.accent)
        .background(PearchHATheme.Dashboard.palette(colorScheme).surfaceRoot)
    }
}

struct PearchHAEntityControlInput: View {
    let field: PearchHAEntityControlField
    let entityName: String
    let clock: any PearchClock
    var isInline = false
    var isRunning = false
    var requestedValue: ActionValue? = nil
    var showsRequestedIndicator = true
    var coverMode: CoverControlMode? = nil
    var runCoverCommand: ((PearchHACoverCommand) -> Bool)? = nil
    let submit: (ActionValue?, Bool) -> Bool
    @State private var text = ""
    @State private var color = Color.white
    @State private var needsConfirmation = false
    @State private var pendingNumberTask: Task<Void, Never>?
    @State private var isSliding = false
    @State private var isNumberEntryPresented = false
    @Environment(\.isEnabled) private var isEnabled
    @FocusState private var isEditingNumber: Bool

    var body: some View {
        HStack(spacing: 5) {
            switch field.input {
            case .action:
                Button(field.title) {
                    if field.requiresConfirmation { needsConfirmation = true }
                    else { _ = submit(nil, false) }
                }
            case let .choice(options, current):
                if isInline {
                    choiceMenu(options: options, current: requestedValue?.controlString ?? current)
                        .menuStyle(.borderlessButton)
                        .font(.system(size: 14, weight: .semibold))
                        .fixedSize()
                } else {
                    LabeledContent(field.title) {
                        choiceMenu(options: options, current: requestedValue?.controlString ?? current)
                            .frame(maxWidth: 180)
                    }
                }
            case let .number(_, range, step, unit):
                if isInline {
                    numberInput(range: range, step: step, unit: unit)
                } else {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(field.title).font(.subheadline)
                        numberInput(range: range, step: step, unit: unit)
                        Text("\(range.lowerBound.formatted()) - \(range.upperBound.formatted())\(step.map { ", step " + $0.formatted() } ?? "")")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            case let .boolean(current):
                let current = requestedValue?.controlBool ?? current
                if isInline, let current {
                    CompactSwitch(isOn: current, isRunning: isRunning) { _ = submit(.bool($0), false) }
                        .accessibilityLabel("\(field.title) for \(entityName)")
                } else {
                    LabeledContent(isInline ? "" : field.title) {
                        Menu(current.map { $0 ? "On" : "Off" } ?? "Choose") {
                            Button("On") { _ = submit(.bool(true), false) }
                            Button("Off") { _ = submit(.bool(false), false) }
                        }
                    }
                }
            case .color:
                HStack {
                    ColorPicker(field.title, selection: $color, supportsOpacity: false)
                    Button("Set") {
                        guard let rgb = NSColor(color).usingColorSpace(.sRGB) else { return }
                        _ = submit(.array([rgb.redComponent, rgb.greenComponent, rgb.blueComponent].map { .number(($0 * 255).rounded()) }), false)
                    }
                }
            case .text:
                if isInline {
                    HStack(spacing: 4) {
                        TextField("Message", text: $text)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 120)
                            .onSubmit { sendMessage() }
                            .accessibilityLabel("Message for \(entityName)")
                        Button(action: sendMessage) { Image(systemName: "paperplane") }
                            .accessibilityLabel("Send message to \(entityName)")
                            .disabled(field.actionSpec(value: .string(text)) == nil)
                    }
                } else {
                    VStack(alignment: .leading, spacing: 6) {
                        TextField("Message", text: $text, axis: .vertical)
                            .lineLimit(3...6).textFieldStyle(.roundedBorder)
                        Button("Send message", action: sendMessage)
                            .disabled(field.actionSpec(value: .string(text)) == nil)
                    }
                }
            }
            if field.input.reportsValue && showsRequestedIndicator {
                PearchHARequestedControlIndicator(isRequested: requestedValue != nil)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(field.title) for \(entityName)")
        .confirmationDialog("\(field.title) for \(entityName)?", isPresented: $needsConfirmation, titleVisibility: .visible) {
            Button(field.title) { _ = submit(nil, true) }
            Button("Cancel", role: .cancel) {}
        }
        .onAppear { synchronize() }
        .onChange(of: field) { _ in
            if !isEditingNumber && !isSliding && pendingNumberTask == nil {
                synchronize()
            } else if changedNumberValue == nil {
                cancelPendingNumber()
            }
        }
        .onChange(of: isEditingNumber) { editing in
            if !editing { isNumberEntryPresented = false }
            if !editing && !isSliding && pendingNumberTask == nil { synchronize() }
        }
        .onChange(of: isRunning) { running in
            if !running && !isEditingNumber && !isSliding && pendingNumberTask == nil { synchronize() }
        }
        .onChange(of: requestedValue) { [requestedValue] newValue in
            if !isSliding && pendingNumberTask == nil && (!isEditingNumber || numberValue == requestedValue?.controlNumber) {
                synchronize(using: newValue)
            }
        }
        .onChange(of: isEnabled) { enabled in
            if !enabled { cancelPendingNumber() }
        }
        .onChange(of: coverMode) { _ in
            cancelPendingNumber()
            synchronize()
        }
        .onDisappear { cancelPendingNumber() }
    }

    private func choiceMenu(options: [String], current: String?) -> some View {
        Menu(current ?? "Choose") {
            ForEach(options, id: \.self) { option in
                Button {
                    _ = submit(.string(option), false)
                } label: {
                    if option == current { Label(option, systemImage: "checkmark") }
                    else { Text(option) }
                }
            }
        }
        .accessibilityLabel("\(field.title) for \(entityName)")
    }

    private func numberInput(range: ClosedRange<Double>, step: Double?, unit: String?) -> some View {
        let usesSlider = field.prefersSlider && range.lowerBound < range.upperBound
        return HStack(spacing: isInline ? 4 : 6) {
            if coverMode?.showsButtons == true {
                coverButton(.open, icon: "arrow.up.to.line", title: "Open")
                coverButton(.stop, icon: "stop.fill", title: "Stop")
                coverButton(.close, icon: "arrow.down.to.line", title: "Close")
            }
            if coverMode == nil || (coverMode?.showsSlider == true && reportedNumber != nil) {
                if usesSlider {
                    Slider(value: Binding(get: { numberValue ?? reportedNumber ?? range.lowerBound }, set: { value in
                        let snapped = step.map { range.lowerBound + ((value - range.lowerBound) / $0).rounded() * $0 } ?? value
                        updateNumberDraft(snapped.formatted(.number.grouping(.never).precision(.fractionLength(0...8))))
                    }), in: range) { editing in
                        isSliding = editing
                        isNumberEntryPresented = false
                        isEditingNumber = false
                        cancelPendingNumber()
                        if !editing { sendNumber() }
                    }
                    .accessibilityLabel("\(field.title) for \(entityName)")
                    .accessibilityValue(numberValue.map { PearchHASliderValueFormatting.accessibilityValue(for: $0, unit: unit) } ?? "Not reported")
                    .frame(minWidth: 50)
                    .frame(width: isInline && coverMode == nil ? 80 : nil)
                }
                Group {
                    if usesSlider && !isNumberEntryPresented {
                        Button(text.isEmpty ? "-" : text + (unit.map { " " + $0 } ?? "")) {
                            isNumberEntryPresented = true
                        }
                        .buttonStyle(.borderless)
                        .help("Click to enter an exact value")
                        .accessibilityLabel("Edit \(field.title) for \(entityName)")
                        .accessibilityValue(text.isEmpty ? "Not reported" : text + (unit.map { " " + $0 } ?? ""))
                    } else {
                        HStack(spacing: 3) {
                            numberTextField
                                .textFieldStyle(.plain)
                                .multilineTextAlignment(.trailing)
                                .foregroundStyle(isEditingNumber && numberValue.flatMap { field.actionSpec(value: .number($0)) } == nil ? Color.red : Color.primary)
                                .overlay(alignment: .bottom) {
                                    Rectangle().fill(Color.accentColor).frame(height: 1).opacity(isEditingNumber ? 1 : 0)
                                }
                                .task {
                                    guard usesSlider else { return }
                                    await Task.yield()
                                    guard !Task.isCancelled else { return }
                                    isEditingNumber = true
                                }
                            if let unit { Text(unit).foregroundStyle(.secondary).fixedSize() }
                        }
                    }
                }
                .font(.system(size: 14).monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 62, alignment: .trailing)
                if !usesSlider, let step, range.lowerBound < range.upperBound {
                    Stepper("", onIncrement: { adjust(by: step, range: range) }, onDecrement: { adjust(by: -step, range: range) })
                        .labelsHidden()
                        .controlSize(.small)
                        .fixedSize()
                        .accessibilityLabel("Adjust \(field.title) for \(entityName)")
                }
                if !isInline && !usesSlider { Spacer(minLength: 0) }
            }
        }
    }

    private func coverButton(_ command: PearchHACoverCommand, icon: String, title: String) -> some View {
        Button {
            cancelPendingNumber()
            isSliding = false
            isNumberEntryPresented = false
            synchronize()
            isEditingNumber = false
            _ = runCoverCommand?(command)
        } label: {
            PearchHACircularIconLabel(icon: icon, disabled: !isEnabled)
        }
        .buttonStyle(.borderless)
        .help(isRunning ? "Waiting for Home Assistant" : "\(title) \(entityName)")
        .accessibilityLabel("\(title) \(entityName)")
    }

    private var reportedNumber: Double? {
        if case let .number(current, _, _, _) = field.input { return current }
        return nil
    }

    private var numberTextField: some View {
        TextField(isInline ? "Value" : "Not reported", text: Binding(get: { text }, set: { updateNumberDraft($0) }))
            .focused($isEditingNumber)
            .onSubmit { sendNumber() }
            .onExitCommand { cancelPendingNumber(); synchronize(); isEditingNumber = false; isNumberEntryPresented = false }
            .accessibilityLabel("\(field.title) for \(entityName)")
            .accessibilityHint("Applies after a short pause. Return applies immediately. Escape cancels pending changes.")
    }

    private func sendMessage() {
        _ = submit(.string(text), false)
    }

    private var numberValue: Double? {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.usesGroupingSeparator = false
        formatter.isLenient = false
        var value: AnyObject?
        var range = NSRange(location: 0, length: text.utf16.count)
        do {
            try formatter.getObjectValue(&value, for: text, range: &range)
        } catch {
            return nil
        }
        guard range.location == 0, range.length == text.utf16.count else { return nil }
        return (value as? NSNumber)?.doubleValue
    }

    private func sendNumber() {
        cancelPendingNumber()
        guard isEnabled, let numberValue, field.actionSpec(value: .number(numberValue)) != nil else { return }
        if changedNumberValue == nil || submit(.number(numberValue), false) {
            isEditingNumber = false
            isNumberEntryPresented = false
        }
    }

    private var changedNumberValue: Double? {
        guard let numberValue, case let .number(current, _, _, _) = field.input,
              numberValue != (requestedValue?.controlNumber ?? current), field.actionSpec(value: .number(numberValue)) != nil else { return nil }
        return numberValue
    }

    private func updateNumberDraft(_ value: String) {
        text = value
        cancelPendingNumber()
        guard isEnabled, !isSliding, changedNumberValue != nil else { return }
        pendingNumberTask = Task { @MainActor in
            do {
                _ = try await clock.sleep(for: .milliseconds(600))
            } catch {
                return // A new edit, explicit submission or dismissal cancels the timer.
            }
            guard !Task.isCancelled else { return }
            sendNumber()
        }
    }

    private func cancelPendingNumber() {
        pendingNumberTask?.cancel()
        pendingNumberTask = nil
    }

    private func adjust(by step: Double, range: ClosedRange<Double>) {
        let value = min(max((numberValue ?? range.lowerBound) + step, range.lowerBound), range.upperBound)
        updateNumberDraft(value.formatted(.number.grouping(.never).precision(.fractionLength(0...8))))
    }

    private func synchronize() {
        synchronize(using: requestedValue)
    }

    private func synchronize(using requestedValue: ActionValue?) {
        switch field.input {
        case let .number(current, _, _, _):
            text = (requestedValue?.controlNumber ?? current).map { $0.formatted(.number.grouping(.never).precision(.fractionLength(0...8))) } ?? ""
        case let .color(current):
            let requestedComponents: [Double]?
            if case let .array(values) = requestedValue { requestedComponents = values.compactMap(\.controlNumber) }
            else { requestedComponents = nil }
            if let current = requestedComponents ?? current {
                color = Color(.sRGB, red: current[0] / 255, green: current[1] / 255, blue: current[2] / 255)
            }
        case .action, .choice, .boolean, .text:
            break
        }
    }
}

/// A quiet, non-animated status shared by inline controls and their editor.
struct PearchHARequestedControlIndicator: View {
    let isRequested: Bool

    var body: some View {
        ZStack {
            if isRequested {
                Image(systemName: "clock")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .help("Requested. Waiting for the next value from Home Assistant.")
                    .accessibilityLabel("Requested")
                    .accessibilityHint("Waiting for the next value from Home Assistant")
            }
        }
        .frame(width: 12, height: 12)
    }
}
