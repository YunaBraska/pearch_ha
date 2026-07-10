import Foundation
import AppKit
import Combine
import SwiftUI
import UniformTypeIdentifiers
import PerchHACore
import PerchHASupport

@MainActor
private final class PerchHAPanelViewState: ObservableObject {
    @Published private(set) var snapshot: PerchHAPanelSnapshot
    @Published private(set) var oauthSignInState: PerchHAOAuthSignInState
    @Published private(set) var displayPreferences: PerchHADisplayPreferences

    init(model: PerchHAPanelModel) {
        self.snapshot = model.snapshot
        self.oauthSignInState = model.oauthSignInState
        self.displayPreferences = model.displayPreferences
        model.$snapshot
            .receive(on: RunLoop.main)
            .assign(to: &$snapshot)
        model.$oauthSignInState
            .receive(on: RunLoop.main)
            .assign(to: &$oauthSignInState)
        model.$displayPreferences
            .receive(on: RunLoop.main)
            .assign(to: &$displayPreferences)
    }
}

@MainActor
private final class PerchHAEntityHistoryRevisionObserver: ObservableObject {
    @Published private(set) var revision: UInt64 = 0

    private var cancellable: AnyCancellable?

    init(model: PerchHAPanelModel, entityID: EntityID) {
        self.cancellable = model.historyRevisionPublisher(for: entityID)
            .receive(on: RunLoop.main)
            .assign(to: \.revision, on: self)
    }
}

private struct PerchHAInlineHistoryPreview: View {
    let model: PerchHAPanelModel
    let entity: DiscoveredEntity
    let presentation: PerchHAEntityRowPresentation
    let value: FormattedEntityValue
    let palette: PerchHATheme.DashboardPalette
    @StateObject private var historyObserver: PerchHAEntityHistoryRevisionObserver

    init(
        model: PerchHAPanelModel,
        entity: DiscoveredEntity,
        presentation: PerchHAEntityRowPresentation,
        value: FormattedEntityValue,
        palette: PerchHATheme.DashboardPalette
    ) {
        self.model = model
        self.entity = entity
        self.presentation = presentation
        self.value = value
        self.palette = palette
        _historyObserver = StateObject(
            wrappedValue: PerchHAEntityHistoryRevisionObserver(model: model, entityID: entity.id)
        )
    }

    var body: some View {
        let _ = historyObserver.revision
        if case let .gauge(gauge) = presentation,
           gauge.style != .ring,
           PerchHADashboardPreview.meterShows(for: value.status) {
            MicroMeter(
                fraction: gauge.fraction,
                color: palette.severityColor(gauge.severity),
                trackColor: palette.meterTrack
            )
            .frame(width: 54, height: 6)
        } else if let preview = model.cachedInlinePreview(for: entity.id) {
            switch preview {
            case let .sparkline(geometry):
                MicroSparkline(geometry: geometry, color: palette.chartPrimary, muted: palette.chartMuted)
                    .frame(width: TelemetryRowMetrics.previewWidth, height: 22)
            case let .state(series):
                MicroActivityBars(series: series, muted: palette.chartMuted)
                    .frame(width: TelemetryRowMetrics.previewWidth, height: 7)
            case .placeholder:
                MicroDash(color: palette.chartMuted)
            }
        } else {
            Color.clear
        }
    }
}

@MainActor
private final class PerchHAHistoryPopoverController: ObservableObject {
    private static let popoverSize = NSSize(width: 308, height: 244)
    private weak var model: PerchHAPanelModel?
    private let onOpenEntitySettings: ((EntityID) -> Void)?
    private let popover: NSPopover
    private var snapshotCancellable: AnyCancellable?
    private var anchors: [EntityID: WeakAnchorView] = [:]
    private var currentEntityID: EntityID?
    private weak var currentAnchorView: NSView?
    private var hostingController: NSHostingController<PerchHAHistoryPopoverRootView>?
    private var clickOutsideMonitor: Any?

    init(model: PerchHAPanelModel, onOpenEntitySettings: ((EntityID) -> Void)?) {
        self.model = model
        self.onOpenEntitySettings = onOpenEntitySettings
        let popover = NSPopover()
        popover.behavior = .applicationDefined
        popover.animates = false
        self.popover = popover
        snapshotCancellable = model.$snapshot
            .receive(on: RunLoop.main)
            .sink { [weak self] snapshot in
                self?.update(with: snapshot)
            }
    }

