import Foundation
import PerchHACore
import PerchHAPersistence
import PerchHAUI

public struct PerchHAMenuBarPresentation: Equatable, Sendable {
    public static let fallback = PerchHAMenuBarPresentation(
        entityID: nil,
        title: "PearchHA",
        statusItemTitle: "PearchHA",
        accessibilityLabel: "PearchHA",
        renderedItem: nil
    )

    /// The promoted entity this item represents, or `nil` for the fallback
    /// (fish-logo) item shown when no entity is promoted.
    public let entityID: EntityID?
    public let title: String
    public let statusItemTitle: String
    public let accessibilityLabel: String
    public let renderedItem: RenderedMenuBarItem?

    public init(
        entityID: EntityID?,
        title: String,
        statusItemTitle: String,
        accessibilityLabel: String,
        renderedItem: RenderedMenuBarItem?
    ) {
        self.entityID = entityID
        self.title = title
        self.statusItemTitle = statusItemTitle
        self.accessibilityLabel = accessibilityLabel
        self.renderedItem = renderedItem
    }
}

public struct PerchHAMenuBarPresenter: Sendable {
    private let renderer: MenuBarItemRenderer
    private let projector: MenuBarItemProjector

    public init(
        renderer: MenuBarItemRenderer = MenuBarItemRenderer(),
        projector: MenuBarItemProjector = MenuBarItemProjector()
    ) {
        self.renderer = renderer
        self.projector = projector
    }

    /// Builds the menu-bar presentation for the first promoted entity, or the
    /// fallback (fish-logo) presentation when nothing is promoted.
    ///
    /// - Parameters:
    ///   - configuration: The active configuration carrying promoted entity IDs
    ///     and per-entity display options.
    ///   - panelSnapshot: The current panel snapshot supplying live entity values.
    ///   - locale: The locale used to format values and units.
    /// - Returns: The first element of ``presentations(configuration:panelSnapshot:locale:)``.
    public func presentation(
        configuration: PerchHAConfiguration,
        panelSnapshot: PerchHAPanelSnapshot,
        locale: Locale = .current
    ) -> PerchHAMenuBarPresentation {
        presentations(
            configuration: configuration,
            panelSnapshot: panelSnapshot,
            locale: locale
        )[0]
    }

    /// Builds one menu-bar presentation per promoted entity, in
    /// `menuBarEntityIDs` order, skipping IDs absent from the available rooms.
    ///
    /// - Parameters:
    ///   - configuration: The active configuration carrying promoted entity IDs
    ///     and per-entity display options.
    ///   - panelSnapshot: The current panel snapshot supplying live entity values.
    ///   - locale: The locale used to format values and units.
    /// - Returns: A non-empty array with one presentation per promoted entity;
    ///   a single-element array holding ``PerchHAMenuBarPresentation/fallback``
    ///   when no promoted entity is present.
    public func presentations(
        configuration: PerchHAConfiguration,
        panelSnapshot: PerchHAPanelSnapshot,
        locale: Locale = .current
    ) -> [PerchHAMenuBarPresentation] {
        // Read the promoted set from the live panel snapshot rather than the
        // launch-time configuration so runtime promotions immediately add or
        // remove menu-bar items.
        let displayConfiguration = panelSnapshot.menuBarDisplayConfiguration
        let entities = projector.promotedEntities(
            rooms: panelSnapshot.availableRooms,
            menuBarEntityIDs: displayConfiguration.promotedEntityIDs
        )
        guard !entities.isEmpty else {
            return [.fallback]
        }
        let availableEntities = panelSnapshot.availableRooms.flatMap(\.entities)
        return entities.map { entity in
            let rendered = renderer.render(
                entity: entity,
                configuration: displayConfiguration.itemConfiguration(for: entity.id),
                availableEntities: availableEntities,
                locale: locale,
                isStale: panelSnapshot.valuesAreStale
            )
            return PerchHAMenuBarPresentation(
                entityID: entity.id,
                title: rendered.title,
                statusItemTitle: rendered.gauge == nil ? rendered.title : rendered.textTitle,
                accessibilityLabel: rendered.accessibilityLabel,
                renderedItem: rendered
            )
        }
    }
}
