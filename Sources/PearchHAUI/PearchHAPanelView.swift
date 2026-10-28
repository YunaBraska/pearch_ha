import Foundation
import AppKit
import Combine
import SwiftUI
import UniformTypeIdentifiers
import PearchHACore
import PearchHASupport

private struct PanelSelectionDropDelegate: DropDelegate {
    let translation: SelectionDropTranslation
    let setTargeted: (Bool) -> Void
    let move: () -> Bool

    func validateDrop(info: DropInfo) -> Bool {
        return translation != .unsupported
    }

    func dropEntered(info: DropInfo) { setTargeted(validateDrop(info: info)) }

    func dropExited(info: DropInfo) { setTargeted(false) }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: validateDrop(info: info) ? .move : .forbidden)
    }

    func performDrop(info: DropInfo) -> Bool {
        setTargeted(false)
        guard validateDrop(info: info) else { return false }
        return move()
    }
}

@MainActor
private final class PearchHAPanelViewState: ObservableObject {
    @Published private(set) var snapshot: PearchHAPanelSnapshot
    @Published private(set) var oauthSignInState: PearchHAOAuthSignInState
    @Published private(set) var displayPreferences: PearchHADisplayPreferences
    @Published private(set) var isInitialHistoryLoading: Bool
    private var controlRequestsSubscription: AnyCancellable?

    init(model: PearchHAPanelModel) {
        self.snapshot = model.snapshot
        self.oauthSignInState = model.oauthSignInState
        self.displayPreferences = model.displayPreferences
        self.isInitialHistoryLoading = model.isInitialHistoryLoading
        model.$snapshot
            .receive(on: RunLoop.main)
            .assign(to: &$snapshot)
        model.$oauthSignInState
            .receive(on: RunLoop.main)
            .assign(to: &$oauthSignInState)
        model.$displayPreferences
            .receive(on: RunLoop.main)
            .assign(to: &$displayPreferences)
        model.$isInitialHistoryLoading
            .receive(on: RunLoop.main)
            .assign(to: &$isInitialHistoryLoading)
        controlRequestsSubscription = model.requestedControlsPublisher
            .receive(on: RunLoop.main)
            .sink { [weak self] in self?.objectWillChange.send() }
    }
}

@MainActor
private final class PearchHAEntityHistoryRevisionObserver: ObservableObject {
    @Published private(set) var revision: UInt64 = 0

    private var cancellable: AnyCancellable?

    init(model: PearchHAPanelModel, entityID: EntityID) {
        self.cancellable = model.historyRevisionPublisher(for: entityID)
            .receive(on: RunLoop.main)
            .assign(to: \.revision, on: self)
    }
}

private struct PearchHAInlineHistoryPreview: View {
    let model: PearchHAPanelModel
    let entity: DiscoveredEntity
    let presentation: PearchHAEntityRowPresentation
    let value: FormattedEntityValue
    let palette: PearchHATheme.DashboardPalette
    @StateObject private var historyObserver: PearchHAEntityHistoryRevisionObserver

    init(
        model: PearchHAPanelModel,
        entity: DiscoveredEntity,
        presentation: PearchHAEntityRowPresentation,
        value: FormattedEntityValue,
        palette: PearchHATheme.DashboardPalette
    ) {
        self.model = model
        self.entity = entity
        self.presentation = presentation
        self.value = value
        self.palette = palette
        _historyObserver = StateObject(
            wrappedValue: PearchHAEntityHistoryRevisionObserver(model: model, entityID: entity.id)
        )
    }

    var body: some View {
        let _ = historyObserver.revision
        if entity.id.source == .thisMac {
            preview
                .frame(width: TelemetryRowMetrics.previewWidth, height: TelemetryRowMetrics.previewHeight)
                .help(LocalMacText.historyUnavailable.localized())
                .accessibilityLabel(LocalMacText.readOnly.localized())
        } else {
            Button {
                model.presentHistoryDetail(entity.id)
            } label: {
                preview
                    .frame(width: TelemetryRowMetrics.previewWidth, height: TelemetryRowMetrics.previewHeight)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Show history for \(entity.name)")
            .accessibilityLabel("Show history for \(entity.name)")
        }
    }

    @ViewBuilder
    private var preview: some View {
        let _ = historyObserver.revision
        let configuration = model.snapshot.effectiveMenuBarItemConfiguration(for: entity)
        let numericPreviewColor = PearchHAHistoryTint.numericAccent(for: entity, configuration: configuration)
            .map(PearchHATheme.color(for:))
            ?? palette.chartPrimary
        let numericPreviewThresholdColor: (Double) -> Color? = { value in
            PearchHAHistoryTint.numericAccent(for: value, entity: entity, configuration: configuration)
                .map(PearchHATheme.color(for:))
        }
        let statePreviewColor: (String) -> Color = { state in
            if let accent = PearchHAHistoryTint.stateAccent(for: state, entity: entity, configuration: configuration) {
                return PearchHATheme.color(for: accent)
            }
            return PearchHATheme.color(for: HistoryStateColorKind.classify(state))
        }
        if case let .gauge(gauge) = presentation,
           (gauge.style != .ring || entity.id.source == .thisMac),
           PearchHADashboardPreview.meterShows(for: value.status) {
            MicroMeter(
                fraction: gauge.fraction,
                color: palette.severityColor(gauge.severity),
                trackColor: palette.meterTrack
            )
            .frame(width: 54, height: 6)
        } else if let preview = model.cachedInlinePreview(for: entity.id) {
            switch preview {
            case let .sparkline(geometry):
                MicroSparkline(
                    geometry: geometry,
                    color: numericPreviewColor,
                    muted: palette.chartMuted,
                    colorForValue: numericPreviewThresholdColor
                )
                    .frame(width: TelemetryRowMetrics.previewWidth, height: 22)
            case let .state(series):
                MicroActivityBars(
                    series: series,
                    muted: palette.chartMuted,
                    colorForState: statePreviewColor
                )
                    .frame(width: TelemetryRowMetrics.previewWidth, height: 7)
            case .placeholder:
                MicroDash(color: palette.chartMuted)
            }
        } else {
            MicroDash(color: palette.chartMuted)
        }
    }
}

private struct PearchHAHistoryDetailView: View {
    @ObservedObject var model: PearchHAPanelModel
    let entity: DiscoveredEntity
    let onOpenEntitySettings: ((EntityID) -> Void)?

