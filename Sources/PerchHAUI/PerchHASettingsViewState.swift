import Foundation
import Combine
import PerchHACore
import PerchHASupport

@MainActor
final class PerchHASettingsViewState: ObservableObject {
    @Published private(set) var snapshot: PerchHAPanelSnapshot
    @Published private(set) var settingsSelectionTree: [SelectableRoom]
    @Published private(set) var snapshotRevision: UInt64 = 0
    @Published private(set) var customActionPersistenceFailureDescription: String?
    @Published private(set) var shellPersistenceFailureDescription: String?
    @Published private(set) var oauthSignInState: PerchHAOAuthSignInState
    @Published private(set) var releaseUpdateState: PerchHAReleaseUpdateState
    @Published private(set) var retryBackoffState: PerchHARetryBackoffState
    @Published private(set) var diagnosticEvents: [PerchHADiagnosticEvent]

    private var cancellables: Set<AnyCancellable> = []
    private weak var model: PerchHAPanelModel?
    private var averageLinkPresenceCache: [EntityID: Bool] = [:]
    private var averageAvailabilityCache: [EntityID: Bool] = [:]
    private var activeTab: PerchHASettingsView.Tab = .connection

    init(model: PerchHAPanelModel) {
        self.model = model
        snapshot = model.snapshot
        settingsSelectionTree = model.settingsSelectionTree
        customActionPersistenceFailureDescription = model.customActionPersistenceFailureDescription
        shellPersistenceFailureDescription = model.shellPersistenceFailureDescription
        oauthSignInState = model.oauthSignInState
        releaseUpdateState = model.releaseUpdateState
        retryBackoffState = model.retryBackoffState
        diagnosticEvents = model.diagnosticEvents

        model.$snapshot
            .receive(on: RunLoop.main)
            .sink { [weak self] snapshot in
                guard let self else {
                    return
                }
                let previousSnapshot = self.snapshot
                guard self.shouldAcceptSnapshotUpdate(from: previousSnapshot, to: snapshot) else {
                    return
                }
                self.snapshot = snapshot
                self.snapshotRevision &+= 1
                if previousSnapshot.selectionConfiguration != snapshot.selectionConfiguration
                    || previousSnapshot.selectionQuery != snapshot.selectionQuery {
                    self.settingsSelectionTree = snapshot.selectionTree
                    self.clearDerivedEntityPresentationCaches()
                }
                if previousSnapshot.menuBarDisplayConfiguration != snapshot.menuBarDisplayConfiguration {
                    self.clearDerivedEntityPresentationCaches()
                }
            }
            .store(in: &cancellables)
        model.$customActionPersistenceFailureDescription
            .receive(on: RunLoop.main)
            .sink { [weak self] failure in
                guard let self, self.activeTab == .entities else {
                    return
                }
                self.customActionPersistenceFailureDescription = failure
            }
            .store(in: &cancellables)
        model.$shellPersistenceFailureDescription
            .receive(on: RunLoop.main)
            .sink { [weak self] failure in
                guard let self, self.activeTab == .entities else {
                    return
                }
                self.shellPersistenceFailureDescription = failure
            }
            .store(in: &cancellables)
        model.$oauthSignInState
            .receive(on: RunLoop.main)
            .sink { [weak self] state in
                guard let self, self.activeTab == .connection else {
                    return
                }
                self.oauthSignInState = state
            }
            .store(in: &cancellables)
        model.$releaseUpdateState
            .receive(on: RunLoop.main)
            .sink { [weak self] state in
                guard let self, self.activeTab == .about else {
                    return
                }
                self.releaseUpdateState = state
            }
            .store(in: &cancellables)
        model.$retryBackoffState
            .receive(on: RunLoop.main)
            .sink { [weak self] state in
                guard let self, self.activeTab == .diagnostics else {
                    return
                }
                self.retryBackoffState = state
            }
            .store(in: &cancellables)
        model.$diagnosticEvents
            .receive(on: RunLoop.main)
            .sink { [weak self] events in
                guard let self, self.activeTab == .diagnostics else {
                    return
                }
                self.diagnosticEvents = events
            }
            .store(in: &cancellables)
    }

