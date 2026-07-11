import Foundation
import AppKit
import SwiftUI
import UniformTypeIdentifiers
import PerchHACore
import PerchHASupport


/// Dedicated, resizable Settings window content for PerchHA.
///
/// Organized as a `TabView` with three tabs: Connection, Entities, and About.
/// Per-entity display and action configuration stays inline inside the
/// Entities tree, matching the documented UX. This view hosts the settings-only
/// controls relocated out of the cramped menu-bar panel.
public struct PerchHASettingsView: View {
    /// Selectable sections of the Settings window, shown in the sidebar rail in
    /// declaration order.
    public enum Tab: Hashable, Sendable, CaseIterable {
        case general
        case connection
        case entities
        case appearance
        case diagnostics
        case privacy
        case about

        /// The sidebar rail label.
        var title: String {
            switch self {
            case .general: "General"
            case .connection: "Connection"
            case .entities: "Entities"
            case .appearance: "Appearance"
            case .diagnostics: "Diagnostics"
            case .privacy: "Privacy"
            case .about: "About"
            }
        }

        /// The sidebar rail SF Symbol.
        var systemImage: String {
            switch self {
            case .general: "gearshape"
            case .connection: "network"
            case .entities: "square.grid.2x2"
            case .appearance: "paintbrush"
            case .diagnostics: "stethoscope"
            case .privacy: "lock"
            case .about: "info.circle"
            }
        }
    }

    private let model: PerchHAPanelModel
    @StateObject private var viewState: PerchHASettingsViewState
    private let accessibilityPreferencesOverride: PerchHAAccessibilityPreferences?
    private let displayPreferencesProvider: () -> PerchHADisplayPreferences
    private let displayPreferencesSink: (PerchHADisplayPreferences) -> Void
    private let launchAtLoginProvider: () -> Bool
    private let launchAtLoginSink: (Bool) -> Bool
    @State private var draggedSelectionItem: SelectionDragItem?
    @State private var selectedTab: Tab
    /// The single entity whose inspector is open in the Entities tab, or `nil`
    /// when every row is collapsed. Only one inspector is open at a time.
    @State private var inspectedEntityID: EntityID?
    /// A one-shot scroll target consumed when Settings was opened for a
    /// specific entity from outside the Entities tab. Once revealed, the list
    /// stays under the user's control instead of snapping back on later view
    /// updates or manual scrolling.
    @State private var pendingRevealEntityID: EntityID?
    /// Room ids (``RoomID/rawValue``) whose entity rows are collapsed in the
    /// Entities tab. Rooms default to expanded, so a room is hidden only when it
    /// appears here. A live search or an open inspector force the affected room
    /// visible regardless of this set, without mutating it, so clearing the
    /// search restores the prior collapsed state.
    /// Rooms the user has explicitly expanded in the Entities tab. Empty by
    /// default, so every room starts collapsed.
    @State private var expandedRooms: Set<String> = []
    @State private var displayPreferences: PerchHADisplayPreferences
    @State private var pendingDisplayPreferencesSave: Task<Void, Never>?
    /// View-local echo of the Entities search field; pushed to the model after
    /// a short debounce so typing never rebuilds the whole app state per key.
    @State private var entitySearchText: String = ""
    @State private var searchDebounceTask: Task<Void, Never>?
    @State private var averagePickerEntityID: EntityID?
    @State private var averagePickerSearchText: String = ""
    @State private var launchAtLogin: Bool
    @State private var launchAtLoginPermissionDenied = false
    @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast
    @Environment(\.colorScheme) private var colorScheme

    /// Creates the Settings window content.
    ///
    /// - Parameters:
    ///   - model: The shared panel model driving every binding and persistence
    ///     side effect.
    ///   - accessibilityPreferencesOverride: Optional fixed accessibility
    ///     preferences. When `nil`, preferences are read from the environment.
    ///   - initialTab: The tab shown when the window first appears.
    ///   - initiallyExpandedEntityIDs: Entity rows in the Entities tab whose
    ///     per-entity configuration should be disclosed (expanded) on first
    ///     render. Defaults to empty, so every row starts collapsed. Used by
    ///     snapshot and test render paths to reveal the configuration controls
    ///     of the entity under inspection.
    public init(
        model: PerchHAPanelModel,
        accessibilityPreferencesOverride: PerchHAAccessibilityPreferences? = nil,
        initialTab: Tab = .connection,
        initiallyExpandedEntityIDs: Set<EntityID> = [],
        displayPreferencesProvider: @escaping () -> PerchHADisplayPreferences = { .defaults },
        displayPreferencesSink: @escaping (PerchHADisplayPreferences) -> Void = { _ in },
        launchAtLoginProvider: @escaping () -> Bool = { false },
        launchAtLoginSink: @escaping (Bool) -> Bool = { _ in false }
    ) {
        self.model = model
        _viewState = StateObject(wrappedValue: PerchHASettingsViewState(model: model))
        self.accessibilityPreferencesOverride = accessibilityPreferencesOverride
        self.displayPreferencesProvider = displayPreferencesProvider
        self.displayPreferencesSink = displayPreferencesSink
        self.launchAtLoginProvider = launchAtLoginProvider
        self.launchAtLoginSink = launchAtLoginSink
        _selectedTab = State(initialValue: initialTab)
        // Only one entity inspector is open at a time; seed it from the first
        // requested expansion (used by snapshot/test render paths).
        let initiallyInspectedEntityID = initiallyExpandedEntityIDs.first
        _inspectedEntityID = State(initialValue: initiallyInspectedEntityID)
        _pendingRevealEntityID = State(initialValue: initiallyInspectedEntityID)
        _displayPreferences = State(initialValue: displayPreferencesProvider())
        _launchAtLogin = State(initialValue: launchAtLoginProvider())
    }

    private var snapshot: PerchHAPanelSnapshot {
        viewState.snapshot
    }

    private var settingsTree: [SelectableRoom] {
        viewState.settingsSelectionTree
    }

    private var oauthState: PerchHAOAuthSignInState {
        viewState.oauthSignInState
    }

    private var releaseState: PerchHAReleaseUpdateState {
        viewState.releaseUpdateState
    }

    private var retryState: PerchHARetryBackoffState {
        viewState.retryBackoffState
    }

    private var diagnosticsEvents: [PerchHADiagnosticEvent] {
        viewState.diagnosticEvents
    }

