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
        renderedItem: nil,
        showsImage: true,
        showsTitle: false,
        visibleFallbackTitle: "PearchHA",
        iconSymbolName: nil
    )

    /// The promoted entity this item represents, or `nil` for the fallback
    /// (fish-logo) item shown when no entity is promoted.
    public let entityID: EntityID?
    public let title: String
    public let statusItemTitle: String
    public let accessibilityLabel: String
    public let renderedItem: RenderedMenuBarItem?
    /// Whether this item's resolved appearance shows the status-item image.
    public let showsImage: Bool
    /// Whether this item's resolved appearance shows the status-item title.
    public let showsTitle: Bool
    /// A short, always non-empty title used to keep a promoted item visible when
    /// the resolved appearance would otherwise leave it with no image and no
    /// title (a zero-width, invisible status item).
    public let visibleFallbackTitle: String
    /// The SF Symbol drawn as the status-item icon when the entity's "Show
    /// icon" option is on: the user's custom pick, else the automatic
    /// domain-derived symbol. `nil` when the icon is turned off or when a gauge
    /// image already occupies the image slot.
    public let iconSymbolName: String?

    public init(
        entityID: EntityID?,
        title: String,
        statusItemTitle: String,
        accessibilityLabel: String,
        renderedItem: RenderedMenuBarItem?,
        showsImage: Bool,
        showsTitle: Bool,
        visibleFallbackTitle: String,
        iconSymbolName: String? = nil
    ) {
        self.entityID = entityID
        self.title = title
        self.statusItemTitle = statusItemTitle
        self.accessibilityLabel = accessibilityLabel
        self.renderedItem = renderedItem
        self.showsImage = showsImage
        self.showsTitle = showsTitle
        self.visibleFallbackTitle = visibleFallbackTitle
        self.iconSymbolName = iconSymbolName
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
        let globalAppearance = configuration.menuBarAppearance
        return entities.map { entity in
            let itemConfiguration = displayConfiguration.itemConfiguration(for: entity.id)
            let rendered = renderer.render(
                entity: entity,
                configuration: itemConfiguration,
                availableEntities: availableEntities,
                locale: locale,
                isStale: panelSnapshot.valuesAreStale
            )
            // A per-entity appearance always wins over the global default.
            let appearance = itemConfiguration.appearance ?? globalAppearance
            // A gauge image owns the image slot; otherwise the per-entity
            // "Show icon" option supplies an SF Symbol (custom pick, else the
            // automatic domain icon) so a text item can carry an icon.
            let iconSymbolName: String? = rendered.gauge == nil && itemConfiguration.showsEntityIcon
                ? (itemConfiguration.customIconName ?? perchHAEntityIconName(for: entity))
                : nil
            return PerchHAMenuBarPresentation(
                entityID: entity.id,
                title: rendered.title,
                statusItemTitle: rendered.gauge == nil ? rendered.title : rendered.textTitle,
                accessibilityLabel: rendered.accessibilityLabel,
                renderedItem: rendered,
                showsImage: appearance.showsImage,
                showsTitle: appearance.showsTitle,
                visibleFallbackTitle: Self.visibleFallbackTitle(for: entity, rendered: rendered),
                iconSymbolName: iconSymbolName
            )
        }
    }

    /// A short, always non-empty title that keeps a promoted item visible when
    /// the resolved appearance would otherwise leave it with no image and no
    /// title. Prefers the rendered value text, then the entity name; finally a
    /// single-letter abbreviation so the item never collapses to zero width.
    private static func visibleFallbackTitle(for entity: DiscoveredEntity, rendered: RenderedMenuBarItem) -> String {
        let value = rendered.value.text.trimmingCharacters(in: .whitespacesAndNewlines)
        if !value.isEmpty {
            return value
        }
        let name = entity.name.trimmingCharacters(in: .whitespacesAndNewlines)
        if !name.isEmpty {
            return name
        }
        let identifier = entity.id.rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        return identifier.isEmpty ? "•" : String(identifier.prefix(1)).uppercased()
    }
}