    var body: some View {
        PearchHAHistoryPopoverContent(
            entityID: entity.id,
            entityName: entity.name,
            valueText: model.formattedValue(for: entity).text,
            unit: entity.unit,
            fillsPanel: true,
            state: model.snapshot.historyState,
            chartTint: historyChartTint,
            numericColorForValue: historyNumericColor,
            stateColorForTimeline: historyStateColor,
            onOpenSettings: {
                onOpenEntitySettings?(entity.id)
            },
            disabledRanges: model.knownUnavailableHistoryRanges(for: entity.id),
            selectedRange: Binding(
                get: {
                    model.snapshot.historyState.range ?? model.historyRange(for: entity.id)
                },
                set: { range in
                    model.presentHistoryDetail(entity.id, range: range)
                }
            )
        )
    }

    private var configuration: MenuBarItemConfiguration {
        model.snapshot.effectiveMenuBarItemConfiguration(for: entity)
    }

    private var historyChartTint: Color? {
        PearchHAHistoryTint.numericAccent(for: entity, configuration: configuration).map(PearchHATheme.color(for:))
    }

    private var historyNumericColor: (Double) -> Color? {
        { value in
            PearchHAHistoryTint.numericAccent(for: value, entity: entity, configuration: configuration)
                .map(PearchHATheme.color(for:))
        }
    }

    private var historyStateColor: (String) -> Color {
        { state in
            if let accent = PearchHAHistoryTint.stateAccent(for: state, entity: entity, configuration: configuration) {
                return PearchHATheme.color(for: accent)
            }
            return PearchHATheme.color(for: HistoryStateColorKind.classify(state))
        }
    }
}

public struct PearchHAPanelView: View {
    private let model: PearchHAPanelModel
    private let accessibilityPreferencesOverride: PearchHAAccessibilityPreferences?
    private let onOpenSettings: (() -> Void)?
    private let onOpenEntitySettings: ((EntityID) -> Void)?
    @StateObject private var viewState: PearchHAPanelViewState
    @State private var pendingCustomActionID: CustomActionID?
    @State private var expandedModuleIDs: Set<String> = []
    @State private var draggedSelectionItem: SelectionDragItem?
    @State private var targetedSelectionItem: SelectionDragItem?

    private static let panelSelectionDragType = UTType(exportedAs: PearchHAPanelDrag.typeIdentifier, conformingTo: .data)
    @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast
    @Environment(\.colorScheme) private var colorScheme

    public init(
        model: PearchHAPanelModel,
        accessibilityPreferencesOverride: PearchHAAccessibilityPreferences? = nil,
        onOpenSettings: (() -> Void)? = nil,
        onOpenEntitySettings: ((EntityID) -> Void)? = nil
    ) {
        self.model = model
        self.accessibilityPreferencesOverride = accessibilityPreferencesOverride
        self.onOpenSettings = onOpenSettings
        self.onOpenEntitySettings = onOpenEntitySettings
        _viewState = StateObject(wrappedValue: PearchHAPanelViewState(model: model))

    }

    private func openSettings() {
        if let onOpenSettings {
            onOpenSettings()
        } else {
            model.toggleSettings()
        }
    }

    private var snapshot: PearchHAPanelSnapshot {
        viewState.snapshot
    }

    private var panelDisplayPreferences: PearchHADisplayPreferences {
        viewState.displayPreferences
    }

    private var oauthState: PearchHAOAuthSignInState {
        viewState.oauthSignInState
    }

    public var body: some View {
        let accessibility = Self.rootAccessibilityPresentation(
            snapshot: snapshot,
            preferences: accessibilityPreferences
        )
        let palette = PearchHATheme.Dashboard.palette(colorScheme)
        let shape = RoundedRectangle(cornerRadius: PearchHATheme.Dashboard.panelCornerRadius, style: .continuous)
        return VStack(alignment: .leading, spacing: 0) {
            if showsTopBar {
                topBar
                dashboardDivider
            }
            ZStack(alignment: .topLeading) {
                content
                    .opacity(snapshot.historyPresentationEntityID == nil ? 1 : 0)
                    .allowsHitTesting(snapshot.historyPresentationEntityID == nil)
                    .accessibilityHidden(snapshot.historyPresentationEntityID != nil)
                if let id = snapshot.historyPresentationEntityID,
                   let entity = snapshot.availableRooms.flatMap(\.entities).first(where: { $0.id == id }) {
                    VStack(alignment: .leading, spacing: 8) {
                        Button { model.dismissHistoryPopover() } label: {
                            Label("Back to rooms", systemImage: "chevron.left")
                        }
                        .buttonStyle(.borderless)
                        .accessibilityLabel("Back to rooms")
                        .padding(.horizontal, 16).padding(.top, 12)
                        ScrollView {
                            PearchHAHistoryDetailView(model: model, entity: entity, onOpenEntitySettings: onOpenEntitySettings)
                        }
                    }
                }
            }
            dashboardDivider
            footer
        }
        .frame(width: 384, height: 468, alignment: .top)
        .environment(\.dashboardPalette, palette)
        .environment(\.dashboardRowDensity, panelDisplayPreferences.dashboardRowDensity)
        .tint(PearchHATheme.accent)
        .background(palette.surfaceRoot)
        .clipShape(shape)
        .overlay {
            shape.strokeBorder(
                accessibility.contrastPolicy == .increased
                    ? (colorScheme == .dark ? Color.white.opacity(0.32) : Color.black.opacity(0.40))
                    : palette.borderEmphatic,
                lineWidth: 1
            )
        }
        .shadow(color: Color.black.opacity(colorScheme == .dark ? 0.45 : 0.22), radius: 18, x: 0, y: 8)
        .contrast(accessibility.contrastPolicy == .increased ? 1.12 : 1)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(accessibility.label)
        .accessibilityValue(accessibility.value)
        .accessibilityHint(accessibility.hint)
        .transaction { transaction in
            if accessibility.motionPolicy == .reduced {
                transaction.animation = nil
            }
        }
        .confirmationDialog(
            pendingCustomAction.map { "Run \($0.title)?" } ?? "Run action?",
            isPresented: customActionConfirmationBinding,
            titleVisibility: .visible
        ) {
            if let action = pendingCustomAction {
                Button(action.title) {
                    model.startCustomAction(action.id, confirmed: true)
                    pendingCustomActionID = nil
                }
            }
            Button("Cancel", role: .cancel) {
                pendingCustomActionID = nil
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSMenu.didBeginTrackingNotification)) { _ in
            model.beginTransientUITracking()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSMenu.didEndTrackingNotification)) { _ in
            model.endTransientUITracking()
        }
        .onDisappear {
            draggedSelectionItem = nil
            targetedSelectionItem = nil
        }
    }