    public var body: some View {
        let accessibility = PerchHAPanelView.rootAccessibilityPresentation(
            snapshot: snapshot,
            preferences: accessibilityPreferences
        )
        let palette = PerchHATheme.Dashboard.palette(colorScheme)
        return HStack(spacing: 0) {
            sidebarRail
            Rectangle()
                .fill(palette.separatorSubtle)
                .frame(width: 1)
                .accessibilityHidden(true)
            detailContent(for: selectedTab)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .background(palette.surfaceRoot.ignoresSafeArea())
        }
        .environment(\.dashboardPalette, palette)
        .frame(minWidth: 660, minHeight: 560)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .tint(PerchHATheme.accent)
        .contrast(accessibility.contrastPolicy == .increased ? 1.12 : 1)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(accessibility.label)
        .transaction { transaction in
            if accessibility.motionPolicy == .reduced {
                transaction.animation = nil
            }
        }
        .onAppear {
            viewState.setActiveTab(selectedTab)
        }
        .onChange(of: selectedTab) { tab in
            viewState.setActiveTab(tab)
        }
        .onDisappear {
            flushPendingDisplayPreferencesSave()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSMenu.didBeginTrackingNotification)) { _ in
            model.beginTransientUITracking()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSMenu.didEndTrackingNotification)) { _ in
            model.endTransientUITracking()
        }
    }

    /// The deterministic left sidebar rail: a fixed-width vertical stack of one
    /// selectable row per ``Tab`` case, in declaration order. Unlike
    /// `NavigationSplitView`, this plain `HStack` rail always renders and never
    /// auto-collapses in the fixed-size Settings window. Each row is a focusable
    /// `Button` carrying a spoken accessibility name; the selected row is
    /// highlighted with the palette accent (filled rounded background, accent
    /// text) and marked with the selected trait. The rail sits on the palette's
    /// elevated surface so it reads as a rail in both light and dark.
    private var sidebarRail: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 2) {
                ForEach(Tab.allCases, id: \.self) { tab in
                    sidebarRow(tab)
                }
            }
            .padding(.horizontal, PerchHASpacing.sm)
            .padding(.vertical, PerchHASpacing.md)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(width: 198)
        .frame(maxHeight: .infinity)
        .background(railBackground.ignoresSafeArea())
        .accessibilityLabel("Settings sections")
    }

    /// A single selectable rail row: SF Symbol + label in a full-width tappable
    /// `Button`. The selected row fills with the accent and uses accent text;
    /// unselected rows use secondary text.
    private func sidebarRow(_ tab: Tab) -> some View {
        let palette = PerchHATheme.Dashboard.palette(colorScheme)
        let isSelected = selectedTab == tab
        return Button {
            selectedTab = tab
        } label: {
            HStack(spacing: PerchHASpacing.sm) {
                Image(systemName: tab.systemImage)
                    .font(.system(size: 13, weight: .medium))
                    .frame(width: 20, alignment: .center)
                    .foregroundStyle(isSelected ? palette.accentPrimary : palette.textSecondary)
                Text(tab.title)
                    .font(.system(size: 13, weight: isSelected ? .semibold : .regular))
                    .lineLimit(1)
                    .foregroundStyle(isSelected ? palette.textPrimary : palette.textSecondary)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, PerchHASpacing.sm)
            .padding(.vertical, PerchHASpacing.sm - 1)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: PerchHACornerRadius.control, style: .continuous)
                    .fill(isSelected ? palette.accentPrimary.opacity(colorScheme == .dark ? 0.22 : 0.14) : Color.clear)
            )
            .overlay(alignment: .leading) {
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(isSelected ? palette.accentPrimary : Color.clear)
                    .frame(width: 3, height: 16)
                    .offset(x: -PerchHASpacing.xs)
            }
            .contentShape(RoundedRectangle(cornerRadius: PerchHACornerRadius.control, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(tab.title)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : [.isButton])
    }

    /// The rail's surface fill, resolved against the current appearance so it
    /// reads as a distinct rail that matches the dashboard panel in light/dark.
    private var railBackground: Color {
        PerchHATheme.Dashboard.palette(colorScheme).surfacePanel
    }

    /// Routes a section to its detail content.
    @ViewBuilder
    private func detailContent(for tab: Tab) -> some View {
        switch tab {
        case .general: generalTab
        case .connection: connectionTab
        case .entities: entitiesTab
        case .appearance: appearanceTab
        case .diagnostics: diagnosticsTab
        case .privacy: privacyTab
        case .about: aboutTab
        }
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

    /// Renders a single tab's content (without the surrounding `TabView` chrome)
    /// on an opaque full-bleed background. Used to capture deterministic settings
    /// snapshots that avoid the platform tab-strip's transparent regions.
    @ViewBuilder
    public func tabContentForSnapshot(_ tab: Tab) -> some View {
        let content: AnyView = switch tab {
        case .general: AnyView(generalTab)
        case .connection: AnyView(connectionTab)
        case .entities: AnyView(entitiesTab)
        case .appearance: AnyView(appearanceTab)
        case .diagnostics: AnyView(diagnosticsTab)
        case .privacy: AnyView(privacyTab)
        case .about: AnyView(aboutTab)
        }
        content
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(PerchHATheme.Dashboard.palette(colorScheme).surfaceRoot.ignoresSafeArea())
            .environment(\.dashboardPalette, PerchHATheme.Dashboard.palette(colorScheme))
            .contrast(accessibilityPreferences.contrastPolicy == .increased ? 1.12 : 1)
    }

    private var connectionTab: some View {
        settingsPage(title: "Connection", systemImage: Tab.connection.systemImage) {
            settingsCard {
                settingsSection(title: "Status", systemImage: "antenna.radiowaves.left.and.right") {
                    connectionStatusContent
                }
            }
            settingsCard {
                settingsSection(title: "Addresses & access", systemImage: "network") {
                    PerchHAConnectionFormFields(
                        model: model,
                        snapshot: snapshot,
                        oauthSignInState: oauthState
                    )
                        .textFieldStyle(.roundedBorder)
                }
            }
        }
    }

    /// The connection status card content: a status pill, the connected host
    /// (when known), and the last successful update — all derived from the live
    /// snapshot. No stored secret is ever surfaced.
    private var connectionStatusContent: some View {
        let status = connectionDiagnostic
        let host = connectionSummaryHost
        return VStack(alignment: .leading, spacing: PerchHASpacing.sm) {
            HStack(spacing: 8) {
                StatusPill(
                    status.label,
                    systemImage: status.systemImage,
                    color: status.color,
                    accessibilityLabel: "Connection \(status.label)"
                )
                Spacer(minLength: 0)
            }
            if let host {
                settingsControlRow("Server") {
                    Text(host)
                        .font(PerchHATypography.bodyValue())
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
            settingsControlRow("Last update") {
                Text(snapshot.lastUpdateDescription)
                    .font(PerchHATypography.bodyValue())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// The connected server host shown in the Connection status card, derived
    /// from the stored connection URL. Never exposes the access token.
    private var connectionSummaryHost: String? {
        let urlString = snapshot.connectionForm.urlString
        if let host = URL(string: urlString)?.host, !host.isEmpty {
            return host
        }
        let trimmed = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    /// A page scaffold shared by every section: a leading-aligned scroll view
    /// hosting a section title and a vertical stack of grouped cards on the
    /// window background, with consistent design-token insets.
    @ViewBuilder
    private func settingsPage<Content: View>(
        title: String,
        systemImage: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        let palette = PerchHATheme.Dashboard.palette(colorScheme)
        ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: PerchHASpacing.md + 2) {
                Text(title)
                    .font(.system(size: 19, weight: .semibold))
                    .foregroundStyle(palette.textPrimary)
                    .accessibilityAddTraits(.isHeader)
                content()
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, PerchHASpacing.lg)
            .padding(.horizontal, PerchHASpacing.lg + 2)
        }
        .toggleStyle(PerchHASwitchToggleStyle())
        .tint(PerchHATheme.accent)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    /// A grouped settings card styled with the dashboard palette: an elevated
    /// surface fill with a subtle hairline border and consistent interior
    /// padding, so settings share the dashboard's panel language and no raw
    /// ungrouped form rows are drawn anywhere.
    private func settingsCard<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        let palette = PerchHATheme.Dashboard.palette(colorScheme)
        return VStack(alignment: .leading, spacing: PerchHASpacing.md) {
            content()
        }
        .padding(PerchHASpacing.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: PerchHACornerRadius.card, style: .continuous)
                .fill(palette.surfacePanel)
        )
        .overlay(
            RoundedRectangle(cornerRadius: PerchHACornerRadius.card, style: .continuous)
                .strokeBorder(palette.borderSubtle, lineWidth: 1)
        )
    }

    /// A compact card variant used for inline inspectors and nested groups, with
    /// the slightly more elevated surface so it reads as sitting above a card.
    private func settingsInsetGroup<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        let palette = PerchHATheme.Dashboard.palette(colorScheme)
        return VStack(alignment: .leading, spacing: PerchHASpacing.sm) {
            content()
        }
        .padding(PerchHASpacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: PerchHACornerRadius.control, style: .continuous)
                .fill(palette.surfacePanelElevated)
        )
    }

    // MARK: General

    /// General settings: the genuinely-global preferences that do not belong to a
    /// more specific section. Appearance (theme/accent) lives in the Appearance
    /// section, so it is intentionally not duplicated here.
    private var generalTab: some View {
        settingsPage(title: "General", systemImage: Tab.general.systemImage) {
            settingsCard {
                settingsSection(title: "Startup", systemImage: "power") {
                    VStack(alignment: .leading, spacing: PerchHASpacing.sm - 2) {
                        Toggle("Launch at login", isOn: launchAtLoginBinding)
                            .fixedSize()
                            .accessibilityLabel("Launch PearchHA at login")
                        Text("Start PearchHA automatically when you sign in to this Mac.")
                            .font(PerchHATypography.caption().weight(.regular))
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                        if launchAtLoginPermissionDenied {
                            PerchHAPermissionState(
                                title: "Couldn't enable launch at login",
                                message: "Open System Settings > General > Login Items and allow PearchHA."
                            )
                        }
                    }
                }
            }
            settingsCard {
                settingsSection(title: "Keyboard", systemImage: "keyboard") {
                    VStack(alignment: .leading, spacing: PerchHASpacing.sm) {
                        shortcutRow(label: "Open settings", keys: "⌘ ,")
                        settingsSectionDivider
                        shortcutRow(label: "Quit PearchHA", keys: "⌘ Q")
                        Text("These shortcuts are built in and cannot be changed.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
    }

    /// A read-only row pairing a shortcut description with its key combination,
    /// shown as a calm keycap so it reads as a fact rather than an editable
    /// control (no editable shortcut binding exists today).
    private func shortcutRow(label: String, keys: String) -> some View {
        let palette = PerchHATheme.Dashboard.palette(colorScheme)
        return HStack(spacing: PerchHASpacing.sm) {
            Text(label)
                .foregroundStyle(palette.textPrimary)
            Spacer(minLength: 8)
            Text(keys)
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(palette.textSecondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(palette.surfaceControl)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .strokeBorder(palette.borderSubtle, lineWidth: 1)
                )
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(label), shortcut \(keys)")
    }

    // MARK: Appearance

    /// Appearance: the live preview plus the theme/accent controls, which share
    /// their bindings (and persistence) with the General section, and a reset to
    /// the shipped display-preference defaults.
    private var appearanceTab: some View {
        settingsPage(title: "Appearance", systemImage: Tab.appearance.systemImage) {
            settingsCard {
                settingsSection(title: "Preview", systemImage: "eye") {
                    VStack(alignment: .leading, spacing: PerchHASpacing.md) {
                        PerchHAAppearancePreview(preferences: displayPreferences)
                        appearanceDashboardSample
                    }
                }
            }
            settingsCard {
                settingsSection(title: "Theme & accent", systemImage: "paintbrush") {
                    VStack(alignment: .leading, spacing: 10) {
                        settingsControlRow("Theme") {
                            themeModePicker
                        }
                        settingsControlRow("Accent") {
                            accentMenuPicker
                        }
                        accentSwatchPreview
                    }
                }
            }
            settingsCard {
                settingsSection(title: "Menu bar", systemImage: "menubar.rectangle") {
                    VStack(alignment: .leading, spacing: 10) {
                        settingsControlRow("Style") {
                            Picker("Menu bar style", selection: menuBarAppearanceBinding) {
                                ForEach(PerchHAMenuBarAppearance.allCases, id: \.rawValue) { appearance in
                                    Text(appearance.displayName).tag(appearance)
                                }
                            }
                            .pickerStyle(.segmented)
                            .labelsHidden()
                            .fixedSize()
                            .accessibilityLabel("Global menu bar style")
                        }
                        Text("The default look for menu-bar values. Individual values can override this in Entities.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                        Toggle("Keep a stable width", isOn: stableMenuBarWidthBinding)
                            .fixedSize()
                            .accessibilityLabel("Keep a stable menu bar width")
                        Text("Uses monospaced digits so the value does not shift as it changes.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            settingsCard {
                settingsSection(title: "Dashboard", systemImage: "rectangle.grid.1x2") {
                    VStack(alignment: .leading, spacing: PerchHASpacing.sm + 2) {
                        settingsControlRow("Row density") {
                            Picker("Row density", selection: rowDensityBinding) {
                                ForEach(PerchHADashboardRowDensity.allCases, id: \.rawValue) { density in
                                    Text(density.displayName).tag(density)
                                }
                            }
                            .pickerStyle(.segmented)
                            .labelsHidden()
                            .fixedSize()
                            .accessibilityLabel("Dashboard row density")
                        }
                        settingsControlRow("Default history range") {
                            Picker("Default history range", selection: defaultHistoryRangeBinding) {
                                ForEach(HistoryRange.uiSelectable, id: \.rawValue) { range in
                                    Text(range.displayName).tag(range)
                                }
                            }
                            .pickerStyle(.segmented)
                            .labelsHidden()
                            .fixedSize()
                            .accessibilityLabel("Default history range")
                        }
                        Text("Used for inline charts and the history popover unless a value has its own range.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                        settingsControlRow("Rows per room") {
                            SettingsIntegerField(
                                placeholder: "6",
                                value: displayPreferences.dashboardRoomRowLimit,
                                onCommit: { limit in
                                    updateDisplayPreferences(displayPreferences.with(dashboardRoomRowLimit: limit))
                                }
                            )
                            .frame(width: 56)
                            .accessibilityLabel("Rows shown per room before the more affordance")
                        }
                        Text("Rows shown per room before \u{201C}x more\u{201D}. A negative number shows every row.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                        Toggle("Show updated timestamp in the footer", isOn: footerTimestampBinding)
                            .fixedSize()
                            .accessibilityLabel("Show the dashboard footer updated timestamp")
                    }
                }
            }
            settingsCard {
                settingsSection(title: "Reset", systemImage: "arrow.counterclockwise") {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Restore the display preferences (menu-bar appearance, theme, and accent) to their defaults. Your connection and entities are not changed.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                        Button {
                            updateDisplayPreferences(.defaults)
                        } label: {
                            Label("Reset display preferences", systemImage: "arrow.counterclockwise")
                                .labelStyle(.titleAndIcon)
                        }
                        .buttonStyle(PerchHAIconButtonStyle())
                        .disabled(displayPreferences == .defaults)
                        .help("Reset menu-bar appearance, theme, and accent to defaults")
                        .accessibilityLabel("Reset display preferences to defaults")
                    }
                }
            }
        }
    }

    /// A sample dashboard telemetry row rendered on the dashboard surface using
    /// the currently-chosen accent and density, so the Appearance preview shows
    /// both a menu-bar item (from ``PerchHAAppearancePreview``) and a real
    /// dashboard row reflecting the live theme/accent.
    private var appearanceDashboardSample: some View {
        let palette = PerchHATheme.Dashboard.palette(colorScheme)
        let accent = color(for: displayPreferences.accentColor)
        return VStack(alignment: .leading, spacing: 4) {
            Text("Dashboard row")
                .font(PerchHATypography.caption())
                .foregroundStyle(palette.textTertiary)
            TelemetryRow(
                icon: "thermometer.medium",
                iconActive: true,
                label: "Living room",
                subtitle: "Temperature",
                preview: {
                    MicroMeter(fraction: 0.62, color: accent, trackColor: palette.meterTrack)
                        .frame(width: 54, height: 6)
                },
                value: {
                    Text("21.4°")
                        .font(PerchHATypography.bodyValue())
                        .foregroundStyle(palette.textPrimary)
                },
                control: { EmptyView() }
            )
            .background(
                RoundedRectangle(cornerRadius: PerchHACornerRadius.control, style: .continuous)
                    .fill(palette.surfaceRoot)
            )
            .overlay(
                RoundedRectangle(cornerRadius: PerchHACornerRadius.control, style: .continuous)
                    .strokeBorder(palette.borderSubtle, lineWidth: 1)
            )
            .environment(\.dashboardPalette, palette)
            .environment(\.dashboardRowDensity, displayPreferences.dashboardRowDensity)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Sample dashboard row, Living room temperature 21.4 degrees")
        }
    }

    private var themeModePicker: some View {
        Picker("Theme", selection: themeModeBinding) {
            ForEach(PerchHAThemeMode.allCases, id: \.rawValue) { mode in
                Text(mode.displayName).tag(mode)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .fixedSize()
        .accessibilityLabel("Theme")
    }

    private var accentMenuPicker: some View {
        Picker("Accent", selection: accentSwatchBinding) {
            ForEach(PerchHAAccentColor.swatches) { swatch in
                Text(swatch.name).tag(swatch.id)
            }
        }
        .labelsHidden()
        .frame(width: 160)
        .perchHACompactControl()
        .accessibilityLabel("Accent color")
    }

    private var accentSwatchPreview: some View {
        HStack(spacing: 8) {
            ForEach(PerchHAAccentColor.swatches) { swatch in
                let isSelected = displayPreferences.accentColor == swatch.color
                Button {
                    updateDisplayPreferences(displayPreferences.with(accentColor: swatch.color))
                } label: {
                    Circle()
                        .fill(color(for: swatch.color))
                        .frame(width: 18, height: 18)
                        .overlay(
                            Circle().strokeBorder(
                                isSelected ? Color.primary.opacity(0.75) : Color.primary.opacity(0.12),
                                lineWidth: isSelected ? 2 : 1
                            )
                        )
                }
                .buttonStyle(.plain)
                .help(swatch.name)
                .accessibilityLabel(swatch.name)
                .accessibilityAddTraits(isSelected ? [.isSelected] : [])
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func color(for accent: PerchHAAccentColor) -> Color {
        Color(.sRGB, red: accent.red, green: accent.green, blue: accent.blue, opacity: accent.alpha)
    }

    // MARK: Diagnostics

    /// Diagnostics: real connection status, entity health (the warning count and
    /// a deduped, capped list of affected entities), the last-updated timestamp
    /// with a manual refresh action, and the read-only history-prefetch
    /// reference. All values come from the live snapshot; nothing is fabricated.
    /// This is the only place a manual refresh lives.
    private var diagnosticsTab: some View {
        let health = entityHealth
        return settingsPage(title: "Diagnostics", systemImage: Tab.diagnostics.systemImage) {
            settingsCard {
                settingsSection(title: "Connection", systemImage: "antenna.radiowaves.left.and.right") {
                    diagnosticsConnectionContent
                }
            }
            settingsCard {
                settingsSection(title: "Retry & backoff", systemImage: "arrow.triangle.2.circlepath") {
                    diagnosticsRetryContent
                }
            }
            settingsCard {
                settingsSection(title: "Traffic", systemImage: "arrow.up.arrow.down") {
                    diagnosticsTrafficContent
                }
            }
            settingsCard {
                settingsSection(title: "Recent issues", systemImage: "list.bullet.rectangle") {
                    diagnosticsRecentIssuesContent
                }
            }
            settingsCard {
                settingsSection(title: "Entity health", systemImage: "heart.text.square") {
                    diagnosticsHealthContent(health)
                }
            }
            settingsCard {
                settingsSection(title: "Updates", systemImage: "clock.arrow.circlepath") {
                    diagnosticsUpdatesContent
                }
            }
            settingsCard {
                settingsSection(title: "History sync", systemImage: "chart.line.uptrend.xyaxis") {
                    diagnosticsHistorySyncContent
                }
            }
        }
    }

    /// The connection diagnostic: a status pill carrying its own text plus the
    /// last error message when the snapshot reports one.
    private var diagnosticsConnectionContent: some View {
        let status = connectionDiagnostic
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                StatusPill(
                    status.label,
                    systemImage: status.systemImage,
                    color: status.color,
                    accessibilityLabel: "Connection \(status.label)"
                )
                Spacer(minLength: 0)
            }
            if let detail = model.snapshot.failureDescription {
                PerchHAErrorState(
                    title: "Last error",
                    message: detail,
                    style: .inline,
                    accessibilityPrefix: "Connection error"
                )
            } else {
                Text(status.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// The traffic diagnostic: how many requests PearchHA sent to Home
    /// Assistant within the last minute (REST calls, WebSocket connects, and
    /// service calls). No secret.
    private var diagnosticsTrafficContent: some View {
        let rpm = model.requestsPerMinute()
        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                StatusPill(
                    "\(rpm) req/min",
                    systemImage: "arrow.up.arrow.down",
                    color: PerchHATheme.accent,
                    accessibilityLabel: "\(rpm) requests per minute"
                )
                Spacer(minLength: 0)
            }
            Text("Requests sent to Home Assistant in the last minute: connection checks, history fetches, live-update connects, and actions.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// The retry/backoff diagnostic: a single calm line derived from the live
    /// connection state and the periodic-refresh backoff posture. No secret.
    private var diagnosticsRetryContent: some View {
        let state = retryState
        let isHealthy: Bool = {
            switch state {
            case .connected: return true
            case .connecting, .reconnecting, .backingOff, .disconnected: return false
            }
        }()
        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                StatusPill(
                    state.summary,
                    systemImage: isHealthy ? "checkmark.circle.fill" : "arrow.triangle.2.circlepath",
                    color: isHealthy ? PerchHATheme.ok : PerchHATheme.warn,
                    accessibilityLabel: "Retry state: \(state.summary)"
                )
                Spacer(minLength: 0)
            }
            Text("Background refresh backs off automatically after repeated failures and resumes once the connection recovers.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// The recent-issues diagnostic: the deduped diagnostic ring buffer, newest
    /// first, capped to a sensible visible number with the remainder summarized,
    /// plus a "Clear diagnostics" action. A calm empty state when nothing is
    /// recorded. Messages come straight from the sanitized event log; no secret
    /// is ever shown.
    @ViewBuilder
    private var diagnosticsRecentIssuesContent: some View {
        let events = diagnosticsEvents
        let visibleCap = 8
        if events.isEmpty {
            PerchHAStateView(
                systemImage: "checkmark.seal",
                symbolTint: PerchHATheme.ok,
                title: "No recent issues",
                message: "Connection problems, reconnects, and recoveries will appear here.",
                emphasis: .inline
            )
        } else {
            let visible = Array(events.prefix(visibleCap))
            let hidden = events.count - visible.count
            VStack(alignment: .leading, spacing: 8) {
                VStack(spacing: 0) {
                    ForEach(Array(visible.enumerated()), id: \.element.id) { index, event in
                        diagnosticEventRow(event)
                        if index < visible.count - 1 {
                            Divider().accessibilityHidden(true)
                        }
                    }
                }
                if hidden > 0 {
                    Text("and \(hidden) more \(hidden == 1 ? "event" : "events")")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                HStack {
                    Spacer(minLength: 0)
                    Button {
                        model.clearDiagnostics()
                    } label: {
                        Label("Clear diagnostics", systemImage: "trash")
                            .labelStyle(.titleAndIcon)
                    }
                    .buttonStyle(PerchHAIconButtonStyle())
                    .help("Remove all recorded diagnostic events")
                    .accessibilityLabel("Clear diagnostics")
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// A single recorded diagnostic event row: kind icon + message + relative age,
    /// with a "×N" badge when the event was deduplicated more than once.
    private func diagnosticEventRow(_ event: PerchHADiagnosticEvent) -> some View {
        let tint: Color = {
            switch event.kind {
            case .recovered: return PerchHATheme.ok
            case .reconnecting, .liveUpdatesInterrupted: return PerchHATheme.warn
            case .connectionFailed, .refreshFailed: return PerchHATheme.critical
            }
        }()
        let countSuffix = event.count > 1 ? " ×\(event.count)" : ""
        return HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: event.kind.systemImage)
                .font(.caption)
                .foregroundStyle(tint)
                .frame(width: 18)
                .accessibilityHidden(true)
            Text(event.message)
                .font(.callout)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 8)
            if event.count > 1 {
                Text("×\(event.count)")
                    .font(PerchHATypography.caption().weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            Text(model.relativeAgeDescription(for: event))
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .padding(.vertical, 5)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(event.message)\(countSuffix), \(model.relativeAgeDescription(for: event))")
    }

    /// The entity-health diagnostic: the warning count and a deduped, capped
    /// summary of affected entities, or a calm "all healthy" / "no values" state.
    @ViewBuilder
    private func diagnosticsHealthContent(_ health: EntityHealthReport) -> some View {
        if health.totalVisible == 0 {
            PerchHAStateView(
                systemImage: "tray",
                title: "No values yet",
                message: "Connect and select some values to see their health here.",
                emphasis: .inline
            )
        } else if health.warningCount == 0 {
            PerchHAStateView(
                systemImage: "checkmark.seal",
                symbolTint: PerchHATheme.ok,
                title: "All values healthy",
                message: "\(health.totalVisible) visible \(health.totalVisible == 1 ? "value is" : "values are") reporting normally.",
                emphasis: .inline
            )
        } else {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    StatusPill(
                        health.warningCount == 1 ? "1 needs attention" : "\(health.warningCount) need attention",
                        systemImage: "exclamationmark.triangle.fill",
                        color: PerchHATheme.warn,
                        accessibilityLabel: "\(health.warningCount) of \(health.totalVisible) values need attention"
                    )
                    Spacer(minLength: 0)
                }
                VStack(spacing: 0) {
                    ForEach(Array(health.visibleGroups.enumerated()), id: \.offset) { index, group in
                        HStack(spacing: 8) {
                            Image(systemName: group.systemImage)
                                .font(.caption)
                                .foregroundStyle(PerchHATheme.warn)
                                .frame(width: 18)
                                .accessibilityHidden(true)
                            Text(group.label)
                                .font(.callout)
                            Spacer(minLength: 8)
                            Text("\(group.count)")
                                .font(PerchHATypography.bodyValue())
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 5)
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel("\(group.label), \(group.count)")
                        if index < health.visibleGroups.count - 1 {
                            Divider().accessibilityHidden(true)
                        }
                    }
                }
                if health.hiddenCount > 0 {
                    Text("and \(health.hiddenCount) more")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// The updates diagnostic: the last-updated description plus a manual
    /// "Refresh now" action. Refresh is otherwise automatic (on open,
    /// periodically while open, and via live WebSocket push).
    private var diagnosticsUpdatesContent: some View {
        VStack(alignment: .leading, spacing: 8) {
            settingsControlRow("Last updated") {
                Text(snapshot.lastUpdateDescription)
                    .font(PerchHATypography.bodyValue())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            diagnosticsRefreshSlider(
                title: "Menu Bar Refresh",
                value: displayPreferences.menuBarRefreshInterval.displayName,
                binding: menuBarRefreshIntervalIndexBinding
            )
            diagnosticsRefreshSlider(
                title: "Data Sync",
                value: displayPreferences.dataSyncInterval.displayName,
                binding: dataSyncIntervalIndexBinding
            )
            diagnosticsRefreshSlider(
                title: "History Detail Refresh",
                value: displayPreferences.historyDetailRefreshInterval.displayName,
                binding: historyDetailRefreshIntervalIndexBinding
            )
            Button {
                model.startRefresh()
            } label: {
                Label("Refresh now", systemImage: "arrow.clockwise")
                    .labelStyle(.titleAndIcon)
            }
            .buttonStyle(PerchHAIconButtonStyle())
            .disabled(model.snapshot.connectionState != .connected)
            .help("Fetch the latest values from Home Assistant now")
            .accessibilityLabel("Refresh values now")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var diagnosticsHistorySyncContent: some View {
        let cacheEntries = model.historyCacheEntryCount()
        let cacheSamples = model.historyCacheSampleCount()
        let cacheCapacity = model.historyCacheCapacity()
        return VStack(alignment: .leading, spacing: 6) {
            settingsControlRow("Cache size") {
                Text("\(cacheEntries) series · \(cacheSamples) samples · cap \(cacheCapacity)")
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            settingsControlRow("Policy") {
                Text("day on sync · week/month TTL 24h")
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func diagnosticsRefreshSlider(
        title: String,
        value: String,
        binding: Binding<Double>
    ) -> some View {
        settingsControlRow(title) {
            Text(value)
                .font(PerchHATypography.bodyValue())
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        Slider(
            value: binding,
            in: 0...Double(Self.refreshIntervalOptions.count - 1),
            step: 1
        )
        HStack {
            Text(Self.refreshIntervalOptions.first?.displayName ?? "1s")
            Spacer(minLength: 8)
            Text(Self.refreshIntervalOptions.last?.displayName ?? "300s")
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }

    /// A resolved connection status for the Diagnostics pill, mapped from the
    /// real snapshot connection state.
    private var connectionDiagnostic: (label: String, detail: String, systemImage: String, color: Color) {
        switch model.snapshot.connectionState {
        case .connected:
            return ("Connected", "Live updates are flowing from Home Assistant.", "checkmark.circle.fill", PerchHATheme.ok)
        case .connecting:
            return ("Connecting", "Establishing a connection to Home Assistant.", "hourglass", PerchHATheme.warn)
        case let .reconnecting(attempt):
            return ("Reconnecting", "Attempt \(attempt). Showing the last known values.", "arrow.triangle.2.circlepath", PerchHATheme.warn)
        case .disconnected:
            return ("Disconnected", "Not connected to Home Assistant.", "bolt.horizontal.circle", .secondary)
        case let .failed(failure):
            switch failure {
            case .authentication:
                return ("Permission", "Sign in again or check your access token.", "lock.circle.fill", PerchHATheme.critical)
            case .unreachable, .tlsRejected, .unsupportedCommand, .protocolError:
                return ("Error", "Connection failed. See the last error below.", "exclamationmark.circle.fill", PerchHATheme.critical)
            }
        }
    }

    /// A deduped, capped report of unhealthy entities, built from the same
    /// visible rooms the dashboard warning count uses. Identical statuses are
    /// grouped with a count; the visible list is capped so a large fleet does not
    /// dump hundreds of rows.
    private var entityHealth: EntityHealthReport {
        let visible = model.snapshot.rooms.flatMap(\.entities)
        var unavailable = 0
        var unknown = 0
        var stale = 0
        for entity in visible {
            switch model.snapshot.formattedValue(for: entity).status {
            case .unavailable: unavailable += 1
            case .unknown: unknown += 1
            case .stale: stale += 1
            case .available: break
            }
        }
        let groups: [EntityHealthGroup] = [
            EntityHealthGroup(label: "Unavailable", count: unavailable, systemImage: "wifi.slash"),
            EntityHealthGroup(label: "Unknown", count: unknown, systemImage: "questionmark.circle"),
            EntityHealthGroup(label: "Stale", count: stale, systemImage: "clock.badge.exclamationmark")
        ].filter { $0.count > 0 }
        let cap = 3
        return EntityHealthReport(
            totalVisible: visible.count,
            warningCount: unavailable + unknown + stale,
            visibleGroups: Array(groups.prefix(cap)),
            hiddenCount: groups.dropFirst(cap).reduce(0) { $0 + $1.count }
        )
    }

    // MARK: Privacy

    /// Privacy statement: a static, honest summary of what PearchHA reads, where
    /// credentials live, and the absence of analytics or third-party calls.
    private var privacyTab: some View {
        settingsPage(title: "Privacy", systemImage: Tab.privacy.systemImage) {
            settingsCard {
                settingsSection(title: "What PearchHA reads", systemImage: "doc.text.magnifyingglass") {
                    Text("PearchHA talks only to the Home Assistant server you configure. It reads your Home Assistant address and the access token (or browser sign-in) you provide, plus the entity states needed to show your values.")
                        .font(.callout)
                        .fixedSize(horizontal: false, vertical: true)
                }
                settingsSectionDivider
                settingsSection(title: "Where credentials live", systemImage: "key") {
                    Text("Your access and refresh tokens are stored in the macOS Keychain on this Mac. They are never written to the configuration file and never shown in this window.")
                        .font(.callout)
                        .fixedSize(horizontal: false, vertical: true)
                }
                settingsSectionDivider
                settingsSection(title: "No tracking", systemImage: "hand.raised") {
                    Text("PearchHA makes no analytics, telemetry, or third-party network calls. Nothing is sent anywhere except your own Home Assistant server.")
                        .font(.callout)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    // MARK: General bindings

    private func updateDisplayPreferences(_ preferences: PerchHADisplayPreferences) {
        displayPreferences = preferences
        pendingDisplayPreferencesSave?.cancel()
        pendingDisplayPreferencesSave = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 150_000_000)
            guard !Task.isCancelled else {
                return
            }
            displayPreferencesSink(preferences)
            pendingDisplayPreferencesSave = nil
        }
    }

    private func flushPendingDisplayPreferencesSave() {
        pendingDisplayPreferencesSave?.cancel()
        pendingDisplayPreferencesSave = nil
        displayPreferencesSink(displayPreferences)
    }

    private var stableMenuBarWidthBinding: Binding<Bool> {
        Binding(
            get: { displayPreferences.stableMenuBarWidth },
            set: { updateDisplayPreferences(displayPreferences.with(stableMenuBarWidth: $0)) }
        )
    }

    private var menuBarAppearanceBinding: Binding<PerchHAMenuBarAppearance> {
        Binding(
            get: { displayPreferences.menuBarAppearance },
            set: { updateDisplayPreferences(displayPreferences.with(menuBarAppearance: $0)) }
        )
    }

    private var menuBarRefreshIntervalIndexBinding: Binding<Double> {
        refreshIntervalIndexBinding(
            get: { displayPreferences.menuBarRefreshInterval },
            set: { updateDisplayPreferences(displayPreferences.with(menuBarRefreshInterval: $0)) }
        )
    }

    private var dataSyncIntervalIndexBinding: Binding<Double> {
        refreshIntervalIndexBinding(
            get: { displayPreferences.dataSyncInterval },
            set: { updateDisplayPreferences(displayPreferences.with(dataSyncInterval: $0)) }
        )
    }

    private var historyDetailRefreshIntervalIndexBinding: Binding<Double> {
        refreshIntervalIndexBinding(
            get: { displayPreferences.historyDetailRefreshInterval },
            set: { updateDisplayPreferences(displayPreferences.with(historyDetailRefreshInterval: $0)) }
        )
    }

    private func refreshIntervalIndexBinding(
        get currentValue: @escaping () -> PerchHAMenuBarRefreshInterval,
        set apply: @escaping (PerchHAMenuBarRefreshInterval) -> Void
    ) -> Binding<Double> {
        Binding(
            get: {
                Double(
                    Self.refreshIntervalOptions.firstIndex(of: currentValue()) ?? 0
                )
            },
            set: { newValue in
                let index = min(
                    max(Int(newValue.rounded()), Self.refreshIntervalOptions.startIndex),
                    Self.refreshIntervalOptions.index(before: Self.refreshIntervalOptions.endIndex)
                )
                apply(Self.refreshIntervalOptions[index])
            }
        )
    }

    private var rowDensityBinding: Binding<PerchHADashboardRowDensity> {
        Binding(
            get: { displayPreferences.dashboardRowDensity },
            set: { updateDisplayPreferences(displayPreferences.with(dashboardRowDensity: $0)) }
        )
    }

    private var defaultHistoryRangeBinding: Binding<HistoryRange> {
        Binding(
            get: { displayPreferences.defaultHistoryRange },
            set: { updateDisplayPreferences(displayPreferences.with(defaultHistoryRange: $0)) }
        )
    }

    private var footerTimestampBinding: Binding<Bool> {
        Binding(
            get: { displayPreferences.showsFooterTimestamp },
            set: { updateDisplayPreferences(displayPreferences.with(showsFooterTimestamp: $0)) }
        )
    }

    private func entityIconVisibilityBinding(for id: EntityID) -> Binding<Bool> {
        Binding(
            get: { model.snapshot.menuBarDisplayConfiguration.itemConfiguration(for: id).showsEntityIcon },
            set: { model.setShowsEntityIcon(id, showsEntityIcon: $0) }
        )
    }

    private var themeModeBinding: Binding<PerchHAThemeMode> {
        Binding(
            get: { displayPreferences.themeMode },
            set: { updateDisplayPreferences(displayPreferences.with(themeMode: $0)) }
        )
    }

    private var accentSwatchBinding: Binding<String> {
        Binding(
            get: { displayPreferences.accentColor.matchingSwatchID ?? PerchHAAccentColor.swatches.first?.id ?? "ha-blue" },
            set: { id in
                guard let swatch = PerchHAAccentColor.swatches.first(where: { $0.id == id }) else {
                    return
                }
                updateDisplayPreferences(displayPreferences.with(accentColor: swatch.color))
            }
        )
    }

    private var launchAtLoginBinding: Binding<Bool> {
        Binding(
            get: { launchAtLogin },
            set: { requested in
                // Reflect the real resulting login-item state: if the service
                // call fails, the toggle snaps back instead of lying.
                let applied = launchAtLoginSink(requested)
                launchAtLogin = applied ? requested : launchAtLoginProvider()
                // Surface a calm permission message only when the user asked to
                // enable launch at login and the system declined.
                launchAtLoginPermissionDenied = requested && !applied
            }
        )
    }

    private var aboutTab: some View {
        settingsPage(title: "About", systemImage: Tab.about.systemImage) {
            aboutIdentityCard
            aboutDetailsCard
            aboutSupportCard
        }
    }

    /// Identity card: the real application icon, the app name, version, and a
    /// one-line description of what PearchHA is.
    private var aboutIdentityCard: some View {
        settingsCard {
            HStack(alignment: .center, spacing: 14) {
                aboutAppIcon
                VStack(alignment: .leading, spacing: 3) {
                    Text("PearchHA")
                        .font(.title2.weight(.semibold))
                    Text("Version \(Self.applicationVersion.displayText)")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("PearchHA, version \(Self.applicationVersion.displayText)")
            Text("A calm Home Assistant menu-bar companion for macOS.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// The real application icon at a tasteful size, falling back to an SF Symbol
    /// glyph when no app icon is available (for example in non-bundle render
    /// paths).
    @ViewBuilder
    private var aboutAppIcon: some View {
        if let icon = Self.applicationIconImage {
            Image(nsImage: icon)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 68, height: 68)
                .accessibilityHidden(true)
        } else {
            Image(systemName: "house.circle.fill")
                .font(.system(size: 64))
                .foregroundStyle(PerchHATheme.accent)
                .accessibilityHidden(true)
        }
    }

    /// Details card: license, developer, and repository, with the license and
    /// repository as browser links.
    private var aboutDetailsCard: some View {
        settingsCard {
            settingsSection(title: "Details", systemImage: "info.circle") {
                VStack(alignment: .leading, spacing: 8) {
                    settingsControlRow("License") {
                        Link("MIT License", destination: Self.licenseURL)
                            .accessibilityLabel("MIT License, opens in browser")
                    }
                    settingsControlRow("Developer") {
                        Text("YunaBraska")
                            .foregroundStyle(.secondary)
                    }
                    settingsControlRow("Repository") {
                        Link("github.com/YunaBraska/pearch_ha", destination: Self.repositoryURL)
                            .accessibilityLabel("Repository on GitHub, opens in browser")
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    settingsControlRow("Updates") {
                        VStack(alignment: .trailing, spacing: 6) {
                            aboutUpdateAction
                            Text(aboutUpdateSummary)
                                .font(.footnote)
                                .foregroundStyle(aboutUpdateSummaryColor)
                                .multilineTextAlignment(.trailing)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }
        }
    }

    /// Support card: optional appreciation links (repo star, sponsor/coffee/Ko-fi/
    /// Liberapay) plus an issues/feedback link.
    private var aboutSupportCard: some View {
        settingsCard {
            settingsSection(title: "Support", systemImage: "heart") {
                VStack(alignment: .leading, spacing: 10) {
                    Text("If it earned a place on your menu bar, a star on the repo helps. If you want to fuel a coffee:")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    HStack(spacing: 8) {
                        aboutSupportLink("GitHub Sponsors", systemImage: "heart.fill", destination: Self.sponsorsURL)
                        aboutSupportLink("Buy Me a Coffee", systemImage: "cup.and.saucer.fill", destination: Self.buyMeACoffeeURL)
                    }
                    HStack(spacing: 8) {
                        aboutSupportLink("Ko-fi", systemImage: "mug.fill", destination: Self.koFiURL)
                        aboutSupportLink("Liberapay", systemImage: "banknote", destination: Self.liberapayURL)
                    }
                    Link(destination: Self.issuesURL) {
                        Label("Issues / feedback", systemImage: "exclamationmark.bubble")
                            .labelStyle(.titleAndIcon)
                    }
                    .buttonStyle(PerchHAIconButtonStyle())
                    .accessibilityLabel("Issues and feedback on GitHub, opens in browser")
                }
            }
        }
    }

    /// A single design-system styled support link with an SF Symbol and an
    /// accessible name describing where it leads.
    private func aboutSupportLink(_ title: String, systemImage: String, destination: URL) -> some View {
        Link(destination: destination) {
            Label(title, systemImage: systemImage)
                .labelStyle(.titleAndIcon)
                .lineLimit(1)
        }
        .buttonStyle(PerchHAIconButtonStyle(prominentOnHover: true))
        .accessibilityLabel("\(title), opens in browser")
    }

    @ViewBuilder
    private var aboutUpdateAction: some View {
        switch releaseState {
        case let .updateAvailable(update):
            Link(destination: update.downloadURL) {
                Label("Download \(update.latestVersion)", systemImage: "arrow.down.circle")
                    .labelStyle(.titleAndIcon)
            }
            .buttonStyle(PerchHAIconButtonStyle(prominentOnHover: true))
            .accessibilityLabel("Download PearchHA \(update.latestVersion), opens in browser")
        case .checking:
            HStack(spacing: 8) {
                ProgressView()
                    .controlSize(.small)
                Text("Checking...")
                    .font(.callout.weight(.medium))
            }
            .foregroundStyle(.secondary)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Checking for updates")
        case .idle, .upToDate, .failed:
            Button {
                Task { @MainActor in
                    await model.checkForUpdates()
                }
            } label: {
                Label("Check for updates", systemImage: "arrow.trianglehead.clockwise")
                    .labelStyle(.titleAndIcon)
            }
            .buttonStyle(PerchHAIconButtonStyle(prominentOnHover: true))
            .accessibilityLabel("Check for updates")
        }
    }

    private var aboutUpdateSummary: String {
        switch releaseState {
        case .idle:
            "Check GitHub for the newest published release."
        case .checking:
            "Looking for a newer published release."
        case let .upToDate(currentVersion, latestVersion, _):
            currentVersion == latestVersion ? "PearchHA is up to date." : "Installed \(currentVersion). Latest \(latestVersion)."
        case let .updateAvailable(update):
            "Installed \(update.currentVersion). Latest \(update.latestVersion)."
        case let .failed(message):
            message
        }
    }

    private var aboutUpdateSummaryColor: Color {
        switch releaseState {
        case .failed:
            PerchHATheme.critical
        case .updateAvailable:
            PerchHATheme.warn
        case .idle, .checking, .upToDate:
            .secondary
        }
    }

    private static let repositoryURL = URL(string: "https://github.com/YunaBraska/pearch_ha")!
    private static let licenseURL = URL(string: "https://github.com/YunaBraska/pearch_ha/blob/main/LICENSE")!
    private static let issuesURL = URL(string: "https://github.com/YunaBraska/pearch_ha/issues")!
    private static let sponsorsURL = URL(string: "https://github.com/sponsors/YunaBraska")!
    private static let buyMeACoffeeURL = URL(string: "https://buymeacoffee.com/YunaBraska")!
    private static let koFiURL = URL(string: "https://ko-fi.com/YunaBraska")!
    private static let liberapayURL = URL(string: "https://liberapay.com/YunaBraska")!

    /// The running application's icon, used in the About identity card. Resolves
    /// from the live `NSApp` icon first, then the named application icon.
    private static var applicationIconImage: NSImage? {
        NSApp.applicationIconImage ?? NSImage(named: NSImage.applicationIconName)
    }

    private static let applicationVersion = PerchHAApplicationVersionInfo.currentBundle()
    private static let refreshIntervalOptions = PerchHAMenuBarRefreshInterval.allCases

    private var entitiesTab: some View {
        ScrollViewReader { scrollProxy in
            settingsPage(title: "Entities", systemImage: Tab.entities.systemImage) {
                settingsContent
            }
            .onAppear {
                schedulePendingReveal(using: scrollProxy)
            }
        }
    }

    private var settingsContent: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                PerchHACapsuleField(systemImage: "magnifyingglass") {
                    TextField("Search", text: selectionSearchBinding)
                        .textFieldStyle(.plain)
                }
                Button {
                    model.setAllEntities(isSelected: true)
                } label: {
                    Label("Select all", systemImage: "checkmark.circle")
                        .labelStyle(.titleAndIcon)
                }
                .buttonStyle(PerchHAIconButtonStyle())
                .help("Show every discovered value in the panel")
                .accessibilityLabel("Select all")
                Button {
                    model.setAllEntities(isSelected: false)
                } label: {
                    Label("Clear", systemImage: "circle")
                        .labelStyle(.titleAndIcon)
                }
                .buttonStyle(PerchHAIconButtonStyle())
                .help("Hide every value from the panel")
                .accessibilityLabel("Clear")
                collapseAllControl
            }
            .disabled(model.snapshot.availableRooms.isEmpty)
            if let selectionPersistenceFailure = model.snapshot.selectionPersistenceFailureDescription {
                Text(selectionPersistenceFailure)
                    .font(.callout)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityLabel("Selection settings error: \(selectionPersistenceFailure)")
            }
            if let displayPersistenceFailure = model.snapshot.displayPersistenceFailureDescription {
                Text(displayPersistenceFailure)
                    .font(.callout)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityLabel("Display settings error: \(displayPersistenceFailure)")
            }
            if let serviceMetadataFailure = model.snapshot.serviceMetadataFailureDescription {
                Text(serviceMetadataFailure)
                    .font(.callout)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityLabel("Service metadata error: \(serviceMetadataFailure)")
            }
            if let customActionPersistenceFailure = viewState.customActionPersistenceFailureDescription {
                Text(customActionPersistenceFailure)
                    .font(.callout)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityLabel("Action settings error: \(customActionPersistenceFailure)")
            }
            if let shellPersistenceFailure = viewState.shellPersistenceFailureDescription {
                Text(shellPersistenceFailure)
                    .font(.callout)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityLabel("Storage error: \(shellPersistenceFailure)")
            }
            if !model.orphanedCustomActions.isEmpty {
                orphanedCustomActionControls
            }
            if settingsTree.isEmpty {
                Text("No matching values.")
                    .foregroundStyle(.secondary)
            } else {
                let tree = settingsTree
                // One flat lazy stack: room headers and entity rows are all
                // direct lazy children. Nesting a lazy stack per room forces
                // the whole room to materialize when the outer stack sizes it,
                // which stalls the main thread for seconds on large rooms.
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(tree.enumerated()), id: \.element.id.rawValue) { index, room in
                        selectionDragDrop(
                            selectionRoomHeader(
                                room,
                                isExpanded: isRoomExpanded(room),
                                canMoveUp: canReorderSelection && index > tree.startIndex,
                                canMoveDown: canReorderSelection && index < tree.index(before: tree.endIndex)
                            )
                            .padding(.horizontal, PerchHASpacing.xs),
                            item: .room(room.id)
                        )
                        .padding(.top, index == tree.startIndex ? 0 : 10)
                        .padding(.bottom, 5)
                        if isRoomExpanded(room) {
                            ForEach(Array(room.entities.enumerated()), id: \.element.entity.id.rawValue) { rowIndex, selectable in
                                selectionEntityRowSegment(room: room, rowIndex: rowIndex, selectable: selectable)
                                    .id(selectable.entity.id.rawValue)
                            }
                        }
                    }
                }
            }
        }
    }

    private var orphanedCustomActionControls: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("Unused buttons")
                .font(.caption)
                .foregroundStyle(.secondary)
            ForEach(model.orphanedCustomActions, id: \.id.rawValue) { action in
                HStack(spacing: 6) {
                    Text("\(action.title) - \(action.entityID.rawValue)")
                        .font(.caption)
                        .lineLimit(1)
                    Spacer()
                    Button {
                        model.removeCustomAction(action.id)
                    } label: {
                        Image(systemName: "trash")
                            .frame(width: 18, height: 18)
                    }
                    .buttonStyle(PerchHACircularIconButtonStyle())
                    .controlSize(.small)
                    .help("Delete unused button")
                    .accessibilityLabel("Delete unused button \(action.title)")
                }
            }
        }
    }

    private var canReorderSelection: Bool {
        snapshot.canReorderSelectionWithKeyboard
    }

    /// True while the user is filtering the entity tree. During a search every
    /// rendered room is forced expanded so matches are never hidden behind a
    /// collapsed header; the stored ``expandedRooms`` set is left untouched so
    /// clearing the search restores the prior state.
    private var isSelectionSearching: Bool {
        !snapshot.selectionQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// Whether `room` should show its entity rows. Rooms default to collapsed;
    /// a room is expanded only when it is in ``expandedRooms``. An active
    /// search or the room holding the open inspector forces it expanded
    /// without mutating the stored state.
    private func isRoomExpanded(_ room: SelectableRoom) -> Bool {
        let containsInspected = inspectedEntityID.map { id in
            room.entities.contains { $0.entity.id == id }
        } ?? false
        return SelectionRoomCollapse.isExpanded(
            roomID: room.id.rawValue,
            expandedRoomIDs: expandedRooms,
            isSearching: isSelectionSearching,
            roomContainsInspectedEntity: containsInspected
        )
    }

    /// True when every currently-shown room is collapsed, used to flip the
    /// collapse-all affordance to "Expand all". Searching counts as expanded.
    private var allRoomsCollapsed: Bool {
        SelectionRoomCollapse.allCollapsed(
            roomIDs: settingsTree.map { $0.id.rawValue },
            expandedRoomIDs: expandedRooms,
            isSearching: isSelectionSearching
        )
    }

    /// A small token-styled control that collapses or expands every room at once.
    /// While searching it is disabled, since search already forces rooms open.
    private var collapseAllControl: some View {
        let expandAll = allRoomsCollapsed
        return Button {
            withSelectionAnimation {
                if expandAll {
                    expandedRooms = Set(settingsTree.map { $0.id.rawValue })
                } else {
                    expandedRooms.removeAll()
                }
            }
        } label: {
            Label(
                expandAll ? "Expand all" : "Collapse all",
                systemImage: expandAll ? "chevron.down.square" : "chevron.up.square"
            )
            .labelStyle(.titleAndIcon)
        }
        .buttonStyle(PerchHAIconButtonStyle())
        .disabled(isSelectionSearching || settingsTree.isEmpty)
        .help(expandAll ? "Show every room's values" : "Hide every room's values")
        .accessibilityLabel(expandAll ? "Expand all rooms" : "Collapse all rooms")
    }

    /// Toggles `room`'s collapsed state. Collapsing the room that holds the open
    /// inspector also closes the inspector, so the inspected entity is never left
    /// stranded behind a collapsed header.
    private func toggleRoomCollapsed(_ room: SelectableRoom) {
        let id = room.id.rawValue
        withSelectionAnimation {
            if expandedRooms.contains(id) {
                expandedRooms.remove(id)
                if let inspectedEntityID, room.entities.contains(where: { $0.entity.id == inspectedEntityID }) {
                    self.inspectedEntityID = nil
                }
            } else {
                expandedRooms.insert(id)
            }
        }
    }

    /// Runs `body` inside a calm expand/collapse animation, or with no animation
    /// when the resolved accessibility preference asks for reduced motion.
    private func withSelectionAnimation(_ body: () -> Void) {
        let reduceMotion = accessibilityPreferences.motionPolicy == .reduced
        if let animation = PerchHAMotion.animation(reduceMotion: reduceMotion) {
            withAnimation(animation, body)
        } else {
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction, body)
        }
    }

    /// One lazily-materialized slice of a room card: the row plus its share of
    /// the card chrome. The first/last rows round the card's outer corners and
    /// draw the top/bottom border; every row draws the side borders; rows after
    /// the first draw the inset hairline separator. A run of sibling segments
    /// reads as one card without a container view forcing the whole room to
    /// lay out at once.
    private func selectionEntityRowSegment(
        room: SelectableRoom,
        rowIndex: Int,
        selectable: SelectableEntity
    ) -> some View {
        let palette = PerchHATheme.Dashboard.palette(colorScheme)
        let isFirst = rowIndex == room.entities.startIndex
        let isLast = rowIndex == room.entities.index(before: room.entities.endIndex)
        return selectionDragDrop(
            selectionEntityRow(
                roomName: room.name,
                selectable,
                canMoveUp: canReorderSelection && !isFirst,
                canMoveDown: canReorderSelection && !isLast
            ),
            item: .entity(selectable.entity.id)
        )
        .padding(.top, isFirst ? PerchHASpacing.xs : 0)
        .padding(.bottom, isLast ? PerchHASpacing.xs : 0)
        .background(
            SelectionRoomSegmentShape(
                radius: PerchHACornerRadius.card,
                roundsTop: isFirst,
                roundsBottom: isLast
            )
            .fill(palette.surfacePanel)
        )
        .overlay(
            SelectionRoomSegmentBorderShape(
                radius: PerchHACornerRadius.card,
                roundsTop: isFirst,
                roundsBottom: isLast
            )
            .stroke(palette.borderSubtle, lineWidth: 1)
        )
        .overlay(alignment: .top) {
            if !isFirst {
                Rectangle()
                    .fill(palette.separatorSubtle)
                    .frame(height: 1)
                    .padding(.leading, 34)
            }
        }
    }

    /// A tappable room header that reads as a section header (uppercase room name
    /// + entity count) and toggles the room's collapsed state. A leading chevron
    /// rotates to communicate expanded/collapsed; the per-room reorder controls
    /// stay in the trailing slot. The toggle is a `Button`, so it is keyboard
    /// activatable and carries an expanded/collapsed accessibility value.
    private func selectionRoomHeader(
        _ room: SelectableRoom,
        isExpanded: Bool,
        canMoveUp: Bool,
        canMoveDown: Bool
    ) -> some View {
        let palette = PerchHATheme.Dashboard.palette(colorScheme)
        let count = room.entities.count
        let countLabel = count == 1 ? "1 entity" : "\(count) entities"
        return HStack(spacing: PerchHASpacing.xs + 1) {
            Button {
                toggleRoomCollapsed(room)
            } label: {
                HStack(spacing: PerchHASpacing.xs + 1) {
                    Image(systemName: "chevron.right")
                        .font(PerchHATypography.caption())
                        .foregroundStyle(palette.textSecondary)
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                        .accessibilityHidden(true)
                    Text(room.name)
                        .font(PerchHATypography.caption())
                        .foregroundStyle(.secondary)
                        .textCase(.uppercase)
                        .tracking(0.5)
                        .lineLimit(1)
                    Text("· \(count)")
                        .font(PerchHATypography.caption())
                        .foregroundStyle(palette.textTertiary)
                        .accessibilityHidden(true)
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(isSelectionSearching)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(room.name), \(countLabel)")
            .accessibilityValue(isExpanded ? "Expanded" : "Collapsed")
            .accessibilityHint(isExpanded ? "Collapse room" : "Expand room")
            .accessibilityAddTraits(.isButton)
            selectionMoveButtons(
                up: {
                    model.moveRoom(room.id, direction: .up)
                },
                down: {
                    model.moveRoom(room.id, direction: .down)
                },
                upLabel: "Move \(room.name) up",
                downLabel: "Move \(room.name) down",
                canMoveUp: canMoveUp,
                canMoveDown: canMoveDown
            )
        }
    }

    /// A compact, collapsed entity row: selection checkbox, domain icon, name,
    /// a type/unit caption, a menu-bar-visible pill, reorder controls, and a
    /// disclosure toggle that opens this entity's inspector. Clicking the row
    /// (or the disclosure) opens the single inspector inline beneath the row;
    /// only one inspector is open at a time.
    private func selectionEntityRow(
        roomName: String,
        _ selectable: SelectableEntity,
        canMoveUp: Bool,
        canMoveDown: Bool
    ) -> some View {
        let palette = PerchHATheme.Dashboard.palette(colorScheme)
        let entity = selectable.entity
        let rowCaption = PerchHAEntityMetadataPresentation.rowCaption(for: entity)
        let hasAverageLinks = viewState.hasAverageLinks(for: entity.id)
        let isExpanded = inspectedEntityID == entity.id
        let isPromoted = snapshot.menuBarDisplayConfiguration.isPromoted(entity.id)
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Toggle("", isOn: selectionBinding(for: entity.id))
                    .labelsHidden()
                    .accessibilityLabel("Show \(entity.name) in panel")
                Image(systemName: perchHAEntityIconName(for: entity))
                    .font(.system(size: 14))
                    .frame(width: 22, alignment: .center)
                    .foregroundStyle(isExpanded ? palette.accentPrimary : palette.textSecondary)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 0) {
                    Text(entity.name)
                        .foregroundStyle(palette.textPrimary)
                        .lineLimit(1)
                    Text(rowCaption)
                        .font(PerchHATypography.caption().weight(.regular))
                        .foregroundStyle(palette.textTertiary)
                        .lineLimit(1)
                }
                Spacer(minLength: 8)
                if hasAverageLinks {
                    averageLinkedPill
                }
                if isPromoted {
                    menuBarVisiblePill
                }
                selectionMoveButtons(
                    up: {
                        model.moveEntity(entity.id, direction: .up)
                    },
                    down: {
                        model.moveEntity(entity.id, direction: .down)
                    },
                    upLabel: "Move \(entity.name) up",
                    downLabel: "Move \(entity.name) down",
                    canMoveUp: canMoveUp,
                    canMoveDown: canMoveDown
                )
                Button {
                    toggleEntityInspector(entity.id)
                } label: {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .semibold))
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                        .frame(width: 18, height: 18)
                }
                .buttonStyle(PerchHACircularIconButtonStyle())
                .controlSize(.small)
                .help(isExpanded ? "Hide settings" : "Show settings")
                .accessibilityLabel(isExpanded ? "Hide \(entity.name) settings" : "Show \(entity.name) settings")
            }
            .font(.body)
            .contentShape(Rectangle())
            .onTapGesture {
                toggleEntityInspector(entity.id)
            }
            if isExpanded {
                settingsInsetGroup {
                    entityDetailSections(for: entity, roomName: roomName)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(
            isExpanded
                ? RoundedRectangle(cornerRadius: PerchHACornerRadius.control, style: .continuous)
                    .fill(palette.accentPrimary.opacity(colorScheme == .dark ? 0.10 : 0.06))
                : nil
        )
    }

    /// The compact "shown in menu bar" pill used on a collapsed entity row.
    private var menuBarVisiblePill: some View {
        collapsedEntityStatusPill(
            systemImage: "menubar.rectangle",
            color: PerchHATheme.Dashboard.palette(colorScheme).accentPrimary,
            accessibilityLabel: "Shown in menu bar"
        )
    }

    /// The compact indicator that this entity participates in a linked average.
    private var averageLinkedPill: some View {
        collapsedEntityStatusPill(
            systemImage: "link",
            color: PerchHATheme.Dashboard.palette(colorScheme).warning,
            accessibilityLabel: "Linked values"
        )
    }

    private func collapsedEntityStatusPill(
        systemImage: String,
        color: Color,
        accessibilityLabel: String
    ) -> some View {
        Image(systemName: systemImage)
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(color)
            .frame(minWidth: 26, minHeight: 18)
            .background(
                Capsule(style: .continuous)
                    .fill(color.opacity(colorScheme == .dark ? 0.22 : 0.14))
            )
            .accessibilityLabel(accessibilityLabel)
            .help(accessibilityLabel)
    }

    /// Opens the inspector for `id`, collapsing any other open inspector so only
    /// one is ever open; tapping the open row collapses it.
    private func toggleEntityInspector(_ id: EntityID) {
        inspectedEntityID = (inspectedEntityID == id) ? nil : id
    }

    private func revealPendingEntity(using scrollProxy: ScrollViewProxy) {
        guard let pendingRevealEntityID else {
            return
        }
        scrollProxy.scrollTo(pendingRevealEntityID.rawValue, anchor: .center)
    }

    private func schedulePendingReveal(using scrollProxy: ScrollViewProxy) {
        guard pendingRevealEntityID != nil else {
            return
        }
        Task { @MainActor in
            await Task.yield()
            revealPendingEntity(using: scrollProxy)
            pendingRevealEntityID = nil
        }
    }

    /// The bespoke detail pane shown when an entity row is expanded: clearly
    /// labelled Display, Menu bar, Alerts, and Buttons sections with
    /// accent-tinted headers and accent-tinted controls, separated by hairlines.
    private func entityDetailSections(for entity: DiscoveredEntity, roomName: String) -> some View {
        let configuration = snapshot.effectiveMenuBarItemConfiguration(for: entity)
        let metadata = viewState.presentation(for: entity, roomName: roomName).metadata
        let links = PerchHAEntityMetadataLinksPresentation(
            baseURL: snapshot.connectionForm.primaryURL(),
            entity: entity
        )
        let isPromoted = snapshot.menuBarDisplayConfiguration.isPromoted(entity.id)
        let showsAverageSection = viewState.canAverageEntity(entity.id)
        return VStack(alignment: .leading, spacing: 0) {
            settingsSection(title: "Identity", systemImage: "info.circle") {
                entityIdentitySection(metadata.inspectorFields, links: links)
            }
            settingsSectionDivider
            settingsSection(title: "Display", systemImage: "textformat.size") {
                displaySectionControls(for: entity, configuration: configuration, isPromoted: isPromoted)
            }
            if showsAverageSection {
                settingsSectionDivider
                settingsSection(title: "Average", systemImage: "sum") {
                    averageSectionControls(for: entity)
                }
            }
            settingsSectionDivider
            settingsSection(title: "Menu bar", systemImage: "menubar.rectangle") {
                menuBarSectionControls(for: entity, isPromoted: isPromoted)
            }
            settingsSectionDivider
            settingsSection(title: "Thresholds", systemImage: "bell.badge") {
                menuBarThresholdControls(for: entity, configuration: configuration)
            }
        }
        .font(.caption)
        .controlSize(.small)
        .tint(PerchHATheme.accent)
    }

    private func entityIdentitySection(
        _ fields: [PerchHAEntityMetadataPresentation.Field],
        links: PerchHAEntityMetadataLinksPresentation
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(fields.enumerated()), id: \.offset) { _, field in
                settingsControlRow(field.label) {
                    VStack(alignment: .trailing, spacing: 3) {
                        if let destination = metadataLink(for: field, links: links) {
                            Link(destination: destination) {
                                Label {
                                    metadataFieldValueText(field)
                                } icon: {
                                    Image(systemName: "arrow.up.right.square")
                                        .font(.system(size: 10, weight: .semibold))
                                }
                            }
                            .accessibilityLabel(accessibilityLabel(for: field))
                            .fixedSize(horizontal: false, vertical: true)
                        } else {
                            metadataFieldValueText(field)
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func metadataFieldValueText(_ field: PerchHAEntityMetadataPresentation.Field) -> some View {
        Text(field.value)
            .font(
                field.usesMonospacedFont
                    ? .system(size: 11.5, weight: .regular, design: .monospaced)
                    : PerchHATypography.caption()
            )
            .foregroundStyle(.primary)
            .multilineTextAlignment(.trailing)
            .textSelection(.enabled)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func metadataLink(
        for field: PerchHAEntityMetadataPresentation.Field,
        links: PerchHAEntityMetadataLinksPresentation
    ) -> URL? {
        switch field.label {
        case "Entity ID":
            return links.entitiesURL
        case "Device ID":
            return links.deviceURL
        default:
            return nil
        }
    }

    private func accessibilityLabel(for field: PerchHAEntityMetadataPresentation.Field) -> String {
        switch field.label {
        case "Entity ID":
            return "Open Home Assistant entities page for \(field.value)"
        case "Device ID":
            return "Open Home Assistant device page for \(field.value)"
        default:
            return field.value
        }
    }

    /// A single labelled settings section with a small accent-tinted leading SF
    /// Symbol header and right-aligned controls in the bespoke PerchHA language.
    private func settingsSection<Content: View>(
        title: String,
        systemImage: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: PerchHASpacing.sm) {
            PerchHASectionHeader(title, systemImage: systemImage)
            content()
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, PerchHASpacing.sm)
    }

    private var settingsSectionDivider: some View {
        Divider()
            .accessibilityHidden(true)
    }

    /// Display section: how the value is rendered (style, unit, min/max,
    /// label/unit toggles, decimals). Excludes promotion/reorder and alerts.
    @ViewBuilder
    private func displaySectionControls(
        for entity: DiscoveredEntity,
        configuration: MenuBarItemConfiguration,
        isPromoted: Bool
    ) -> some View {
        let isNumeric = menuBarNumericState(entity.state) != nil
        let isCover = entity.id.domain == "cover"
        VStack(alignment: .leading, spacing: 6) {
            if isNumeric {
                settingsControlRow("Style") {
                    Picker("Style", selection: menuBarStyleBinding(for: entity.id)) {
                        ForEach(MenuBarDisplayStyle.allCases, id: \.rawValue) { style in
                            Text(style.displayName).tag(style)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 110)
                    .accessibilityLabel("\(entity.name) display style")
                }
            }

            if isCover {
                settingsControlRow("Controls") {
                    Picker("Controls", selection: coverControlModeBinding(for: entity.id)) {
                        ForEach(CoverControlMode.allCases, id: \.rawValue) { mode in
                            Text(mode.displayName).tag(mode)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 110)
                    .accessibilityLabel("\(entity.name) cover controls")
                }
            }

            unitDisplayControls(for: entity, configuration: configuration)

            settingsControlRow("Icon") {
                entityIconPicker(for: entity, configuration: configuration)
            }

            settingsControlRow("Chart range") {
                Picker("Chart range", selection: menuBarHistoryRangeBinding(for: entity.id)) {
                    Text("Auto").tag(HistoryRange?.none)
                    ForEach(HistoryRange.allCases, id: \.rawValue) { range in
                        Text(range.displayName).tag(HistoryRange?.some(range))
                    }
                }
                .labelsHidden()
                .frame(width: 96)
                .accessibilityLabel("\(entity.name) chart range")
            }

            if isPromoted {
                settingsControlRow("Decimals") {
                    Picker("Decimals", selection: menuBarDecimalsBinding(for: entity.id)) {
                        ForEach(0...3, id: \.self) { digits in
                            Text("\(digits)").tag(digits)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .fixedSize()
                    .accessibilityLabel("\(entity.name) decimals")
                }
                if configuration.style != .text && menuBarCanUseGaugeTotal(for: entity) {
                    menuBarTotalControls(for: entity, configuration: configuration)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func averageSectionControls(for entity: DiscoveredEntity) -> some View {
        let linkedEntities = model.averageLinkedEntities(for: entity.id)
        VStack(alignment: .leading, spacing: 8) {
            settingsControlRow("Linked values") {
                Text(linkedEntities.isEmpty ? "None" : "\(linkedEntities.count + 1) values")
                    .foregroundStyle(.secondary)
            }

            if linkedEntities.isEmpty {
                Text("No linked values")
                    .foregroundStyle(.secondary)
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(linkedEntities, id: \.id.rawValue) { linked in
                        HStack(spacing: 8) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(linked.name)
                                Text(averageEntitySecondaryText(linked))
                                    .foregroundStyle(.secondary)
                            }
                            Spacer(minLength: 8)
                            Button {
                                removeAverageLink(from: entity.id, linkedID: linked.id)
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .frame(width: 18, height: 18)
                            }
                            .buttonStyle(PerchHACircularIconButtonStyle())
                            .controlSize(.small)
                            .help("Remove \(linked.name) from the shared average")
                            .accessibilityLabel("Remove \(linked.name) from \(entity.name) average")
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            HStack(spacing: 8) {
                Button {
                    averagePickerSearchText = ""
                    averagePickerEntityID = entity.id
                } label: {
                    Label("Add value", systemImage: "plus")
                        .labelStyle(.titleAndIcon)
                }
                .buttonStyle(PerchHAIconButtonStyle())
                .popover(
                    isPresented: averagePickerBinding(for: entity.id),
                    arrowEdge: .bottom
                ) {
                    averagePickerPopover(for: entity)
                }
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func averagePickerBinding(for id: EntityID) -> Binding<Bool> {
        Binding(
            get: {
                averagePickerEntityID == id
            },
            set: { isPresented in
                if isPresented {
                    averagePickerSearchText = ""
                    averagePickerEntityID = id
                } else if averagePickerEntityID == id {
                    averagePickerEntityID = nil
                    averagePickerSearchText = ""
                }
            }
        )
    }

    private func averagePickerPopover(for entity: DiscoveredEntity) -> some View {
        let candidates = filteredAverageCandidates(for: entity)
        return VStack(alignment: .leading, spacing: 10) {
            TextField("Search values", text: $averagePickerSearchText)
                .textFieldStyle(.roundedBorder)
            if candidates.isEmpty {
                Text("No matching values")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(Array(candidates.enumerated()), id: \.element.id.rawValue) { index, candidate in
                            Button {
                                addAverageLink(from: entity.id, linkedID: candidate.id)
                            } label: {
                                HStack(spacing: 8) {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(candidate.name)
                                            .foregroundStyle(.primary)
                                        Text(averageEntitySecondaryText(candidate))
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer(minLength: 8)
                                    Image(systemName: "plus.circle")
                                        .foregroundStyle(PerchHATheme.accent)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.vertical, 6)
                            }
                            .buttonStyle(.plain)
                            if index < candidates.count - 1 {
                                Divider()
                            }
                        }
                    }
                }
                .frame(width: 320, height: 220)
            }
        }
        .padding(12)
        .frame(width: 344)
    }

    private func filteredAverageCandidates(for entity: DiscoveredEntity) -> [DiscoveredEntity] {
        let query = averagePickerSearchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let candidates = model.averageCandidateEntities(for: entity.id)
        guard !query.isEmpty else {
            return candidates
        }
        return candidates.filter { candidate in
            averageSearchFields(for: candidate).contains { field in
                field.localizedCaseInsensitiveContains(query)
            }
        }
    }

    private func averageSearchFields(for entity: DiscoveredEntity) -> [String] {
        var fields: [String] = [entity.name, entity.id.rawValue]
        fields.append(contentsOf: [entity.deviceName, entity.deviceModel, entity.deviceManufacturer].compactMap { value in
            guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else {
                return nil
            }
            return value
        })
        return fields
    }

    private func averageEntitySecondaryText(_ entity: DiscoveredEntity) -> String {
        let unit = entity.unit?.trimmingCharacters(in: .whitespacesAndNewlines)
        let context = entity.deviceName?.trimmingCharacters(in: .whitespacesAndNewlines)
        let parts: [String] = [context, unit].compactMap { value in
            guard let value, !value.isEmpty else {
                return nil
            }
            return value
        }
        return parts.isEmpty ? entity.id.rawValue : parts.joined(separator: " · ")
    }

    private func addAverageLink(from id: EntityID, linkedID: EntityID) {
        let next = model.averageLinkedEntityIDs(for: id) + [linkedID]
        if model.setAverageLinkedEntityIDs(id, linkedEntityIDs: next) {
            averagePickerSearchText = ""
        }
    }

    private func removeAverageLink(from id: EntityID, linkedID: EntityID) {
        let next = model.averageLinkedEntityIDs(for: id).filter { $0 != linkedID }
        _ = model.setAverageLinkedEntityIDs(id, linkedEntityIDs: next)
    }

    /// The entity's icon picker: the custom SF Symbol used everywhere this
    /// value appears (dashboard row and menu bar), or Automatic for the
    /// domain-derived symbol.
    private func entityIconPicker(
        for entity: DiscoveredEntity,
        configuration: MenuBarItemConfiguration
    ) -> some View {
        Menu {
            Button {
                model.setCustomEntityIcon(entity.id, symbolName: nil)
            } label: {
                Label("Automatic", systemImage: perchHAEntityIconName(for: entity))
            }
            ForEach(PerchHAEntityIconCatalog.sections, id: \.title) { section in
                Section(section.title) {
                    ForEach(section.symbols, id: \.self) { symbol in
                        Button {
                            model.setCustomEntityIcon(entity.id, symbolName: symbol)
                        } label: {
                            Label(symbol, systemImage: symbol)
                        }
                    }
                }
            }
        } label: {
            Label(
                configuration.customIconName ?? "Automatic",
                systemImage: configuration.customIconName ?? perchHAEntityIconName(for: entity)
            )
        }
        .fixedSize()
        .accessibilityLabel("\(entity.name) icon, currently \(configuration.customIconName ?? "automatic")")
    }

    /// Menu bar section: whether the entity is shown in the menu bar and its
    /// position there.
    private func menuBarSectionControls(for entity: DiscoveredEntity, isPromoted: Bool) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Toggle("Show in menu bar", isOn: menuBarVisibilityBinding(for: entity.id))
                    .fixedSize()
                    .accessibilityLabel("Show \(entity.name) in menu bar")
                if isPromoted {
                    menuBarMoveButtons(for: entity)
                }
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if isPromoted {
                HStack(spacing: 12) {
                    Toggle("Show icon", isOn: entityIconVisibilityBinding(for: entity.id))
                        .fixedSize()
                        .accessibilityLabel("Show \(entity.name) icon in the menu bar")
                    Toggle("Show label", isOn: menuBarLabelBinding(for: entity.id))
                        .fixedSize()
                        .accessibilityLabel("Show \(entity.name) label in menu bar")
                    Toggle("Show unit", isOn: menuBarUnitBinding(for: entity.id))
                        .fixedSize()
                        .accessibilityLabel("Show \(entity.name) unit in menu bar")
                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// A label-column row with right-aligned trailing controls, used for the
    /// aligned settings layout.
    private func settingsControlRow<Trailing: View>(
        _ label: String,
        @ViewBuilder trailing: () -> Trailing
    ) -> some View {
        HStack(spacing: 10) {
            Text(label)
                .foregroundStyle(.secondary)
            Spacer(minLength: 8)
            trailing()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func unitDisplayControls(
        for entity: DiscoveredEntity,
        configuration: MenuBarItemConfiguration
    ) -> some View {
        let detected = EntityDisplayDefaults.detectedUnit(for: entity)
        let detectedLabel = detectedUnitLabel(for: entity, detected: detected)
        let effectiveUnit = configuration.displayUnit ?? detected
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text("Unit")
                    .foregroundStyle(.secondary)
                Menu {
                    Button("Detected · \(detectedLabel)") {
                        model.setDisplayUnit(entity.id, displayUnit: nil, displayUnitSymbol: nil)
                    }
                    Divider()
                    ForEach(unitSelectionGroups(for: entity), id: \.title) { group in
                        Menu(group.title) {
                            ForEach(group.options, id: \.title) { option in
                                Button(option.title) {
                                    model.setDisplayUnit(
                                        entity.id,
                                        displayUnit: option.displayUnit,
                                        displayUnitSymbol: option.displayUnitSymbol
                                    )
                                }
                            }
                        }
                    }
                } label: {
                    HStack(spacing: 6) {
                        Text(unitSelectionTitle(for: entity, configuration: configuration, detectedLabel: detectedLabel))
                            .lineLimit(1)
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.system(size: 9, weight: .semibold))
                    }
                    .frame(width: 160, alignment: .leading)
                }
                .menuStyle(.borderlessButton)
                .accessibilityLabel("\(entity.name) unit")
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if effectiveUnit.usesNormalizedFraction {
                HStack(spacing: 8) {
                    Text("Min")
                        .foregroundStyle(.secondary)
                    TextField("0", text: displayMinBinding(for: entity.id))
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 64)
                        .accessibilityLabel("\(entity.name) minimum value")
                    Text("Max")
                        .foregroundStyle(.secondary)
                    TextField("100", text: displayMaxBinding(for: entity.id))
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 64)
                        .accessibilityLabel("\(entity.name) maximum value")
                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func detectedUnitLabel(for entity: DiscoveredEntity, detected: ValueUnit) -> String {
        if detected != .number {
            return detected.displayName
        }
        let trimmedUnit = entity.unit?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !trimmedUnit.isEmpty {
            return trimmedUnit
        }
        let trimmedState = entity.state.trimmingCharacters(in: .whitespacesAndNewlines)
        return Double(trimmedState) == nil ? "String" : detected.displayName
    }

    private struct UnitSelectionOption: Equatable {
        let title: String
        let displayUnit: ValueUnit
        let displayUnitSymbol: String?
    }

    private struct UnitSelectionGroup: Equatable {
        let title: String
        let options: [UnitSelectionOption]
    }

    private func unitSelectionTitle(
        for entity: DiscoveredEntity,
        configuration: MenuBarItemConfiguration,
        detectedLabel: String
    ) -> String {
        if let selectedOption = selectedUnitSelectionOption(for: entity, configuration: configuration) {
            return selectedOption.title
        }
        if let symbol = configuration.displayUnitSymbol {
            return symbol
        }
        if let displayUnit = configuration.displayUnit {
            return displayUnit.displayName
        }
        return "Detected · \(detectedLabel)"
    }

    private func unitSelectionGroups(for entity: DiscoveredEntity) -> [UnitSelectionGroup] {
        let detected = EntityDisplayDefaults.detectedUnit(for: entity)
        let trimmedUnit = entity.unit?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let hasUnit = !trimmedUnit.isEmpty
        var groups: [UnitSelectionGroup] = []

        groups.append(
            UnitSelectionGroup(
                title: "General",
                options: [
                    UnitSelectionOption(title: "Number", displayUnit: .number, displayUnitSymbol: nil),
                    UnitSelectionOption(title: "Compact (SI)", displayUnit: .compact, displayUnitSymbol: nil),
                    UnitSelectionOption(title: "Percent", displayUnit: .percent, displayUnitSymbol: nil),
                    UnitSelectionOption(title: "Duration", displayUnit: .duration, displayUnitSymbol: nil),
                    UnitSelectionOption(title: "Illuminance (lx)", displayUnit: .illuminance, displayUnitSymbol: hasUnit ? "lx" : nil),
                    UnitSelectionOption(title: "Bytes", displayUnit: .bytes, displayUnitSymbol: nil),
                    UnitSelectionOption(title: "Data rate", displayUnit: .dataRate, displayUnitSymbol: nil)
                ]
            )
        )
        groups.append(
            UnitSelectionGroup(
                title: "Temperature",
                options: [
                    UnitSelectionOption(title: "Celsius", displayUnit: .celsius, displayUnitSymbol: nil),
                    UnitSelectionOption(title: "Fahrenheit", displayUnit: .fahrenheit, displayUnitSymbol: nil),
                    UnitSelectionOption(title: "Kelvin", displayUnit: .kelvin, displayUnitSymbol: nil)
                ]
            )
        )
        groups.append(
            UnitSelectionGroup(
                title: "Icons",
                options: [
                    UnitSelectionOption(title: "Battery icon", displayUnit: .batteryIcon, displayUnitSymbol: nil),
                    UnitSelectionOption(title: "Signal icon", displayUnit: .signalIcon, displayUnitSymbol: nil),
                    UnitSelectionOption(title: "Sound icon", displayUnit: .soundIcon, displayUnitSymbol: nil),
                    UnitSelectionOption(title: "Brightness icon", displayUnit: .brightnessIcon, displayUnitSymbol: nil),
                    UnitSelectionOption(title: "Thermometer icon", displayUnit: .thermometerIcon, displayUnitSymbol: nil)
                ]
            )
        )

        let scaledGroups: [UnitSelectionGroup] = [
            unitScaleGroup(title: "Power", displayUnit: .power, symbols: ["nW", "µW", "mW", "W", "kW", "MW", "GW"]),
            unitScaleGroup(title: "Energy", displayUnit: .energy, symbols: ["nWh", "µWh", "mWh", "Wh", "kWh", "MWh", "GWh"]),
            unitScaleGroup(title: "Current", displayUnit: .number, symbols: ["nA", "µA", "mA", "A", "kA", "MA", "GA"]),
            unitScaleGroup(title: "Voltage", displayUnit: .number, symbols: ["nV", "µV", "mV", "V", "kV", "MV", "GV"]),
            unitScaleGroup(title: "Frequency", displayUnit: .number, symbols: ["nHz", "µHz", "mHz", "Hz", "kHz", "MHz", "GHz"]),
            unitScaleGroup(title: "Volume", displayUnit: .number, symbols: ["nL", "µL", "mL", "L", "kL", "ML", "GL"]),
            unitScaleGroup(title: "Pressure", displayUnit: .number, symbols: ["nPa", "µPa", "mPa", "Pa", "hPa", "kPa", "MPa", "GPa"]),
            unitScaleGroup(title: "Storage", displayUnit: .bytes, symbols: ["B", "KB", "MB", "GB", "TB", "PB", "EB"]),
            unitScaleGroup(title: "Transfer rate", displayUnit: .dataRate, symbols: ["B/s", "KB/s", "MB/s", "GB/s", "TB/s", "PB/s"]),
            unitScaleGroup(title: "Concentration", displayUnit: .number, symbols: ["ng/m³", "µg/m³", "mg/m³", "g/m³", "kg/m³"]),
            unitScaleGroup(title: "Parts", displayUnit: .number, symbols: ["ppb", "ppm"])
        ]

        if detected == .number || hasUnit {
            groups.append(contentsOf: scaledGroups)
        }
        return groups
    }

    private func unitScaleGroup(title: String, displayUnit: ValueUnit, symbols: [String]) -> UnitSelectionGroup {
        UnitSelectionGroup(
            title: title,
            options: symbols.map { symbol in
                UnitSelectionOption(title: symbol, displayUnit: displayUnit, displayUnitSymbol: symbol)
            }
        )
    }

    private func selectedUnitSelectionOption(
        for entity: DiscoveredEntity,
        configuration: MenuBarItemConfiguration
    ) -> UnitSelectionOption? {
        unitSelectionGroups(for: entity).flatMap(\.options).first { option in
            option.displayUnit == configuration.displayUnit
                && option.displayUnitSymbol == configuration.displayUnitSymbol
        }
    }

    private func menuBarTotalControls(
        for entity: DiscoveredEntity,
        configuration: MenuBarItemConfiguration
    ) -> some View {
        let candidates = menuBarTotalCandidates(for: entity)
        return HStack(spacing: 8) {
            Picker("Total", selection: menuBarTotalModeBinding(for: entity.id)) {
                Text("No total").tag(MenuBarTotalMode.none)
                Text("Manual").tag(MenuBarTotalMode.absolute)
                if let totalEntityID = configuration.totalEntityID,
                   !candidates.contains(where: { $0.id == totalEntityID }) {
                    Text(totalEntityID.rawValue).tag(MenuBarTotalMode.entity(totalEntityID))
                }
                ForEach(candidates, id: \.id.rawValue) { candidate in
                    Text(candidate.name).tag(MenuBarTotalMode.entity(candidate.id))
                }
            }
            .frame(width: 132)
            .accessibilityLabel("\(entity.name) gauge total source")
            if configuration.absoluteTotal != nil {
                Stepper(
                    "Total \(menuBarNumberLabel(configuration.absoluteTotal))",
                    value: menuBarAbsoluteTotalBinding(for: entity.id),
                    in: 1...100_000,
                    step: 1
                )
                .accessibilityLabel("\(entity.name) manual gauge total")
            }
        }
    }

    private func menuBarThresholdControls(
        for entity: DiscoveredEntity,
        configuration: MenuBarItemConfiguration
    ) -> AnyView {
        guard entitySupportsNumericThresholdEditing(entity, configuration: configuration) else {
            return AnyView(semanticStateThresholdControls(for: entity))
        }
        let thresholds = EntityDisplayDefaults.effectiveThresholds(for: entity, configuration: configuration)
        let steps = thresholds.steps.sorted { $0.value > $1.value }
        let defaultThresholds = EntityDisplayDefaults.defaultThresholds(
            for: entity,
            selectedUnit: configuration.displayUnit
        )
        let hasThresholdDefaults = EntityDisplayDefaults.hasThresholds(defaultThresholds)
        return AnyView(VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Spacer(minLength: 0)
                if hasThresholdDefaults {
                    Button {
                        model.setThresholds(entity.id, thresholds: defaultThresholds)
                    } label: {
                        Label("Reset defaults", systemImage: "arrow.counterclockwise")
                            .labelStyle(.titleAndIcon)
                    }
                    .buttonStyle(PerchHAIconButtonStyle())
                    .disabled(thresholds == defaultThresholds)
                    .accessibilityLabel("Reset \(entity.name) threshold colors to defaults")
                }
                Button {
                    let highest = steps.first?.value ?? 0
                    updateThresholdSteps(for: entity.id, thresholds: thresholds) { next in
                        next.append(ThresholdStep(value: highest + 10, color: ValueThresholds.criticalColor))
                    }
                } label: {
                    Label("Add threshold", systemImage: "plus.circle.fill")
                        .labelStyle(.titleAndIcon)
                        .lineLimit(1)
                }
                .buttonStyle(PerchHAIconButtonStyle(prominentOnHover: true))
                .accessibilityLabel("Add threshold for \(entity.name)")
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            ForEach(Array(steps.enumerated()), id: \.offset) { index, step in
                thresholdStepRow(entity: entity, thresholds: thresholds, step: step, index: index)
            }

            // The Base row: the color below every step, like Grafana's Base.
            HStack(spacing: 8) {
                ColorPicker(
                    "Base color",
                    selection: thresholdBaseColorBinding(for: entity.id, thresholds: thresholds),
                    supportsOpacity: false
                )
                .labelsHidden()
                .frame(width: 34)
                .accessibilityLabel("\(entity.name) base threshold color")
                Text("Base")
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
                if thresholds.baseColor != nil {
                    Button {
                        setThresholdBaseColor(nil, for: entity.id, thresholds: thresholds)
                    } label: {
                        Image(systemName: "arrow.counterclockwise")
                            .frame(width: 18, height: 18)
                    }
                    .buttonStyle(PerchHACircularIconButtonStyle())
                    .controlSize(.small)
                    .help("Reset base to the default tint")
                    .accessibilityLabel("Reset \(entity.name) base threshold color")
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading))
    }

    private func entitySupportsNumericThresholdEditing(
        _ entity: DiscoveredEntity,
        configuration: MenuBarItemConfiguration
    ) -> Bool {
        if Double(entity.state.trimmingCharacters(in: .whitespacesAndNewlines)) != nil {
            return true
        }
        let thresholds = EntityDisplayDefaults.effectiveThresholds(for: entity, configuration: configuration)
        return EntityDisplayDefaults.hasThresholds(thresholds)
    }

    private func semanticStateThresholdControls(for entity: DiscoveredEntity) -> some View {
        let configuration = snapshot.effectiveMenuBarItemConfiguration(for: entity)
        let thresholds = EntityDisplayDefaults.effectiveStateThresholds(for: entity, configuration: configuration)
        let currentColor = EntityDisplayDefaults.semanticStateColor(
            for: entity.state,
            entity: entity,
            configuration: configuration
        )
        let hasDefaultThresholds = EntityDisplayDefaults.hasStateThresholds(
            EntityDisplayDefaults.defaultStateThresholds(for: entity)
        )
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Spacer(minLength: 0)
                if hasDefaultThresholds {
                    Button {
                        model.setStateThresholds(entity.id, thresholds: .inheritingDefaults)
                    } label: {
                        Label("Reset defaults", systemImage: "arrow.counterclockwise")
                            .labelStyle(.titleAndIcon)
                    }
                    .buttonStyle(PerchHAIconButtonStyle())
                    .disabled(configuration.stateThresholds.inheritsDefaults)
                    .accessibilityLabel("Reset \(entity.name) state threshold colors to defaults")
                }
                Button {
                    let currentState = entity.state.trimmingCharacters(in: .whitespacesAndNewlines)
                    let stem = currentState.isEmpty ? "match" : currentState.uppercased()
                    let existingMatches = Set(
                        thresholds.rules.map { $0.match.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
                    )
                    var nextMatch = stem
                    var suffix = 2
                    while existingMatches.contains(nextMatch.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()) {
                        nextMatch = "\(stem) \(suffix)"
                        suffix += 1
                    }
                    updateStateThresholdRules(for: entity.id, thresholds: thresholds) { next in
                        next.append(StateThresholdRule(match: nextMatch, color: ValueThresholds.warningColor))
                    }
                } label: {
                    Label("Add threshold", systemImage: "plus.circle.fill")
                        .labelStyle(.titleAndIcon)
                        .lineLimit(1)
                }
                .buttonStyle(PerchHAIconButtonStyle(prominentOnHover: true))
                .accessibilityLabel("Add state threshold for \(entity.name)")
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: 8) {
                semanticThresholdSwatch(currentColor)
                VStack(alignment: .leading, spacing: 2) {
                    Text(entity.state.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Current state" : entity.state)
                    Text("Current value")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
            ForEach(Array(thresholds.rules.enumerated()), id: \.offset) { index, rule in
                stateThresholdRuleRow(
                    entity: entity,
                    thresholds: thresholds,
                    rule: rule,
                    index: index
                )
            }
            HStack(spacing: 8) {
                ColorPicker(
                    "Base color",
                    selection: stateThresholdBaseColorBinding(for: entity.id, thresholds: thresholds),
                    supportsOpacity: false
                )
                .labelsHidden()
                .frame(width: 34)
                .accessibilityLabel("\(entity.name) base state threshold color")

                Text("Base")
                    .foregroundStyle(.secondary)

                Spacer(minLength: 0)

                if thresholds.baseColor != nil {
                    Button {
                        setStateThresholdBaseColor(nil, for: entity.id, thresholds: thresholds)
                    } label: {
                        Image(systemName: "arrow.counterclockwise")
                            .frame(width: 18, height: 18)
                    }
                    .buttonStyle(PerchHACircularIconButtonStyle())
                    .controlSize(.small)
                    .help("Reset base to automatic semantic fallback")
                    .accessibilityLabel("Reset \(entity.name) base state threshold color")
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func semanticThresholdSwatch(_ accent: PerchHAAccentColor) -> some View {
        RoundedRectangle(cornerRadius: 6, style: .continuous)
            .fill(PerchHATheme.color(for: accent))
            .frame(width: 28, height: 16)
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
            )
    }

    private func stateThresholdRuleRow(
        entity: DiscoveredEntity,
        thresholds: StateThresholds,
        rule: StateThresholdRule,
        index: Int
    ) -> some View {
        HStack(spacing: 8) {
            ColorPicker(
                "Threshold color",
                selection: stateThresholdRuleColorBinding(for: entity.id, thresholds: thresholds, rule: rule),
                supportsOpacity: false
            )
            .labelsHidden()
            .frame(width: 34)
            .accessibilityLabel("\(entity.name) state threshold \(index + 1) color")

            ThresholdMatchField(
                placeholder: "state",
                value: rule.match
            ) { newValue in
                guard !newValue.isEmpty else {
                    return
                }
                updateStateThresholdRules(for: entity.id, thresholds: thresholds) { next in
                    if let position = next.firstIndex(of: rule) {
                        next[position] = StateThresholdRule(match: newValue, color: rule.color)
                    }
                }
            }
            .frame(width: 120)
            .accessibilityLabel("\(entity.name) state threshold \(index + 1) match")

            Spacer(minLength: 0)

            Button {
                updateStateThresholdRules(for: entity.id, thresholds: thresholds) { next in
                    if let position = next.firstIndex(of: rule) {
                        next.remove(at: position)
                    }
                }
            } label: {
                Image(systemName: "trash")
                    .frame(width: 18, height: 18)
            }
            .buttonStyle(PerchHACircularIconButtonStyle())
            .controlSize(.small)
            .help("Delete threshold")
            .accessibilityLabel("Delete \(entity.name) state threshold \(index + 1)")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// One threshold step row, Grafana style: `[color well] >= [value] [delete]`.
    private func thresholdStepRow(
        entity: DiscoveredEntity,
        thresholds: ValueThresholds,
        step: ThresholdStep,
        index: Int
    ) -> some View {
        HStack(spacing: 8) {
            ColorPicker(
                "Threshold color",
                selection: thresholdStepColorBinding(for: entity.id, thresholds: thresholds, step: step),
                supportsOpacity: false
            )
            .labelsHidden()
            .frame(width: 34)
            .accessibilityLabel("\(entity.name) threshold \(index + 1) color")

            Text("\u{2265}")
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)

            ThresholdBoundField(
                placeholder: "value",
                value: step.value,
                onCommit: { newValue in
                    guard let newValue else {
                        return
                    }
                    updateThresholdSteps(for: entity.id, thresholds: thresholds) { next in
                        if let position = next.firstIndex(of: step) {
                            next[position] = ThresholdStep(value: newValue, color: step.color)
                        }
                    }
                }
            )
            .frame(width: 72)
            .accessibilityLabel("\(entity.name) threshold \(index + 1) value")

            Spacer(minLength: 0)

            Button {
                updateThresholdSteps(for: entity.id, thresholds: thresholds) { next in
                    if let position = next.firstIndex(of: step) {
                        next.remove(at: position)
                    }
                }
            } label: {
                Image(systemName: "trash")
                    .frame(width: 18, height: 18)
            }
            .buttonStyle(PerchHACircularIconButtonStyle())
            .controlSize(.small)
            .help("Delete threshold")
            .accessibilityLabel("Delete \(entity.name) threshold \(index + 1)")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func thresholdStepColorBinding(
        for id: EntityID,
        thresholds: ValueThresholds,
        step: ThresholdStep
    ) -> Binding<Color> {
        Binding(
            get: {
                PerchHATheme.color(for: step.color)
            },
            set: { newColor in
                guard let accent = accentColor(from: newColor) else {
                    return
                }
                updateThresholdSteps(for: id, thresholds: thresholds) { next in
                    if let position = next.firstIndex(of: step) {
                        next[position] = ThresholdStep(value: step.value, color: accent)
                    }
                }
            }
        )
    }

    private func thresholdBaseColorBinding(
        for id: EntityID,
        thresholds: ValueThresholds
    ) -> Binding<Color> {
        Binding(
            get: {
                thresholds.baseColor.map(PerchHATheme.color(for:)) ?? PerchHATheme.accent
            },
            set: { newColor in
                guard let accent = accentColor(from: newColor) else {
                    return
                }
                setThresholdBaseColor(accent, for: id, thresholds: thresholds)
            }
        )
    }

    private func stateThresholdRuleColorBinding(
        for id: EntityID,
        thresholds: StateThresholds,
        rule: StateThresholdRule
    ) -> Binding<Color> {
        Binding(
            get: {
                PerchHATheme.color(for: rule.color)
            },
            set: { newColor in
                guard let accent = accentColor(from: newColor) else {
                    return
                }
                updateStateThresholdRules(for: id, thresholds: thresholds) { next in
                    if let position = next.firstIndex(of: rule) {
                        next[position] = StateThresholdRule(match: rule.match, color: accent)
                    }
                }
            }
        )
    }

    private func stateThresholdBaseColorBinding(
        for id: EntityID,
        thresholds: StateThresholds
    ) -> Binding<Color> {
        Binding(
            get: {
                thresholds.baseColor.map(PerchHATheme.color(for:)) ?? PerchHATheme.accent
            },
            set: { newColor in
                guard let accent = accentColor(from: newColor) else {
                    return
                }
                setStateThresholdBaseColor(accent, for: id, thresholds: thresholds)
            }
        )
    }

    private func accentColor(from color: Color) -> PerchHAAccentColor? {
        PerchHAAccentColor(color)
    }

    private func updateThresholdSteps(
        for id: EntityID,
        thresholds: ValueThresholds,
        _ update: (inout [ThresholdStep]) -> Void
    ) {
        var next = thresholds.steps
        update(&next)
        model.setThresholds(id, thresholds: ValueThresholds(steps: next, baseColor: thresholds.baseColor))
    }

    private func setThresholdBaseColor(
        _ baseColor: PerchHAAccentColor?,
        for id: EntityID,
        thresholds: ValueThresholds
    ) {
        model.setThresholds(id, thresholds: ValueThresholds(steps: thresholds.steps, baseColor: baseColor))
    }

    private func updateStateThresholdRules(
        for id: EntityID,
        thresholds: StateThresholds,
        _ update: (inout [StateThresholdRule]) -> Void
    ) {
        var next = thresholds.rules
        update(&next)
        model.setStateThresholds(id, thresholds: StateThresholds(rules: next, baseColor: thresholds.baseColor))
    }

    private func setStateThresholdBaseColor(
        _ baseColor: PerchHAAccentColor?,
        for id: EntityID,
        thresholds: StateThresholds
    ) {
        model.setStateThresholds(id, thresholds: StateThresholds(rules: thresholds.rules, baseColor: baseColor))
    }

    private func menuBarMoveButtons(for entity: DiscoveredEntity) -> some View {
        let promotedIDs = model.snapshot.menuBarDisplayConfiguration.promotedEntityIDs
        let index = promotedIDs.firstIndex(of: entity.id)
        let canMoveUp = canReorderSelection && (index.map { $0 > promotedIDs.startIndex } ?? false)
        let canMoveDown = canReorderSelection && (index.map { $0 < promotedIDs.index(before: promotedIDs.endIndex) } ?? false)
        return HStack(spacing: 2) {
            Button {
                model.moveMenuBarEntity(entity.id, direction: .up)
            } label: {
                Image(systemName: "arrow.up.to.line")
                    .frame(width: 18, height: 18)
            }
            .buttonStyle(PerchHACircularIconButtonStyle())
            .controlSize(.small)
            .disabled(!canMoveUp)
            .help(menuBarMoveHelp(canMove: canMoveUp, boundaryReason: "Already first in menu bar"))
            .accessibilityLabel("Move \(entity.name) earlier in menu bar")
            .accessibilityHint(menuBarMoveHelp(canMove: canMoveUp, boundaryReason: "Already first in menu bar"))

            Button {
                model.moveMenuBarEntity(entity.id, direction: .down)
            } label: {
                Image(systemName: "arrow.down.to.line")
                    .frame(width: 18, height: 18)
            }
            .buttonStyle(PerchHACircularIconButtonStyle())
            .controlSize(.small)
            .disabled(!canMoveDown)
            .help(menuBarMoveHelp(canMove: canMoveDown, boundaryReason: "Already last in menu bar"))
            .accessibilityLabel("Move \(entity.name) later in menu bar")
            .accessibilityHint(menuBarMoveHelp(canMove: canMoveDown, boundaryReason: "Already last in menu bar"))
        }
    }

    private func menuBarMoveHelp(canMove: Bool, boundaryReason: String) -> String {
        model.snapshot.menuBarReorderAccessibilityHint(canMove: canMove, boundaryReason: boundaryReason)
    }

    @ViewBuilder
    private func selectionDragDrop<Row: View>(_ row: Row, item: SelectionDragItem) -> some View {
        if canReorderSelection {
            row
                .onDrag {
                    selectionDragProvider(item)
                }
                .onDrop(of: [.text], isTargeted: nil) { _ in
                    applySelectionDrop(onto: item)
                }
        } else {
            row
        }
    }

    private func selectionDragProvider(_ item: SelectionDragItem) -> NSItemProvider {
        draggedSelectionItem = item
        return NSItemProvider(object: item.providerText as NSString)
    }

    private func applySelectionDrop(onto target: SelectionDragItem) -> Bool {
        guard canReorderSelection, let draggedSelectionItem, draggedSelectionItem != target else {
            self.draggedSelectionItem = nil
            return false
        }
        defer {
            self.draggedSelectionItem = nil
        }

        switch SelectionDropTranslator().translate(source: draggedSelectionItem, target: target, tree: settingsTree) {
        case let .room(sourceID, targetID, placement):
            return model.moveRoom(sourceID, relativeTo: targetID, placement: placement)
        case let .entity(sourceID, targetID, placement):
            return model.moveEntity(sourceID, relativeTo: targetID, placement: placement)
        case .unsupported:
            return false
        }
    }

    private func selectionMoveButtons(
        up: @escaping () -> Void,
        down: @escaping () -> Void,
        upLabel: String,
        downLabel: String,
        canMoveUp: Bool,
        canMoveDown: Bool
    ) -> some View {
        HStack(spacing: 2) {
            Button(action: up) {
                Image(systemName: "chevron.up")
                    .frame(width: 18, height: 18)
            }
            .buttonStyle(PerchHACircularIconButtonStyle())
            .controlSize(.small)
            .disabled(!canMoveUp)
            .help(moveControlHelp(canMove: canMoveUp, boundaryReason: "Already first"))
            .accessibilityLabel(upLabel)
            .accessibilityHint(moveControlHelp(canMove: canMoveUp, boundaryReason: "Already first"))

            Button(action: down) {
                Image(systemName: "chevron.down")
                    .frame(width: 18, height: 18)
            }
            .buttonStyle(PerchHACircularIconButtonStyle())
            .controlSize(.small)
            .disabled(!canMoveDown)
            .help(moveControlHelp(canMove: canMoveDown, boundaryReason: "Already last"))
            .accessibilityLabel(downLabel)
            .accessibilityHint(moveControlHelp(canMove: canMoveDown, boundaryReason: "Already last"))
        }
    }

    private func moveControlHelp(canMove: Bool, boundaryReason: String) -> String {
        model.snapshot.selectionReorderAccessibilityHint(canMove: canMove, boundaryReason: boundaryReason)
    }

    /// The Entities search binding. The field edits view-local state so every
    /// keystroke stays instant; the model (whose query change rebuilds the whole
    /// snapshot and re-renders every subscriber, including the open panel) is
    /// updated after a short debounce instead of per keypress.
    private var selectionSearchBinding: Binding<String> {
        Binding(
            get: {
                entitySearchText
            },
            set: { value in
                entitySearchText = value
                searchDebounceTask?.cancel()
                searchDebounceTask = Task { @MainActor in
                    try? await Task.sleep(nanoseconds: 200_000_000)
                    guard !Task.isCancelled else {
                        return
                    }
                    model.updateSelectionQuery(value)
                }
            }
        )
    }

    private func selectionBinding(for id: EntityID) -> Binding<Bool> {
        Binding(
            get: {
                if !model.snapshot.selectionConfiguration.isExplicit {
                    return true
                }
                return model.snapshot.selectionConfiguration.selectedEntityIDs.contains(id)
            },
            set: { isSelected in
                model.setEntity(id, isSelected: isSelected)
            }
        )
    }

    private func menuBarVisibilityBinding(for id: EntityID) -> Binding<Bool> {
        Binding(
            get: {
                snapshot.menuBarDisplayConfiguration.isPromoted(id)
            },
            set: { isVisible in
                model.setMenuBarEntity(id, isVisible: isVisible)
            }
        )
    }

    private func menuBarItemConfiguration(for id: EntityID) -> MenuBarItemConfiguration {
        snapshot.menuBarDisplayConfiguration.itemConfiguration(for: id)
    }

    private func menuBarItemBinding<Value>(
        for id: EntityID,
        get: @escaping (MenuBarItemConfiguration) -> Value,
        set: @escaping (EntityID, Value) -> Bool
    ) -> Binding<Value> {
        Binding(
            get: {
                get(menuBarItemConfiguration(for: id))
            },
            set: { value in
                _ = set(id, value)
            }
        )
    }

    private func menuBarStyleBinding(for id: EntityID) -> Binding<MenuBarDisplayStyle> {
        menuBarItemBinding(for: id, get: \.style, set: model.setMenuBarDisplayStyle)
    }

    /// The per-entity menu-bar appearance binding. Reads the per-entity override
    /// when set, otherwise the global default; writing always sets a per-entity
    /// override so the choice wins over the global default for this entity.
    private func menuBarItemAppearanceBinding(for id: EntityID) -> Binding<PerchHAMenuBarAppearance> {
        Binding(
            get: {
                menuBarItemConfiguration(for: id).appearance
                    ?? displayPreferences.menuBarAppearance
            },
            set: { appearance in
                model.setMenuBarAppearance(id, appearance: appearance)
            }
        )
    }

    private func coverControlModeBinding(for id: EntityID) -> Binding<CoverControlMode> {
        menuBarItemBinding(for: id, get: \.coverControlMode, set: model.setCoverControlMode)
    }

    private func displayUnitBinding(for id: EntityID) -> Binding<ValueUnit?> {
        Binding(
            get: {
                menuBarItemConfiguration(for: id).displayUnit
            },
            set: { unit in
                model.setDisplayUnit(id, displayUnit: unit)
            }
        )
    }

    private func displayMinBinding(for id: EntityID) -> Binding<String> {
        Binding(
            get: {
                menuBarItemConfiguration(for: id).minValue
                    .map { PerchHABoundsField.text(for: $0) } ?? ""
            },
            set: { text in
                let configuration = menuBarItemConfiguration(for: id)
                model.setDisplayBounds(id, minValue: PerchHABoundsField.value(from: text), maxValue: configuration.maxValue)
            }
        )
    }

    private func displayMaxBinding(for id: EntityID) -> Binding<String> {
        Binding(
            get: {
                menuBarItemConfiguration(for: id).maxValue
                    .map { PerchHABoundsField.text(for: $0) } ?? ""
            },
            set: { text in
                let configuration = menuBarItemConfiguration(for: id)
                model.setDisplayBounds(id, minValue: configuration.minValue, maxValue: PerchHABoundsField.value(from: text))
            }
        )
    }

    private func menuBarLabelBinding(for id: EntityID) -> Binding<Bool> {
        menuBarItemBinding(for: id, get: \.showsLabel, set: model.setMenuBarShowsLabel)
    }

    private func menuBarUnitBinding(for id: EntityID) -> Binding<Bool> {
        menuBarItemBinding(for: id, get: \.showsUnit, set: model.setMenuBarShowsUnit)
    }

    private func menuBarDecimalsBinding(for id: EntityID) -> Binding<Int> {
        menuBarItemBinding(for: id, get: \.maximumFractionDigits, set: model.setMenuBarMaximumFractionDigits)
    }

    private func menuBarHistoryRangeBinding(for id: EntityID) -> Binding<HistoryRange?> {
        menuBarItemBinding(for: id, get: \.defaultHistoryRange, set: model.setMenuBarDefaultHistoryRange)
    }

    private func menuBarTotalModeBinding(for id: EntityID) -> Binding<MenuBarTotalMode> {
        Binding(
            get: {
                let configuration = menuBarItemConfiguration(for: id)
                if let totalEntityID = configuration.totalEntityID {
                    return .entity(totalEntityID)
                }
                if configuration.absoluteTotal != nil {
                    return .absolute
                }
                return .none
            },
            set: { mode in
                let configuration = menuBarItemConfiguration(for: id)
                switch mode {
                case .none:
                    model.setMenuBarTotalEntityID(id, totalEntityID: nil)
                case .absolute:
                    model.setMenuBarAbsoluteTotal(id, total: configuration.absoluteTotal ?? 100)
                case let .entity(totalEntityID):
                    model.setMenuBarTotalEntityID(id, totalEntityID: totalEntityID)
                }
            }
        )
    }

    private func menuBarAbsoluteTotalBinding(for id: EntityID) -> Binding<Double> {
        menuBarItemBinding(
            for: id,
            get: { $0.absoluteTotal ?? 100 },
            set: { id, total in
                model.setMenuBarAbsoluteTotal(id, total: max(1, total))
            }
        )
    }

    private func menuBarTotalCandidates(for source: DiscoveredEntity) -> [DiscoveredEntity] {
        model.snapshot.availableRooms
            .flatMap(\.entities)
            .filter { entity in
                entity.id != source.id
                    && menuBarNumericState(entity.state) != nil
                    && menuBarUnitsAreCompatible(source.unit, entity.unit)
            }
    }

    private func menuBarCanUseGaugeTotal(for entity: DiscoveredEntity) -> Bool {
        menuBarNumericState(entity.state) != nil && !menuBarIsPercentUnit(entity.unit)
    }

    private func menuBarNumericState(_ state: String) -> Double? {
        Double(state.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    private func menuBarIsPercentUnit(_ unit: String?) -> Bool {
        menuBarNormalizedUnit(unit) == "%"
    }

    private func menuBarUnitsAreCompatible(_ sourceUnit: String?, _ totalUnit: String?) -> Bool {
        menuBarNormalizedUnit(sourceUnit) == menuBarNormalizedUnit(totalUnit)
    }

    private func menuBarNormalizedUnit(_ unit: String?) -> String? {
        let trimmed = unit?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let trimmed, !trimmed.isEmpty else {
            return nil
        }
        return trimmed
    }

}

/// A grouped count of entities sharing one unhealthy status, for the
/// Diagnostics entity-health summary.
private struct EntityHealthGroup {
    let label: String
    let count: Int
    let systemImage: String
}

/// A deduped, capped report of unhealthy visible entities for Diagnostics.
///
/// `warningCount` matches the dashboard summary's count of
/// unavailable/unknown/stale values. `visibleGroups` is capped so a large fleet
/// shows a short summary; `hiddenCount` carries the remainder behind an "and N
/// more" affordance.
private struct EntityHealthReport {
    let totalVisible: Int
    let warningCount: Int
    let visibleGroups: [EntityHealthGroup]
    let hiddenCount: Int
}

/// Locale-independent parsing and display for the per-entity min/max bound
/// fields. Empty or unparsable text clears the bound.
private enum PerchHABoundsField {
    static func value(from text: String) -> Double? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return nil
        }
        return Double(trimmed)
    }

    static func text(for value: Double) -> String {
        value == value.rounded() ? String(Int(value)) : String(value)
    }
}

/// The curated SF Symbol catalog offered by the per-entity dashboard icon
/// picker, grouped by home-automation theme. Symbols are limited to names
/// available on macOS 13 so a picked icon always renders.
public enum PerchHAEntityIconCatalog {
    /// One themed group of the picker.
    public struct Section: Sendable {
        public let title: String
        public let symbols: [String]
    }

    /// The picker's sections, in display order.
    public static let sections: [Section] = [
        Section(title: "Climate", symbols: [
            "thermometer.medium", "thermometer.sun", "thermometer.snowflake", "humidity",
            "wind", "snowflake", "flame", "drop", "drop.degreesign", "sun.max", "moon", "cloud.rain"
        ]),
        Section(title: "Energy & power", symbols: [
            "bolt", "bolt.fill", "bolt.circle", "bolt.slash", "battery.100", "battery.50",
            "battery.25", "powerplug", "poweroutlet.type.f", "gauge.with.dots.needle.67percent", "leaf", "ev.charger"
        ]),
        Section(title: "Lights & switches", symbols: [
            "lightbulb", "lightbulb.fill", "lightbulb.2", "lamp.desk", "lamp.floor",
            "lamp.ceiling", "light.recessed", "switch.2", "togglepower", "dial.low", "dial.high"
        ]),
        Section(title: "Security & access", symbols: [
            "lock", "lock.open", "lock.shield", "key", "shield", "shield.checkered",
            "eye", "video", "bell", "bell.badge", "exclamationmark.triangle", "hand.raised"
        ]),
        Section(title: "Doors, windows & covers", symbols: [
            "door.left.hand.closed", "door.left.hand.open", "door.garage.closed", "door.garage.open",
            "window.vertical.closed", "window.vertical.open", "blinds.vertical.closed", "blinds.horizontal.closed",
            "curtains.closed", "curtains.open"
        ]),
        Section(title: "Rooms & appliances", symbols: [
            "sofa", "bed.double", "bathtub", "shower", "toilet", "refrigerator", "oven",
            "microwave", "dishwasher", "washer", "dryer", "stove", "sink", "chair.lounge"
        ]),
        Section(title: "Media & network", symbols: [
            "tv", "hifispeaker", "homepod", "music.note", "speaker.wave.2", "wifi",
            "wifi.router", "antenna.radiowaves.left.and.right", "network", "server.rack", "externaldrive", "printer"
        ]),
        Section(title: "Motion & presence", symbols: [
            "figure.walk", "figure.run", "person", "person.2", "person.3", "pawprint",
            "car", "bicycle", "location", "map", "house", "building.2"
        ]),
        Section(title: "Measurements", symbols: [
            "gauge.medium", "speedometer", "chart.line.uptrend.xyaxis", "chart.bar", "waveform.path.ecg",
            "timer", "clock", "calendar", "number", "percent", "ruler", "scalemass"
        ]),
        Section(title: "General", symbols: [
            "sensor.tag.radiowaves.forward", "dot.radiowaves.left.and.right", "cpu", "memorychip",
            "fanblades", "sparkles", "star", "heart", "checkmark.circle", "xmark.circle", "questionmark.circle", "info.circle"
        ])
    ]

    /// Every symbol in the catalog, flattened in section order.
    public static var allSymbols: [String] {
        sections.flatMap(\.symbols)
    }
}

/// A numeric threshold bound editor: commits on Return or focus loss, an empty
/// field means an open bound, and non-numeric input restores the prior value.
struct ThresholdBoundField: View {
    let placeholder: String
    let value: Double?
    let onCommit: (Double?) -> Void

    @State private var text: String = ""
    @FocusState private var isFocused: Bool

    var body: some View {
        TextField(placeholder, text: $text)
            .textFieldStyle(.roundedBorder)
            .multilineTextAlignment(.trailing)
            .focused($isFocused)
            .onAppear {
                text = Self.label(for: value)
            }
            .onChange(of: value) { newValue in
                if !isFocused {
                    text = Self.label(for: newValue)
                }
            }
            .onSubmit(commit)
            .onChange(of: isFocused) { focused in
                if !focused {
                    commit()
                }
            }
    }

    private func commit() {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            onCommit(nil)
            return
        }
        let normalized = trimmed.replacingOccurrences(of: ",", with: ".")
        if let parsed = Double(normalized) {
            onCommit(parsed)
        } else {
            text = Self.label(for: value)
        }
    }

    private static func label(for value: Double?) -> String {
        guard let value else {
            return ""
        }
        if value == value.rounded() && abs(value) < 1_000_000_000 {
            return String(Int(value))
        }
        return String(value)
    }
}

/// A text editor for non-numeric threshold matches. Empty or whitespace-only
/// edits revert to the prior stored match instead of creating a blank rule.
struct ThresholdMatchField: View {
    let placeholder: String
    let value: String
    let onCommit: (String) -> Void

    @State private var text: String = ""
    @FocusState private var isFocused: Bool

    var body: some View {
        TextField(placeholder, text: $text)
            .textFieldStyle(.roundedBorder)
            .focused($isFocused)
            .onAppear {
                text = value
            }
            .onChange(of: value) { newValue in
                if !isFocused {
                    text = newValue
                }
            }
            .onSubmit(commit)
            .onChange(of: isFocused) { focused in
                if !focused {
                    commit()
                }
            }
    }

    private func commit() {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            text = value
            return
        }
        text = trimmed
        onCommit(trimmed)
    }
}

/// The fill outline of one room-card segment: a rectangle whose top and/or
/// bottom corners round to the card radius, so first/middle/last rows tile
/// into a single card silhouette.
struct SelectionRoomSegmentShape: Shape {
    let radius: CGFloat
    let roundsTop: Bool
    let roundsBottom: Bool

    func path(in rect: CGRect) -> Path {
        let topRadius = roundsTop ? min(radius, min(rect.width, rect.height) / 2) : 0
        let bottomRadius = roundsBottom ? min(radius, min(rect.width, rect.height) / 2) : 0
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.maxY - bottomRadius))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + topRadius))
        if topRadius > 0 {
            path.addArc(
                center: CGPoint(x: rect.minX + topRadius, y: rect.minY + topRadius),
                radius: topRadius,
                startAngle: .degrees(180),
                endAngle: .degrees(270),
                clockwise: false
            )
        }
        path.addLine(to: CGPoint(x: rect.maxX - topRadius, y: rect.minY))
        if topRadius > 0 {
            path.addArc(
                center: CGPoint(x: rect.maxX - topRadius, y: rect.minY + topRadius),
                radius: topRadius,
                startAngle: .degrees(270),
                endAngle: .degrees(0),
                clockwise: false
            )
        }
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - bottomRadius))
        if bottomRadius > 0 {
            path.addArc(
                center: CGPoint(x: rect.maxX - bottomRadius, y: rect.maxY - bottomRadius),
                radius: bottomRadius,
                startAngle: .degrees(0),
                endAngle: .degrees(90),
                clockwise: false
            )
        }
        path.addLine(to: CGPoint(x: rect.minX + bottomRadius, y: rect.maxY))
        if bottomRadius > 0 {
            path.addArc(
                center: CGPoint(x: rect.minX + bottomRadius, y: rect.maxY - bottomRadius),
                radius: bottomRadius,
                startAngle: .degrees(90),
                endAngle: .degrees(180),
                clockwise: false
            )
        }
        path.closeSubpath()
        return path
    }
}

/// The stroked border of one room-card segment: always the two side edges,
/// plus the top edge (with corners) on the first row and the bottom edge on
/// the last, so joints between stacked segments never draw a horizontal line
/// through the card.
struct SelectionRoomSegmentBorderShape: Shape {
    let radius: CGFloat
    let roundsTop: Bool
    let roundsBottom: Bool

    func path(in rect: CGRect) -> Path {
        let topRadius = roundsTop ? min(radius, min(rect.width, rect.height) / 2) : 0
        let bottomRadius = roundsBottom ? min(radius, min(rect.width, rect.height) / 2) : 0
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.maxY - bottomRadius))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + topRadius))
        if roundsTop {
            path.addArc(
                center: CGPoint(x: rect.minX + topRadius, y: rect.minY + topRadius),
                radius: topRadius,
                startAngle: .degrees(180),
                endAngle: .degrees(270),
                clockwise: false
            )
            path.addLine(to: CGPoint(x: rect.maxX - topRadius, y: rect.minY))
            path.addArc(
                center: CGPoint(x: rect.maxX - topRadius, y: rect.minY + topRadius),
                radius: topRadius,
                startAngle: .degrees(270),
                endAngle: .degrees(0),
                clockwise: false
            )
        } else {
            path.move(to: CGPoint(x: rect.maxX, y: rect.minY))
        }
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - bottomRadius))
        if roundsBottom {
            path.addArc(
                center: CGPoint(x: rect.maxX - bottomRadius, y: rect.maxY - bottomRadius),
                radius: bottomRadius,
                startAngle: .degrees(0),
                endAngle: .degrees(90),
                clockwise: false
            )
            path.addLine(to: CGPoint(x: rect.minX + bottomRadius, y: rect.maxY))
            path.addArc(
                center: CGPoint(x: rect.minX + bottomRadius, y: rect.maxY - bottomRadius),
                radius: bottomRadius,
                startAngle: .degrees(90),
                endAngle: .degrees(180),
                clockwise: false
            )
        }
        return path
    }
}

/// A compact integer field committing on Return or blur, used for whole-number
/// display preferences (for example the per-room row limit). Non-numeric input
/// reverts to the last committed value; the field never commits garbage.
struct SettingsIntegerField: View {
    let placeholder: String
    let value: Int
    let onCommit: (Int) -> Void

    @State private var text: String = ""
    @FocusState private var isFocused: Bool

    var body: some View {
        TextField(placeholder, text: $text)
            .textFieldStyle(.roundedBorder)
            .multilineTextAlignment(.trailing)
            .focused($isFocused)
            .onAppear {
                text = String(value)
            }
            .onChange(of: value) { newValue in
                if !isFocused {
                    text = String(newValue)
                }
            }
            .onSubmit(commit)
            .onChange(of: isFocused) { focused in
                if !focused {
                    commit()
                }
            }
    }

    private func commit() {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if let parsed = Int(trimmed) {
            onCommit(parsed)
            text = String(parsed)
        } else {
            text = String(value)
        }
    }
}
