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
    @Published private(set) var diagnosticsReferenceInstant: PerchInstant

    private var cancellables: Set<AnyCancellable> = []
    private weak var model: PerchHAPanelModel?
    private var averageLinkPresenceCache: [EntityID: Bool] = [:]
    private var averageAvailabilityCache: [EntityID: Bool] = [:]

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
        diagnosticsReferenceInstant = model.diagnosticsReferenceInstant

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
            .assign(to: &$customActionPersistenceFailureDescription)
        model.$shellPersistenceFailureDescription
            .receive(on: RunLoop.main)
            .assign(to: &$shellPersistenceFailureDescription)
        model.$oauthSignInState
            .receive(on: RunLoop.main)
            .assign(to: &$oauthSignInState)
        model.$releaseUpdateState
            .receive(on: RunLoop.main)
            .assign(to: &$releaseUpdateState)
        model.$retryBackoffState
            .receive(on: RunLoop.main)
            .assign(to: &$retryBackoffState)
        model.$diagnosticEvents
            .receive(on: RunLoop.main)
            .assign(to: &$diagnosticEvents)
        model.$diagnosticsReferenceInstant
            .receive(on: RunLoop.main)
            .assign(to: &$diagnosticsReferenceInstant)
    }

    func presentation(for entity: DiscoveredEntity, roomName: String) -> PerchHASettingsEntityPresentation {
        PerchHASettingsEntityPresentation(
            metadata: PerchHAEntityMetadataPresentation(entity: entity, roomName: roomName),
            hasAverageLinks: hasAverageLinks(for: entity.id),
            canAverage: canAverage(entity.id)
        )
    }

    private func clearDerivedEntityPresentationCaches() {
        averageLinkPresenceCache.removeAll(keepingCapacity: true)
        averageAvailabilityCache.removeAll(keepingCapacity: true)
    }

    private func hasAverageLinks(for id: EntityID) -> Bool {
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

    private func shouldAcceptSnapshotUpdate(
        from previous: PerchHAPanelSnapshot,
        to next: PerchHAPanelSnapshot
    ) -> Bool {
        previous.connectionState != next.connectionState
            || previous.phase != next.phase
            || previous.connectionForm != next.connectionForm
            || previous.canRetry != next.canRetry
            || previous.selectionConfiguration != next.selectionConfiguration
            || previous.menuBarDisplayConfiguration != next.menuBarDisplayConfiguration
            || previous.selectionQuery != next.selectionQuery
            || previous.isSettingsPresented != next.isSettingsPresented
            || previous.selectionPersistenceFailureDescription != next.selectionPersistenceFailureDescription
            || previous.displayPersistenceFailureDescription != next.displayPersistenceFailureDescription
            || previous.failureDescription != next.failureDescription
    }
}