    public static func rootAccessibilityPresentation(
        snapshot: PearchHAPanelSnapshot,
        preferences: PearchHAAccessibilityPreferences = PearchHAAccessibilityPreferences()
    ) -> PearchHAPanelRootAccessibilityPresentation {
        PearchHAPanelRootAccessibilityPresentation(
            panel: snapshot.accessibilityPresentation(preferences: preferences)
        )
    }

    public static func entityContextPresentation(
        snapshot: PearchHAPanelSnapshot,
        entityID: EntityID
    ) -> PearchHAPanelEntityContextPresentation {
        let configuration = snapshot.menuBarDisplayConfiguration.itemConfiguration(for: entityID)
        return PearchHAPanelEntityContextPresentation(
            isPromotedToMenuBar: snapshot.menuBarDisplayConfiguration.isPromoted(entityID),
            hasAverageLinks: !configuration.averageEntityIDs.isEmpty,
            showsEntityIcon: configuration.showsEntityIcon,
            showsLabel: configuration.showsLabel,
            showsUnit: configuration.showsUnit
        )
    }

    private var accessibilityPreferences: PearchHAAccessibilityPreferences {
        if let accessibilityPreferencesOverride {
            return accessibilityPreferencesOverride
        }
        return PearchHAAccessibilityPreferences(
            reduceMotion: accessibilityReduceMotion,
            increaseContrast: colorSchemeContrast == .increased
        )
    }

    private var pendingCustomAction: EntityCustomAction? {
        pendingCustomActionID.flatMap { model.customAction(id: $0) }
    }

    private var customActionConfirmationBinding: Binding<Bool> {
        Binding(
            get: {
                pendingCustomActionID != nil
            },
            set: { isPresented in
                if !isPresented {
                    pendingCustomActionID = nil
                }
            }
        )
    }

    private var dashboardDivider: some View {
        Rectangle()
            .fill(PearchHATheme.Dashboard.palette(colorScheme).separator)
            .frame(height: 1)
    }

    /// Whether the panel shows a header at all. While connected it does not —
    /// the footer's status dot already communicates connection health, and every
    /// vertical point goes to entity rows instead. Onboarding/connecting/failed
    /// phases keep the compact status row so those states stay explicit.
    private var showsTopBar: Bool {
        switch snapshot.phase {
        case .connectedData, .reconnecting, .failedStale:
            false
        case .firstRun, .connecting, .connectedEmpty, .failed:
            true
        }
    }

    private var topBar: some View {
        statusBar
    }

    private var statusBar: some View {
        let palette = PearchHATheme.Dashboard.palette(colorScheme)
        return HStack(spacing: PearchHASpacing.sm - 2) {
            Circle()
                .fill(connectionStatusColor)
                .frame(width: 7, height: 7)
                .accessibilityHidden(true)
            Text("PearchHA")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(palette.textPrimary)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, PearchHASpacing.md)
        .padding(.top, PearchHASpacing.md)
        .padding(.bottom, PearchHASpacing.sm)
        .onHover { isInside in
            if isInside {
                model.dismissHistoryPopover()
            }
        }
    }

    private var connectionStatusColor: Color {
        let palette = PearchHATheme.Dashboard.palette(colorScheme)
        return snapshot.isLocalOnly ? palette.accentPrimary : palette.connectionColor(snapshot.connectionState)
    }

