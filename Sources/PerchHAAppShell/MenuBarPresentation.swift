import Foundation
import PerchHACore
import PerchHAPersistence
import PerchHAUI

public struct PerchHAMenuBarPresentation: Equatable, Sendable {
    public static let fallback = PerchHAMenuBarPresentation(
        title: "PearchHA",
        statusItemTitle: "PearchHA",
        accessibilityLabel: "PearchHA",
        renderedItem: nil
    )

    public let title: String
    public let statusItemTitle: String
    public let accessibilityLabel: String
    public let renderedItem: RenderedMenuBarItem?

    public init(
        title: String,
        statusItemTitle: String,
        accessibilityLabel: String,
        renderedItem: RenderedMenuBarItem?
    ) {
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

    public func presentation(
        configuration: PerchHAConfiguration,
        panelSnapshot: PerchHAPanelSnapshot,
        locale: Locale = .current
    ) -> PerchHAMenuBarPresentation {
        guard let entity = projector.promotedEntities(
            rooms: panelSnapshot.availableRooms,
            menuBarEntityIDs: configuration.menuBarEntityIDs
        ).first else {
            return .fallback
        }

        let rendered = renderer.render(
            entity: entity,
            configuration: configuration.menuBarDisplayConfiguration.itemConfiguration(for: entity.id),
            availableEntities: panelSnapshot.availableRooms.flatMap(\.entities),
            locale: locale,
            isStale: panelSnapshot.valuesAreStale
        )
        return PerchHAMenuBarPresentation(
            title: rendered.title,
            statusItemTitle: rendered.gauge == nil ? rendered.title : rendered.textTitle,
            accessibilityLabel: rendered.accessibilityLabel,
            renderedItem: rendered
        )
    }
}