    func setActiveTab(_ tab: PerchHASettingsView.Tab) {
        guard activeTab != tab else {
            return
        }
        activeTab = tab
        syncStateForActiveTab()
    }

    func presentation(for entity: DiscoveredEntity, roomName: String) -> PerchHASettingsEntityPresentation {
        PerchHASettingsEntityPresentation(
            metadata: PerchHAEntityMetadataPresentation(entity: entity, roomName: roomName),
            hasAverageLinks: hasAverageLinks(for: entity.id),
            canAverage: canAverage(entity.id)
        )
    }

    func hasAverageLinks(for id: EntityID) -> Bool {
        hasAverageLinksValue(for: id)
    }

    func canAverageEntity(_ id: EntityID) -> Bool {
        canAverage(id)
    }

    private func clearDerivedEntityPresentationCaches() {
        averageLinkPresenceCache.removeAll(keepingCapacity: true)
        averageAvailabilityCache.removeAll(keepingCapacity: true)
    }

    private func hasAverageLinksValue(for id: EntityID) -> Bool {
        if let cached = averageLinkPresenceCache[id] {
            return cached
        }
        let resolved = !(model?.averageLinkedEntityIDs(for: id).isEmpty ?? true)
        averageLinkPresenceCache[id] = resolved
        return resolved
    }

    private func canAverage(_ id: EntityID) -> Bool {
        if let cached = averageAvailabilityCache[id] {
            return cached
        }
        let resolved = model?.canAverage(id) ?? false
        averageAvailabilityCache[id] = resolved
        return resolved
    }

    private func syncStateForActiveTab() {
        guard let model else {
            return
        }
        let currentSnapshot = model.snapshot
        if shouldAcceptSnapshotUpdate(from: snapshot, to: currentSnapshot) {
            snapshot = currentSnapshot
            snapshotRevision &+= 1
            if settingsSelectionTree != currentSnapshot.selectionTree {
                settingsSelectionTree = currentSnapshot.selectionTree
            }
        }
        switch activeTab {
        case .connection:
            oauthSignInState = model.oauthSignInState
        case .entities:
            settingsSelectionTree = model.settingsSelectionTree
            customActionPersistenceFailureDescription = model.customActionPersistenceFailureDescription
            shellPersistenceFailureDescription = model.shellPersistenceFailureDescription
        case .diagnostics:
            retryBackoffState = model.retryBackoffState
            diagnosticEvents = model.diagnosticEvents
        case .about:
            releaseUpdateState = model.releaseUpdateState
        case .general, .appearance, .privacy:
            break
        }
    }

    private func shouldAcceptSnapshotUpdate(
        from previous: PerchHAPanelSnapshot,
        to next: PerchHAPanelSnapshot
    ) -> Bool {
        switch activeTab {
        case .connection:
            previous.connectionState != next.connectionState
                || previous.phase != next.phase
                || previous.connectionForm != next.connectionForm
                || previous.canRetry != next.canRetry
                || previous.failureDescription != next.failureDescription
        case .entities:
            previous.selectionConfiguration != next.selectionConfiguration
                || previous.menuBarDisplayConfiguration != next.menuBarDisplayConfiguration
                || previous.selectionQuery != next.selectionQuery
                || previous.selectionPersistenceFailureDescription != next.selectionPersistenceFailureDescription
                || previous.displayPersistenceFailureDescription != next.displayPersistenceFailureDescription
                || previous.serviceMetadataFailureDescription != next.serviceMetadataFailureDescription
        case .diagnostics:
            previous.connectionState != next.connectionState
                || previous.phase != next.phase
                || previous.canRetry != next.canRetry
                || previous.failureDescription != next.failureDescription
        case .about:
            false
        case .general, .appearance, .privacy:
            false
        }
    }
}