    deinit {
        Task { @MainActor [popover] in
            if popover.isShown {
                popover.performClose(nil)
            }
        }
    }

    func register(anchorView: NSView, for entityID: EntityID) {
        anchors[entityID] = WeakAnchorView(view: anchorView)
        guard currentEntityID == entityID, let model else {
            return
        }
        update(with: model.snapshot)
    }

    func unregister(anchorView: NSView, for entityID: EntityID) {
        guard anchors[entityID]?.view === anchorView else {
            return
        }
        anchors[entityID] = nil
        if currentEntityID == entityID {
            dismiss()
        }
    }

    private func update(with snapshot: PerchHAPanelSnapshot) {
        pruneDeadAnchors()
        guard let model,
              let entityID = snapshot.historyPresentationEntityID,
              let anchorView = anchors[entityID]?.view,
              anchorView.window != nil,
              let entity = snapshot.rooms
                .flatMap(\.entities)
                .first(where: { $0.id == entityID })
        else {
            dismiss()
            return
        }

        if currentEntityID != entityID || hostingController == nil {
            let rootView = PerchHAHistoryPopoverRootView(
                model: model,
                entity: entity,
                onOpenEntitySettings: onOpenEntitySettings
            )
            let hostingController = NSHostingController(rootView: rootView)
            hostingController.view.layoutSubtreeIfNeeded()
            self.hostingController = hostingController
            popover.contentViewController = hostingController
            popover.contentSize = Self.popoverSize
            currentEntityID = entityID
        }

        let needsReanchor = currentAnchorView !== anchorView
        currentAnchorView = anchorView
        if popover.isShown, needsReanchor {
            popover.performClose(nil)
        }
        if !popover.isShown {
            popover.show(relativeTo: anchorView.bounds, of: anchorView, preferredEdge: .maxX)
            installClickOutsideMonitor()
        }
    }

    private func dismiss() {
        currentEntityID = nil
        currentAnchorView = nil
        hostingController = nil
        if popover.isShown {
            popover.performClose(nil)
        }
        removeClickOutsideMonitor()
    }

    private func pruneDeadAnchors() {
        anchors = anchors.filter { $0.value.view != nil }
    }

    private func installClickOutsideMonitor() {
        guard clickOutsideMonitor == nil else {
            return
        }
        clickOutsideMonitor = NSEvent.addLocalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]
        ) { [weak self] event in
            guard let self else {
                return event
            }
            guard popover.isShown else {
                removeClickOutsideMonitor()
                return event
            }
            if shouldKeepPopoverOpen(for: event) {
                return event
            }
            model?.dismissHistoryPopover()
            return event
        }
    }

    private func removeClickOutsideMonitor() {
        guard let clickOutsideMonitor else {
            return
        }
        NSEvent.removeMonitor(clickOutsideMonitor)
        self.clickOutsideMonitor = nil
    }

    private func shouldKeepPopoverOpen(for event: NSEvent) -> Bool {
        if let popoverWindow = popover.contentViewController?.view.window,
           event.window === popoverWindow {
            return true
        }
        guard let anchorView = currentAnchorView,
              let anchorWindow = anchorView.window,
              event.window === anchorWindow
        else {
            return false
        }
        let pointInAnchor = anchorView.convert(event.locationInWindow, from: nil)
        return anchorView.bounds.contains(pointInAnchor)
    }
}

private final class WeakAnchorView {
    weak var view: NSView?

    init(view: NSView?) {
        self.view = view
    }
}

@MainActor
private struct PerchHAHistoryPopoverAnchor: NSViewRepresentable {
    let entityID: EntityID
    let controller: PerchHAHistoryPopoverController

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        view.translatesAutoresizingMaskIntoConstraints = false
        view.wantsLayer = false
        controller.register(anchorView: view, for: entityID)
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        controller.register(anchorView: nsView, for: entityID)
    }

    static func dismantleNSView(_ nsView: NSView, coordinator: ()) {
        // `NSViewRepresentable` dismantle is static, so unregistration is
        // driven by the controller pruning dead weak references on the next
        // snapshot update. That keeps the anchor bookkeeping lightweight.
    }
}

