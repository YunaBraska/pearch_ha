import SwiftUI

/// The PearchHA spacing scale.
///
/// A small, fixed set of step values used for padding and stack spacing so the
/// panel, room cards, and settings sections share one rhythm instead of ad-hoc
/// literals. Steps are named after their role (`xs`…`xl`), not their pixel size,
/// so the scale can be retuned in one place.
public enum PearchHASpacing {
    /// 4 pt — hairline insets and tight icon/label gaps.
    public static let xs: CGFloat = 4
    /// 8 pt — the default gap between related controls.
    public static let sm: CGFloat = 8
    /// 12 pt — the gap between grouped rows and cards.
    public static let md: CGFloat = 12
    /// 16 pt — card interior padding.
    public static let lg: CGFloat = 16
    /// 24 pt — generous padding for centered state views.
    public static let xl: CGFloat = 24
}

/// The PearchHA corner-radius scale for the three nesting levels of surface.
///
/// Controls sit inside cards, cards sit inside the panel; each level uses a
/// slightly larger radius so nested shapes stay visually concentric.
public enum PearchHACornerRadius {
    /// 8 pt — buttons, capsule fields, inset controls.
    public static let control: CGFloat = 8
    /// 12 pt — grouped room and settings cards.
    public static let card: CGFloat = 12
    /// 16 pt — the outer panel surface.
    public static let panel: CGFloat = 16
}

/// The PearchHA typography helpers.
///
/// Each helper returns a system `Font` at the role's size so callers stop
/// scattering `.system(size:)` literals. Value-bearing fonts use the
/// monospaced-digit design so numbers do not shift width as they change.
public enum PearchHATypography {
    /// A muted caption used for section labels and secondary hints (11 pt).
    public static func caption() -> Font {
        .system(size: 11, weight: .semibold)
    }

    /// The default body/row font for entity rows and settings text (13 pt).
    public static func body() -> Font {
        .system(size: 13)
    }

    /// The body/row font for a value rendered with monospaced digits (13 pt).
    public static func bodyValue() -> Font {
        .system(size: 13).monospacedDigit()
    }

    /// The prominent primary value font for the headline number in a metric
    /// (18 pt), rendered with monospaced digits.
    public static func primaryValue() -> Font {
        .system(size: 18, weight: .semibold).monospacedDigit()
    }
}

/// The PearchHA motion tokens and reduce-motion-aware animation helper.
///
/// A single standard duration keeps transitions consistent, and
/// ``animation(reduceMotion:)`` collapses to no animation when the user has
/// asked the system to reduce motion — so callers can express intent once and
/// honor the accessibility setting without branching at every call site.
public enum PearchHAMotion {
    /// The standard transition duration (0.18 s), within the 120–200 ms range
    /// used across the panel and settings.
    public static let standardDuration: Double = 0.18

    /// Returns the standard ease-in-out animation, or `nil` when Reduce Motion
    /// is on so no animation is applied.
    ///
    /// - Parameter reduceMotion: Whether the user has enabled Reduce Motion.
    /// - Returns: An `easeInOut` animation of ``standardDuration``, or `nil`.
    public static func animation(reduceMotion: Bool) -> Animation? {
        reduceMotion ? nil : .easeInOut(duration: standardDuration)
    }
}