    @ViewBuilder
    private var content: some View {
        switch snapshot.hasLocalValues ? .data : PearchHAStateViewKind.forContent(phase: snapshot.phase) {
        case .loading:
            loadingState
        case .connectionForm:
            connectionForm
        case .empty:
            connectedEmptyState
        case .data:
            ZStack {
                if viewState.isInitialHistoryLoading && !snapshot.hasLocalValues {
                    Text("Loading")
                        .font(.system(size: 13))
                        .foregroundStyle(PearchHATheme.Dashboard.palette(colorScheme).textSecondary)
                } else {
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 18) {
                            ForEach(visibleModules, id: \.id.rawValue) { room in
                                moduleBlock(room)
                            }
                        }
                        .padding(.top, 4)
                        .padding(.bottom, 14)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    /// The rooms shown on the dashboard after applying the user's hidden-module
    /// display preference. Hiding every available module would leave a blank
    /// dashboard, so when the preference would hide all of them the filter is
    /// ignored and every room is shown.
    private var visibleModules: [Room] {
        let hidden = panelDisplayPreferences.hiddenModuleIDs
        guard !hidden.isEmpty else {
            return snapshot.rooms
        }
        let filtered = snapshot.rooms.filter { !hidden.contains($0.id.rawValue) }
        return filtered.isEmpty ? snapshot.rooms : filtered
    }

    /// The number of telemetry rows shown per module before the rest collapse
    /// behind a quiet "More" affordance, from the user's display preferences
    /// (`nil` = no limit). Overflow stays reachable by expanding the module in
    /// place; every entity is still reachable via Settings.
    private var curatedRowCap: Int? {
        panelDisplayPreferences.dashboardRoomRowCap
    }

    private var loadingState: some View {
        PearchHALoadingState(
            title: "Connecting…",
            message: "Reaching your Home Assistant and loading values."
        )
    }

    private var connectedEmptyState: some View {
        PearchHAEmptyState(
            systemImage: "square.dashed",
            title: "No values yet",
            message: "Pick the rooms and sensors you want to keep an eye on.",
            actionTitle: "Choose values…",
            actionSystemImage: "slider.horizontal.3",
            actionDisabled: snapshot.availableRooms.isEmpty,
            action: { openSettings() }
        )
    }

    /// The menu-bar panel never hosts the connection form: the dropdown is a
    /// glanceable dashboard, and connection/TLS editing lives in Settings where
    /// there is room to do it properly. First run just points there; while an
    /// OAuth sign-in started from Settings is in flight, the panel reflects it.
    @ViewBuilder
    private var connectionForm: some View {
        if oauthState == .signingIn {
            PearchHALoadingState(
                title: "Signing in…",
                message: "Approve access to Home Assistant in your browser."
            )
        } else {
            PearchHAEmptyState(
                systemImage: "antenna.radiowaves.left.and.right",
                title: "Not connected",
                message: snapshot.failureDescription
                    ?? "Connect PearchHA to your Home Assistant in Settings.",
                actionTitle: "Open Settings…",
                actionSystemImage: "gearshape",
                actionDisabled: false,
                action: { openSettings() }
            )
        }
    }
    /// A curated module of telemetry rows for a room/area.
    ///
    /// The module is integrated into the single popover surface: a small uppercase
    /// ``ModuleHeader`` over a run of ``TelemetryRow``s separated by an
    /// almost-invisible inset hairline — no bordered card. Only the first
    /// ``curatedRowCap`` rows show until the module is expanded in place via a
    /// quiet "More" affordance; every entity stays reachable.
    private func moduleBlock(_ room: Room) -> some View {
        let isExpanded = expandedModuleIDs.contains(room.id.rawValue)
        let total = room.entities.count
        let cap = curatedRowCap
        let visibleEntities = (isExpanded || cap == nil) ? room.entities : Array(room.entities.prefix(cap ?? total))
        let hiddenCount = total - visibleEntities.count
        let roomIndex = visibleModules.firstIndex { $0.id == room.id }
        let earlier = roomIndex.flatMap { $0 > 0 ? visibleModules[$0 - 1] : nil }
        let later = roomIndex.flatMap { $0 + 1 < visibleModules.count ? visibleModules[$0 + 1] : nil }
        let block = ModuleBlock(
            title: room.name,
            headerDrag: panelDrag(for: .room(room.id), title: room.name),
            moveEarlier: earlier.map { target in { _ = model.moveRoom(room.id, relativeTo: target.id, placement: .before) } },
            moveLater: later.map { target in { _ = model.moveRoom(room.id, relativeTo: target.id, placement: .after) } }
        ) {
            ForEach(Array(visibleEntities.enumerated()), id: \.element.id.rawValue) { index, entity in
                entityRowBlock(entity, showsSeparator: index < visibleEntities.count - 1)
            }
            if let cap, total > cap {
                TelemetryRowSeparator()
                moreAffordance(roomID: room.id.rawValue, isExpanded: isExpanded, hiddenCount: hiddenCount)
            }
        }
        return panelDropTarget(block, item: .room(room.id))
    }

    private func entityRowBlock(_ entity: DiscoveredEntity, showsSeparator: Bool) -> some View {
        let value = entityValue(entity)
        let contextPresentation = Self.entityContextPresentation(snapshot: snapshot, entityID: entity.id)
        let row = VStack(spacing: 0) {
            telemetryRow(entity)
            if showsSeparator {
                TelemetryRowSeparator()
            }
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(entity.name), \(value.text)")
        .accessibilityActions { panelReorderActions(for: entity.id) }
        .contextMenu {
            entityContextMenu(for: entity, contextPresentation: contextPresentation)
            Divider()
            panelReorderActions(for: entity.id)
        }
        let accessibleRow: AnyView
        if entity.id.source == .thisMac {
            accessibleRow = AnyView(row)
        } else {
            accessibleRow = AnyView(
                row
                    .accessibilityAction(named: "Show history") {
                        model.presentHistoryDetail(entity.id)
                    }
                    .accessibilityAction(named: "Hide history") {
                        model.dismissHistoryPopover()
                    }
            )
        }
        return panelDropTarget(accessibleRow, item: .entity(entity.id))
    }

    private var panelSelectionTree: [SelectableRoom] {
        EntitySelectionProjector().selectionTree(
            rooms: snapshot.availableRooms,
            configuration: snapshot.selectionConfiguration
        )
    }

    private func panelDropTarget<Content: View>(_ content: Content, item: SelectionDragItem) -> some View {
        let translation = draggedSelectionItem.map {
            SelectionDropTranslator().translate(source: $0, target: item, tree: panelSelectionTree)
        } ?? .unsupported
        let placement: SelectionDropPlacement? = switch translation {
        case let .room(_, _, placement), let .entity(_, _, placement): placement
        case .unsupported: nil
        }
        return content
            .overlay(alignment: .top) {
                if targetedSelectionItem == item, let placement {
                    Rectangle()
                        .fill(PearchHATheme.accent)
                        .frame(height: 2)
                        .padding(.horizontal, 8)
                        .frame(maxHeight: .infinity, alignment: placement == .before ? .top : .bottom)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }
            }
            .onDrop(of: [Self.panelSelectionDragType], delegate: PanelSelectionDropDelegate(
                translation: translation,
                setTargeted: { isTargeted in
                    if isTargeted { targetedSelectionItem = item }
                    else if targetedSelectionItem == item { targetedSelectionItem = nil }
                },
                move: {
                    defer { draggedSelectionItem = nil }
                    return applyPanelDrop(translation)
                }
            ))
    }

    @ViewBuilder
    private func panelReorderActions(for entityID: EntityID) -> some View {
        let item = SelectionDragItem.entity(entityID)
        let items = snapshot.rooms.first { $0.entities.contains { $0.id == entityID } }?.entities.map { SelectionDragItem.entity($0.id) } ?? []
        if let index = items.firstIndex(of: item) {
            if index > 0 {
                Button("Move earlier") {
                    _ = applyPanelDrop(SelectionDropTranslator().translate(source: item, target: items[index - 1], tree: panelSelectionTree))
                }
            }
            if index + 1 < items.count {
                Button("Move later") {
                    _ = applyPanelDrop(SelectionDropTranslator().translate(source: item, target: items[index + 1], tree: panelSelectionTree))
                }
            }
        }
    }

    private func applyPanelDrop(_ translation: SelectionDropTranslation) -> Bool {
        switch translation {
        case let .room(source, target, placement):
            return model.moveRoom(source, relativeTo: target, placement: placement)
        case let .entity(source, target, placement):
            return model.moveEntity(source, relativeTo: target, placement: placement)
        case .unsupported:
            return false
        }
    }

    private func panelDrag(for item: SelectionDragItem, title: String) -> PearchHAPanelDrag {
        PearchHAPanelDrag(
            payload: item.providerText,
            title: title,
            onBegin: {
                draggedSelectionItem = item
                model.beginTransientUITracking()
            },
            onEnd: { _ in
                draggedSelectionItem = nil
                targetedSelectionItem = nil
                model.endTransientUITracking()
            }
        )
    }

    /// A quiet "More" / "Less" affordance that expands or collapses a module in
    /// place, keeping overflow rows reachable without a database dump.
    private func moreAffordance(roomID: String, isExpanded: Bool, hiddenCount: Int) -> some View {
        let palette = PearchHATheme.Dashboard.palette(colorScheme)
        let title = isExpanded ? "Show less" : "\(hiddenCount) more"
        return Button {
            if isExpanded {
                expandedModuleIDs.remove(roomID)
            } else {
                expandedModuleIDs.insert(roomID)
            }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                    .font(.system(size: 9, weight: .semibold))
                Text(title)
                    .font(.system(size: 11, weight: .medium))
                Spacer(minLength: 0)
            }
            .foregroundStyle(palette.textSecondary)
            .padding(.horizontal, 16)
            .padding(.vertical, 7)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isExpanded ? "Show fewer entities" : "Show \(hiddenCount) more entities")
    }

    /// A compact cockpit telemetry row built on the reusable ``TelemetryRow``.
    ///
    /// Built as a fixed-column reserved grid: the domain icon + name (+ optional
    /// unit subtitle), then an always-present reserved history-preview column (an
    /// inline micro chart drawn only from already-cached history, or a muted
    /// placeholder when nothing is cached — never fetches on render or scroll),
    /// then the right-aligned value/status column, then a reserved control column
    /// holding at most one compact control. Cover controls, when enabled, drop
    /// onto a compact second line. Reserving the columns keeps every row aligned
    /// and lets cached data fill its slot in place without any layout shift.
    private func telemetryRow(_ entity: DiscoveredEntity) -> some View {
        let value = entityValue(entity)
        let presentation = model.rowPresentation(for: entity)
        let contextPresentation = Self.entityContextPresentation(snapshot: snapshot, entityID: entity.id)
        // Direct switches already communicate the state. Additional settings
        // use an icon beside the switch instead of repeating its on/off value.
        let hasToggle = snapshot.control(for: entity) != nil
        let fields = PearchHAEntityControlField.controls(for: entity)
        return TelemetryRow(
            icon: entityIconName(for: entity),
            iconActive: value.status == .available,
            label: entity.name,
            labelAccessories: rowLabelAccessories(contextPresentation: contextPresentation),
            labelDrag: panelDrag(for: .entity(entity.id), title: entity.name),
            subtitle: rowSubtitle(for: entity, value: value),
            secondLine: rowSecondLine(for: entity),
            preview: { rowPreview(for: entity, presentation: presentation) },
            value: {
                HStack(spacing: 5) {
                    if fields.count == 1, let field = fields.first {
                        PearchHAEntityControlInput(field: field, entityName: entity.name, clock: model.clock, isInline: true,
                                                  isRunning: snapshot.controlActionState.isRunning(for: entity.id),
                                                  requestedValue: model.requestedControlValue(for: entity.id, controlID: field.id),
                                                  showsRequestedIndicator: !hasToggle) { value, confirmed in
                            model.dismissHistoryPopover()
                            return model.startEntityControlValue(entity.id, controlID: field.id, value: value, confirmed: confirmed)
                        }
                        .id(field.id)
                        .disabled(snapshot.connectionState != .connected || snapshot.controlActionState.isRunning)
                        .help(PearchHAEntityControlField.controlHelp(for: entity) ?? "No controls available")
                    } else if !fields.isEmpty {
                        PearchHAEntityControlsButton(model: model, entity: entity) {
                            HStack(spacing: 5) {
                                if !hasToggle {
                                    rowValueOrPill(entity: entity, value: value, presentation: presentation)
                                }
                                Image(systemName: "slider.horizontal.3")
                                    .font(.system(size: 10, weight: .medium))
                                    .foregroundStyle(PearchHATheme.Dashboard.palette(colorScheme).textSecondary)
                                    .accessibilityHidden(true)
                                if !hasToggle {
                                    PearchHARequestedControlIndicator(isRequested: model.hasRequestedControls(for: entity.id))
                                }
                            }
                            .frame(minHeight: TelemetryRowMetrics.previewHeight)
                            .contentShape(Rectangle())
                        }
                    } else if !hasToggle {
                        rowValueOrPill(entity: entity, value: value, presentation: presentation)
                            .help(entity.id.source == .thisMac ? LocalMacText.readOnly.localized() : PearchHAEntityControlField.controlHelp(for: entity) ?? "Read-only")
                    }
                    if hasToggle {
                        PearchHARequestedControlIndicator(isRequested: model.hasRequestedControls(for: entity.id))
                    }
                }
            },
            control: { rowControls(for: entity) }
        )
    }

    private func rowLabelAccessories(
        contextPresentation: PearchHAPanelEntityContextPresentation
    ) -> [TelemetryRowLabelAccessory] {
        let palette = PearchHATheme.Dashboard.palette(colorScheme)
        var accessories: [TelemetryRowLabelAccessory] = []
        if contextPresentation.hasAverageLinks {
            accessories.append(
                .init(
                    systemImage: "link",
                    accessibilityLabel: "Linked values",
                    color: palette.warning
                )
            )
        }
        if contextPresentation.isPromotedToMenuBar {
            accessories.append(
                .init(
                    systemImage: "menubar.rectangle",
                    accessibilityLabel: "Shown in bar",
                    color: palette.accentPrimary
                )
            )
        }
        return accessories
    }

    @ViewBuilder
    private func entityContextMenu(
        for entity: DiscoveredEntity,
        contextPresentation: PearchHAPanelEntityContextPresentation
    ) -> some View {
        Toggle("Show in Bar", isOn: panelMenuBarVisibilityBinding(for: entity.id))
        Divider()
        Menu("Set icon") {
            Button {
                model.setCustomEntityIcon(entity.id, symbolName: nil)
            } label: {
                Label("Automatic icon", systemImage: entityIconName(for: entity) ?? "questionmark.circle")
            }
            Divider()
            ForEach(PearchHAEntityIconCatalog.sections, id: \.title) { section in
                Menu(section.title) {
                    ForEach(section.symbols, id: \.self) { symbol in
                        Button {
                            model.setCustomEntityIcon(entity.id, symbolName: symbol)
                        } label: {
                            Label(symbol, systemImage: symbol)
                        }
                    }
                }
            }
        }
        if Self.entityContextMenuContainsSettingsAction(onOpenEntitySettings: onOpenEntitySettings),
           let onOpenEntitySettings {
            Divider()
            Button {
                onOpenEntitySettings(entity.id)
            } label: {
                Label("Settings", systemImage: "gearshape")
            }
        }
        if contextPresentation.isPromotedToMenuBar {
            Divider()
            Toggle("Show Icon", isOn: panelEntityIconVisibilityBinding(for: entity.id))
            Toggle("Show Label", isOn: panelMenuBarLabelBinding(for: entity.id))
            Toggle("Show Unit", isOn: panelMenuBarUnitBinding(for: entity.id))
        }
    }

    private func makeEntityContextMenu(
        for entity: DiscoveredEntity,
        contextPresentation: PearchHAPanelEntityContextPresentation
    ) -> NSMenu {
        let menu = NSMenu()
        menu.addItem(toggleMenuItem(
            title: "Show in Bar",
            isOn: snapshot.menuBarDisplayConfiguration.isPromoted(entity.id)
        ) {
            model.setMenuBarEntity(entity.id, isVisible: !snapshot.menuBarDisplayConfiguration.isPromoted(entity.id))
        })
        menu.addItem(.separator())

        let iconMenuItem = NSMenuItem(title: "Set icon", action: nil, keyEquivalent: "")
        iconMenuItem.submenu = iconSelectionMenu(for: entity)
        menu.addItem(iconMenuItem)
        if Self.entityContextMenuContainsSettingsAction(onOpenEntitySettings: onOpenEntitySettings),
           let onOpenEntitySettings {
            menu.addItem(.separator())
            menu.addItem(actionMenuItem(title: "Settings", systemImage: "gearshape") {
                onOpenEntitySettings(entity.id)
            })
        }

        if contextPresentation.isPromotedToMenuBar {
            menu.addItem(.separator())
            menu.addItem(toggleMenuItem(
                title: "Show Icon",
                isOn: snapshot.menuBarDisplayConfiguration.itemConfiguration(for: entity.id).showsEntityIcon
            ) {
                let configuration = snapshot.menuBarDisplayConfiguration.itemConfiguration(for: entity.id)
                model.setShowsEntityIcon(entity.id, showsEntityIcon: !configuration.showsEntityIcon)
            })
            menu.addItem(toggleMenuItem(
                title: "Show Label",
                isOn: snapshot.menuBarDisplayConfiguration.itemConfiguration(for: entity.id).showsLabel
            ) {
                let configuration = snapshot.menuBarDisplayConfiguration.itemConfiguration(for: entity.id)
                model.setMenuBarShowsLabel(entity.id, showsLabel: !configuration.showsLabel)
            })
            menu.addItem(toggleMenuItem(
                title: "Show Unit",
                isOn: snapshot.menuBarDisplayConfiguration.itemConfiguration(for: entity.id).showsUnit
            ) {
                let configuration = snapshot.menuBarDisplayConfiguration.itemConfiguration(for: entity.id)
                model.setMenuBarShowsUnit(entity.id, showsUnit: !configuration.showsUnit)
            })
        }

        return menu
    }

    static func entityContextMenuContainsSettingsAction(onOpenEntitySettings: ((EntityID) -> Void)?) -> Bool {
        onOpenEntitySettings != nil
    }

    private func iconSelectionMenu(for entity: DiscoveredEntity) -> NSMenu {
        let menu = NSMenu()
        let automaticSymbol = entityIconName(for: entity) ?? "questionmark.circle"
        menu.addItem(actionMenuItem(
            title: "Automatic icon",
            systemImage: automaticSymbol
        ) {
            model.setCustomEntityIcon(entity.id, symbolName: nil)
        })
        menu.addItem(.separator())
        for section in PearchHAEntityIconCatalog.sections {
            let sectionItem = NSMenuItem(title: section.title, action: nil, keyEquivalent: "")
            let submenu = NSMenu(title: section.title)
            for symbol in section.symbols {
                submenu.addItem(actionMenuItem(title: symbol, systemImage: symbol) {
                    model.setCustomEntityIcon(entity.id, symbolName: symbol)
                })
            }
            sectionItem.submenu = submenu
            menu.addItem(sectionItem)
        }
        return menu
    }

    private func toggleMenuItem(title: String, isOn: Bool, action: @escaping () -> Void) -> NSMenuItem {
        let item = actionMenuItem(title: title, action: action)
        item.state = isOn ? .on : .off
        return item
    }

    private func actionMenuItem(
        title: String,
        systemImage: String? = nil,
        action: @escaping () -> Void
    ) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: #selector(PearchHAMenuActionTarget.performAction(_:)), keyEquivalent: "")
        let target = PearchHAMenuActionTarget(action: action)
        item.target = target
        item.representedObject = target
        if let systemImage, let image = NSImage(systemSymbolName: systemImage, accessibilityDescription: title) {
            item.image = image
        }
        return item
    }

    /// The optional compact second line: a cover control row, then any failure
    /// message. Returns `nil` when there is nothing to show so the row stays a
    /// single line.
    private func rowSecondLine(for entity: DiscoveredEntity) -> AnyView? {
        let palette = PearchHATheme.Dashboard.palette(colorScheme)
        let hasCover = snapshot.coverControl(for: entity) != nil
        let failure = snapshot.controlActionState.failureMessage(for: entity.id)
        guard hasCover || failure != nil else {
            return nil
        }
        return AnyView(
            VStack(alignment: .leading, spacing: 4) {
                coverControlLine(for: entity)
                if let failure {
                    Text(failure)
                        .font(.system(size: 10.5))
                        .foregroundStyle(palette.danger)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityLabel("\(entity.name) control failed: \(failure)")
                }
            }
            .padding(.leading, 26)
        )
    }

    private func entityIconName(for entity: DiscoveredEntity) -> String? {
        // The custom icon applies everywhere the entity appears; the menu-bar
        // "Show icon" toggle only affects the status item, never the row.
        let configuration = snapshot.menuBarDisplayConfiguration.itemConfiguration(for: entity.id)
        return configuration.customIconName ?? pearchHAEntityIconName(for: entity)
    }

    private func panelMenuBarVisibilityBinding(for id: EntityID) -> Binding<Bool> {
        Binding(
            get: {
                snapshot.menuBarDisplayConfiguration.isPromoted(id)
            },
            set: { isVisible in
                model.setMenuBarEntity(id, isVisible: isVisible)
            }
        )
    }

    private func panelEntityIconVisibilityBinding(for id: EntityID) -> Binding<Bool> {
        Binding(
            get: {
                snapshot.menuBarDisplayConfiguration.itemConfiguration(for: id).showsEntityIcon
            },
            set: { showsEntityIcon in
                model.setShowsEntityIcon(id, showsEntityIcon: showsEntityIcon)
            }
        )
    }

    private func panelMenuBarLabelBinding(for id: EntityID) -> Binding<Bool> {
        Binding(
            get: {
                snapshot.menuBarDisplayConfiguration.itemConfiguration(for: id).showsLabel
            },
            set: { showsLabel in
                model.setMenuBarShowsLabel(id, showsLabel: showsLabel)
            }
        )
    }

    private func panelMenuBarUnitBinding(for id: EntityID) -> Binding<Bool> {
        Binding(
            get: {
                snapshot.menuBarDisplayConfiguration.itemConfiguration(for: id).showsUnit
            },
            set: { showsUnit in
                model.setMenuBarShowsUnit(id, showsUnit: showsUnit)
            }
        )
    }

    private func entityControlHelp(for entity: DiscoveredEntity, control: PearchHAEntityControl, isOn: Bool) -> String {
        if snapshot.connectionState != .connected { return "Reconnect to Home Assistant to control this entity" }
        if snapshot.controlActionState.isRunning {
            return "Waiting for Home Assistant"
        }
        if let failure = control.failureMessage { return failure }
        return isOn ? "Turns \(entity.name) off" : "Turns \(entity.name) on"
    }

    private func customActionButton(_ action: EntityCustomAction) -> some View {
        Button {
            if action.requiresConfirmation {
                pendingCustomActionID = action.id
            } else {
                model.startCustomAction(action.id)
            }
        } label: {
            PearchHACircularIconLabel(
                icon: "play.fill",
                disabled: snapshot.controlActionState.isRunning(for: action.entityID)
            )
        }
        .buttonStyle(.borderless)
        .disabled(snapshot.controlActionState.isRunning)
        .help(customActionHelp(action))
        .accessibilityLabel(action.title)
        .accessibilityHint(customActionHelp(action))
    }

    private func customActionHelp(_ action: EntityCustomAction) -> String {
        if snapshot.controlActionState.isRunning(for: action.entityID) {
            return "Waiting for Home Assistant"
        }
        return action.requiresConfirmation ? "Asks before running" : "Runs saved Home Assistant service"
    }

    /// The quiet anchored footer. Shows a short problem message when present,
    /// otherwise the calm "updated" caption, plus the settings and quit controls.
    /// The manual refresh control is intentionally absent: values auto-update
    /// while the panel is open.
    private var footer: some View {
        DashboardFooter(
            connectionColor: connectionStatusColor,
            updatedText: footerUpdatedText,
            onSettings: { openSettings() },
            onQuit: { NSApplication.shared.terminate(nil) }
        )
        .onHover { isInside in
            if isInside {
                model.dismissHistoryPopover()
            }
        }
    }

    /// The footer caption. A real problem message always shows so failures are
    /// never hidden; the calm "updated" timestamp is suppressed when the user
    /// turns off the footer-timestamp display preference.
    private var footerUpdatedText: String {
        if snapshot.isLocalOnly { return LocalMacText.readOnly.localized() }
        if let problem = snapshot.problemDescription {
            return problem
        }
        return panelDisplayPreferences.showsFooterTimestamp ? snapshot.lastUpdateDescription : ""
    }

    private func entityValue(_ entity: DiscoveredEntity) -> FormattedEntityValue {
        model.formattedValue(for: entity)
    }

    /// The row's reserved history-preview column: a tiny micro chart (or bounded
    /// meter) drawn only from already-cached history, or a muted placeholder when
    /// nothing is cached yet.
    ///
    /// Percentage/bounded rows draw a ``MicroMeter``; numeric rows draw a
    /// ``MicroSparkline`` from cache; non-numeric series draw ``MicroActivityBars``.
    /// When nothing is cached and the row is not a percentage gauge, a muted
    /// ``TelemetryPreviewPlaceholder`` fills the same reserved footprint so the
    /// placeholder→chart swap never shifts the row. It never fetches on render or
    /// scroll.
    @ViewBuilder
    private func rowPreview(
        for entity: DiscoveredEntity,
        presentation: PearchHAEntityRowPresentation
    ) -> some View {
        PearchHAInlineHistoryPreview(
            model: model,
            entity: entity,
            presentation: presentation,
            value: entityValue(entity),
            palette: PearchHATheme.Dashboard.palette(colorScheme)
        )
    }

    /// The value readout: a ``StatusPill`` for on/off & open/closed, otherwise a
    /// monospaced value (with the dynamic glyph when the value carries one).
    @ViewBuilder
    private func rowValueOrPill(
        entity: DiscoveredEntity,
        value: FormattedEntityValue,
        presentation: PearchHAEntityRowPresentation
    ) -> some View {
        let palette = PearchHATheme.Dashboard.palette(colorScheme)
        if case let .statePill(isActive) = presentation, value.iconSymbolName == nil {
            StatusPill(
                value.text,
                color: isActive && value.status == .available ? palette.accentPrimary : palette.textSecondary,
                filled: isActive && value.status == .available,
                accessibilityLabel: value.text
            )
        } else {
            HStack(spacing: 6) {
                if let iconSymbolName = value.iconSymbolName {
                    Image(systemName: iconSymbolName)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(value.status == .available ? palette.textPrimary : palette.textTertiary)
                        .accessibilityHidden(true)
                }
                Text(value.text)
                    .font(.system(size: 14, weight: .semibold).monospacedDigit())
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .fixedSize(horizontal: false, vertical: false)
                    .foregroundStyle(value.status == .available ? rowValueColor(presentation) : palette.textTertiary)
                    .accessibilityHidden(true)
            }
        }
    }

    private func rowValueColor(_ presentation: PearchHAEntityRowPresentation) -> Color {
        let palette = PearchHATheme.Dashboard.palette(colorScheme)
        switch presentation {
        case let .gauge(gauge):
            return gauge.severity == .normal ? palette.textPrimary : palette.severityColor(gauge.severity)
        case let .value(severity):
            return severity == .normal ? palette.textPrimary : palette.severityColor(severity)
        case .statePill:
            return palette.textPrimary
        }
    }

    /// The single compact control a row exposes: a ``CompactSwitch`` for toggle
    /// entities or custom-action buttons. Cover controls drop onto the second
    /// line. Each control keeps its accessibility framing.
    @ViewBuilder
    private func rowControls(for entity: DiscoveredEntity) -> some View {
        if let control = snapshot.control(for: entity) {
            let isOn = model.requestedControlValue(for: entity.id, controlID: "state")?.controlString.map { $0 == "on" } ?? control.isOn
            CompactSwitch(
                isOn: isOn,
                isRunning: snapshot.controlActionState.isRunning,
                onChange: { isOn in model.startEntityControlToggle(entity.id, isOn: isOn) }
            )
            .disabled(snapshot.connectionState != .connected || entity.state == "unavailable" || entity.state == "unknown")
            .help(entityControlHelp(for: entity, control: control, isOn: isOn))
            .accessibilityLabel("\(isOn ? "Turn off" : "Turn on") \(entity.name)")
            .accessibilityHint(entityControlHelp(for: entity, control: control, isOn: isOn))
        }
        ForEach(model.customActions(for: entity), id: \.id.rawValue) { action in
            customActionButton(action)
        }
    }

    /// Cover movement commands and position share the direct numeric editor.
    @ViewBuilder
    private func coverControlLine(for entity: DiscoveredEntity) -> some View {
        if let control = snapshot.coverControl(for: entity) {
            PearchHAEntityControlInput(field: .coverPosition(control), entityName: entity.name, clock: model.clock,
                                      isInline: true, isRunning: control.isRunning,
                                      requestedValue: model.requestedControlValue(for: entity.id, controlID: "position") ?? model.requestedControlValue(for: entity.id, controlID: "state"),
                                      coverMode: model.coverControlMode(for: entity), runCoverCommand: { command in
                model.startCoverControl(entity.id, command: command)
            }) { value, _ in
                guard case let .number(position) = value else { return false }
                return model.startCoverPositionChange(entity.id, position: Int(position))
            }
            .disabled(snapshot.connectionState != .connected || snapshot.controlActionState.isRunning || entity.state == "unavailable")
        }
    }

    /// An optional muted subtitle for the row's name column.
    ///
    /// Shows the entity's unit (for example `°C`, `W`) when the value carries a
    /// numeric reading and the unit is not already embedded in the value text, so
    /// the right-aligned hero value can stay a bare number. Returns `nil` for
    /// state-pill rows and unit-less values so no empty line is drawn.
    private func rowSubtitle(for entity: DiscoveredEntity, value: FormattedEntityValue) -> String? {
        guard value.status == .available, Double(entity.state) != nil else {
            return nil
        }
        let unit = (entity.unit ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let valueAlreadyShowsAUnit = value.text.contains(unit) || value.text.contains { character in
            character.isLetter || character == "%" || character == "°" || character == "/"
        }
        guard !unit.isEmpty, !valueAlreadyShowsAUnit else {
            return nil
        }
        return unit
    }

}

/// Resolves the SF Symbol name representing an entity's domain or measured
/// quantity.
///
/// The choice is derived first from the Home Assistant domain, then falls back
/// to heuristics over the entity name and unit (temperature, humidity, battery,
/// power, air quality, contact/motion) before a neutral gauge default. Shared by
/// the drop-down panel and the Settings entity overview so both present the same
/// leading glyph for a given entity.
///
/// - Parameter entity: The discovered entity to represent.
/// - Returns: A valid SF Symbol name; never empty.