private struct PerchHAHistoryPopoverRootView: View {
    @ObservedObject var model: PerchHAPanelModel
    let entity: DiscoveredEntity
    let onOpenEntitySettings: ((EntityID) -> Void)?

    var body: some View {
        PerchHAHistoryPopoverContent(
            entityID: entity.id,
            entityName: entity.name,
            valueText: model.formattedValue(for: entity).text,
            unit: entity.unit,
            state: model.snapshot.historyState,
            onOpenSettings: {
                onOpenEntitySettings?(entity.id)
            },
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
}

public struct PerchHAPanelView: View {
    private let model: PerchHAPanelModel
    private let accessibilityPreferencesOverride: PerchHAAccessibilityPreferences?
    private let onOpenSettings: (() -> Void)?
    private let onOpenEntitySettings: ((EntityID) -> Void)?
    @StateObject private var viewState: PerchHAPanelViewState
    @StateObject private var historyPopoverController: PerchHAHistoryPopoverController
    @State private var pendingCustomActionID: CustomActionID?
    @State private var expandedModuleIDs: Set<String> = []
    @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast
    @Environment(\.colorScheme) private var colorScheme

    public init(
        model: PerchHAPanelModel,
        accessibilityPreferencesOverride: PerchHAAccessibilityPreferences? = nil,
        onOpenSettings: (() -> Void)? = nil,
        onOpenEntitySettings: ((EntityID) -> Void)? = nil
    ) {
        self.model = model
        self.accessibilityPreferencesOverride = accessibilityPreferencesOverride
        self.onOpenSettings = onOpenSettings
        self.onOpenEntitySettings = onOpenEntitySettings
        _viewState = StateObject(wrappedValue: PerchHAPanelViewState(model: model))
        _historyPopoverController = StateObject(
            wrappedValue: PerchHAHistoryPopoverController(
                model: model,
                onOpenEntitySettings: onOpenEntitySettings
            )
        )
    }

    private func openSettings() {
        if let onOpenSettings {
            onOpenSettings()
        } else {
            model.toggleSettings()
        }
    }

    private var snapshot: PerchHAPanelSnapshot {
        viewState.snapshot
    }

    private var panelDisplayPreferences: PerchHADisplayPreferences {
        viewState.displayPreferences
    }

    private var oauthState: PerchHAOAuthSignInState {
        viewState.oauthSignInState
    }

    public var body: some View {
        let accessibility = Self.rootAccessibilityPresentation(
            snapshot: snapshot,
            preferences: accessibilityPreferences
        )
        let palette = PerchHATheme.Dashboard.palette(colorScheme)
        let shape = RoundedRectangle(cornerRadius: PerchHATheme.Dashboard.panelCornerRadius, style: .continuous)
        return VStack(alignment: .leading, spacing: 0) {
            if showsTopBar {
                topBar
                dashboardDivider
            }
            content
            dashboardDivider
            footer
        }
        .frame(width: 384, height: 468, alignment: .top)
        .environment(\.dashboardPalette, palette)
        .environment(\.dashboardRowDensity, panelDisplayPreferences.dashboardRowDensity)
        .background(
            dashboardBackground(palette)
        )
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
    }

    public static func rootAccessibilityPresentation(
        snapshot: PerchHAPanelSnapshot,
        preferences: PerchHAAccessibilityPreferences = PerchHAAccessibilityPreferences()
    ) -> PerchHAPanelRootAccessibilityPresentation {
        PerchHAPanelRootAccessibilityPresentation(
            panel: snapshot.accessibilityPresentation(preferences: preferences)
        )
    }

    public static func entityContextPresentation(
        snapshot: PerchHAPanelSnapshot,
        entityID: EntityID
    ) -> PerchHAPanelEntityContextPresentation {
        let configuration = snapshot.menuBarDisplayConfiguration.itemConfiguration(for: entityID)
        return PerchHAPanelEntityContextPresentation(
            isPromotedToMenuBar: snapshot.menuBarDisplayConfiguration.isPromoted(entityID),
            hasAverageLinks: !configuration.averageEntityIDs.isEmpty,
            showsEntityIcon: configuration.showsEntityIcon,
            showsLabel: configuration.showsLabel,
            showsUnit: configuration.showsUnit
        )
    }

    private var accessibilityPreferences: PerchHAAccessibilityPreferences {
        if let accessibilityPreferencesOverride {
            return accessibilityPreferencesOverride
        }
        return PerchHAAccessibilityPreferences(
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

    /// The appearance-aware base fill plus a thin translucent material, painted
    /// edge-to-edge so the popover reads as a designed instrument panel (graphite
    /// in dark, light translucent graphite in light) and never shows a transparent
    /// seam. The SwiftUI root clips the rounded corners and provides the shadow;
    /// the base fill keeps every edge opaque against the borderless window.
    private func dashboardBackground(_ palette: PerchHATheme.DashboardPalette) -> some View {
        palette.popoverBackground
            .overlay(Rectangle().fill(.ultraThinMaterial).opacity(0.5))
    }

    private var dashboardDivider: some View {
        Rectangle()
            .fill(PerchHATheme.Dashboard.palette(colorScheme).separator)
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
        let palette = PerchHATheme.Dashboard.palette(colorScheme)
        return HStack(spacing: PerchHASpacing.sm - 2) {
            Circle()
                .fill(connectionStatusColor)
                .frame(width: 7, height: 7)
                .accessibilityHidden(true)
            Text("PearchHA")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(palette.textPrimary)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, PerchHASpacing.md)
        .padding(.top, PerchHASpacing.md)
        .padding(.bottom, PerchHASpacing.sm)
        .onHover { isInside in
            if isInside {
                model.dismissHistoryPopover()
            }
        }
    }

    private var connectionStatusColor: Color {
        PerchHATheme.Dashboard.palette(colorScheme).connectionColor(snapshot.connectionState)
    }

    @ViewBuilder
    private var content: some View {
        switch PerchHAStateViewKind.forContent(phase: snapshot.phase) {
        case .loading:
            loadingState
        case .connectionForm:
            connectionForm
        case .empty:
            connectedEmptyState
        case .data:
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 18) {
                    ForEach(visibleModules, id: \.id.rawValue) { room in
                        moduleBlock(room)
                    }
                }
                .padding(.top, 4)
                .padding(.bottom, 14)
            }
            .onAppear {
                syncWarmedEntityIDs()
            }
            .onChange(of: warmedEntityIDs) { ids in
                syncWarmedEntityIDs(ids)
            }
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

    private var warmedEntityIDs: [EntityID] {
        visibleModules.flatMap { room in
            let isExpanded = expandedModuleIDs.contains(room.id.rawValue)
            let visibleEntities = (isExpanded || curatedRowCap == nil)
                ? room.entities
                : Array(room.entities.prefix(curatedRowCap ?? room.entities.count))
            return visibleEntities.map(\.id)
        }
    }

    private var loadingState: some View {
        PerchHALoadingState(
            title: "Connecting…",
            message: "Reaching your Home Assistant and loading values."
        )
    }

    private var connectedEmptyState: some View {
        PerchHAEmptyState(
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
            PerchHALoadingState(
                title: "Signing in…",
                message: "Approve access to Home Assistant in your browser."
            )
        } else {
            PerchHAEmptyState(
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
        return ModuleBlock(title: room.name) {
            ForEach(Array(visibleEntities.enumerated()), id: \.element.id.rawValue) { index, entity in
                entityRowBlock(entity, showsSeparator: index < visibleEntities.count - 1)
            }
            if let cap, total > cap {
                TelemetryRowSeparator()
                moreAffordance(roomID: room.id.rawValue, isExpanded: isExpanded, hiddenCount: hiddenCount)
            }
        }
    }

    private func entityRowBlock(_ entity: DiscoveredEntity, showsSeparator: Bool) -> some View {
        let value = entityValue(entity)
        let contextPresentation = Self.entityContextPresentation(snapshot: snapshot, entityID: entity.id)
        return VStack(spacing: 0) {
            telemetryRow(entity)
            if showsSeparator {
                TelemetryRowSeparator()
            }
        }
        .contentShape(Rectangle())
        .background(
            PerchHAHistoryPopoverAnchor(
                entityID: entity.id,
                controller: historyPopoverController
            )
        )
        .onTapGesture {
            if snapshot.historyPresentationEntityID == entity.id {
                model.dismissHistoryPopover()
            } else {
                model.presentHistoryDetail(entity.id)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(entity.name), \(value.text)")
        .accessibilityAction(named: "Show history") {
            model.presentHistoryDetail(entity.id)
        }
        .accessibilityAction(named: "Hide history") {
            model.dismissHistoryPopover()
        }
        .contextMenu {
            entityContextMenu(for: entity, contextPresentation: contextPresentation)
        }
    }

    /// A quiet "More" / "Less" affordance that expands or collapses a module in
    /// place, keeping overflow rows reachable without a database dump.
    private func moreAffordance(roomID: String, isExpanded: Bool, hiddenCount: Int) -> some View {
        let palette = PerchHATheme.Dashboard.palette(colorScheme)
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
        // A row with a real switch reads as `[icon] name ………… [switch]`: the
        // switch alone communicates the on/off state, so the redundant ON/OFF
        // pill and the meaningless meter band are dropped. Mixing those in was
        // what made the column grid feel random next to numeric rows.
        let hasToggle = snapshot.control(for: entity) != nil
        return TelemetryRow(
            icon: entityIconName(for: entity),
            iconActive: value.status == .available,
            label: entity.name,
            labelAccessories: rowLabelAccessories(contextPresentation: contextPresentation),
            subtitle: rowSubtitle(for: entity, value: value),
            secondLine: rowSecondLine(for: entity),
            preview: {
                if !hasToggle {
                    rowPreview(for: entity, presentation: presentation)
                }
            },
            value: {
                if !hasToggle {
                    rowValueOrPill(entity: entity, value: value, presentation: presentation)
                }
            },
            control: { rowControls(for: entity) }
        )
    }

    private func rowLabelAccessories(
        contextPresentation: PerchHAPanelEntityContextPresentation
    ) -> [TelemetryRowLabelAccessory] {
        let palette = PerchHATheme.Dashboard.palette(colorScheme)
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
        contextPresentation: PerchHAPanelEntityContextPresentation
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
            ForEach(PerchHAEntityIconCatalog.sections, id: \.title) { section in
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
        if contextPresentation.isPromotedToMenuBar {
            Divider()
            Toggle("Show Icon", isOn: panelEntityIconVisibilityBinding(for: entity.id))
            Toggle("Show Label", isOn: panelMenuBarLabelBinding(for: entity.id))
            Toggle("Show Unit", isOn: panelMenuBarUnitBinding(for: entity.id))
        }
    }

    private func makeEntityContextMenu(
        for entity: DiscoveredEntity,
        contextPresentation: PerchHAPanelEntityContextPresentation
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
        for section in PerchHAEntityIconCatalog.sections {
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
        let item = NSMenuItem(title: title, action: #selector(PerchHAMenuActionTarget.performAction(_:)), keyEquivalent: "")
        let target = PerchHAMenuActionTarget(action: action)
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
        let palette = PerchHATheme.Dashboard.palette(colorScheme)
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

    /// Reports the rows currently rendered in the panel so background history
    /// warming happens from layout state, not per-row scroll churn.
    private func syncWarmedEntityIDs(_ ids: [EntityID]? = nil) {
        model.updateVisibleEntities(ids ?? warmedEntityIDs)
    }

    private func entityIconName(for entity: DiscoveredEntity) -> String? {
        // The custom icon applies everywhere the entity appears; the menu-bar
        // "Show icon" toggle only affects the status item, never the row.
        let configuration = snapshot.menuBarDisplayConfiguration.itemConfiguration(for: entity.id)
        return configuration.customIconName ?? perchHAEntityIconName(for: entity)
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

    private func entityControlHelp(for entity: DiscoveredEntity, control: PerchHAEntityControl) -> String {
        if control.isRunning {
            return "Waiting for Home Assistant"
        }
        return control.isOn ? "Turns \(entity.name) off" : "Turns \(entity.name) on"
    }

    private func customActionButton(_ action: EntityCustomAction) -> some View {
        Button {
            if action.requiresConfirmation {
                pendingCustomActionID = action.id
            } else {
                model.startCustomAction(action.id)
            }
        } label: {
            PerchHACircularIconLabel(
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

    private func coverButtons(for entity: DiscoveredEntity, control: PerchHACoverControl) -> some View {
        HStack(spacing: 4) {
            coverButton(
                icon: "arrow.up.to.line",
                label: "Open \(entity.name)",
                help: coverControlHelp(for: entity, control: control, command: .open),
                disabled: control.isRunning
            ) {
                model.startCoverControl(entity.id, command: .open)
            }
            coverButton(
                icon: "stop.fill",
                label: "Stop \(entity.name)",
                help: coverControlHelp(for: entity, control: control, command: .stop),
                disabled: control.isRunning
            ) {
                model.startCoverControl(entity.id, command: .stop)
            }
            coverButton(
                icon: "arrow.down.to.line",
                label: "Close \(entity.name)",
                help: coverControlHelp(for: entity, control: control, command: .close),
                disabled: control.isRunning
            ) {
                model.startCoverControl(entity.id, command: .close)
            }
        }
    }

    private func coverButton(
        icon: String,
        label: String,
        help: String,
        disabled: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            PerchHACircularIconLabel(icon: icon, disabled: disabled)
        }
        .buttonStyle(.borderless)
        .disabled(disabled)
        .help(help)
        .accessibilityLabel(label)
        .accessibilityHint(help)
    }

    private func coverControlHelp(
        for entity: DiscoveredEntity,
        control: PerchHACoverControl,
        command: PerchHACoverCommand
    ) -> String {
        if control.isRunning {
            return "Waiting for Home Assistant"
        }
        switch command {
        case .open:
            return "Opens \(entity.name)"
        case .close:
            return "Closes \(entity.name)"
        case .stop:
            return "Stops \(entity.name)"
        case let .setPosition(position):
            return "Sets \(entity.name) to \(position) percent"
        }
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
        presentation: PerchHAEntityRowPresentation
    ) -> some View {
        PerchHAInlineHistoryPreview(
            model: model,
            entity: entity,
            presentation: presentation,
            value: entityValue(entity),
            palette: PerchHATheme.Dashboard.palette(colorScheme)
        )
    }

    /// The value readout: a ``StatusPill`` for on/off & open/closed, otherwise a
    /// monospaced value (with the dynamic glyph when the value carries one).
    @ViewBuilder
    private func rowValueOrPill(
        entity: DiscoveredEntity,
        value: FormattedEntityValue,
        presentation: PerchHAEntityRowPresentation
    ) -> some View {
        let palette = PerchHATheme.Dashboard.palette(colorScheme)
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
                    .fixedSize(horizontal: true, vertical: false)
                    .foregroundStyle(value.status == .available ? rowValueColor(presentation) : palette.textTertiary)
                    .accessibilityHidden(true)
            }
        }
    }

    private func rowValueColor(_ presentation: PerchHAEntityRowPresentation) -> Color {
        let palette = PerchHATheme.Dashboard.palette(colorScheme)
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
            CompactSwitch(
                isOn: control.isOn,
                isRunning: control.isRunning,
                onChange: { isOn in model.startEntityControlToggle(entity.id, isOn: isOn) }
            )
            .help(entityControlHelp(for: entity, control: control))
            .accessibilityLabel("\(control.isOn ? "Turn off" : "Turn on") \(entity.name)")
            .accessibilityHint(entityControlHelp(for: entity, control: control))
        }
        ForEach(model.customActions(for: entity), id: \.id.rawValue) { action in
            customActionButton(action)
        }
    }

    /// The cover controls on the row's compact second line: the up/stop/down
    /// buttons (when enabled) and the position slider (when enabled). Kept off the
    /// top line so the cover row reads as a normal named row whose top line is
    /// `[icon] name [band/sparkline] [state]`. Returns nothing when neither the
    /// buttons nor the slider are configured.
    @ViewBuilder
    private func coverControlLine(for entity: DiscoveredEntity) -> some View {
        if let coverControl = snapshot.coverControl(for: entity) {
            let mode = model.coverControlMode(for: entity)
            HStack(spacing: 8) {
                if mode.showsButtons {
                    coverButtons(for: entity, control: coverControl)
                }
                if mode.showsSlider, let position = coverControl.position {
                    PerchHACoverPositionSlider(
                        position: position,
                        disabled: coverControl.isRunning,
                        accessibilityName: "\(entity.name) position"
                    ) { position in
                        model.startCoverPositionChange(entity.id, position: position)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
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
