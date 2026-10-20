import Foundation
import Cocoa

struct WindowConstants {
    static let columnWidth: CGFloat = 200
    /// Narrow screens (e.g. 13" MacBook at "Larger Text") allow slimmer columns
    static let compactColumnWidth: CGFloat = 180
    static let compactScreenWidth: CGFloat = 1300
    static let columnSpacing: CGFloat = 20
    static let rowSpacing: CGFloat = 16
    static let padding: CGFloat = 16
    static let headerHeight: CGFloat = 28
    static let footerHeight: CGFloat = 32
    static let searchBarHeight: CGFloat = 32
    /// Vertical gaps: header → search, search → grid, grid → footer
    static let searchTopGap: CGFloat = 8
    static let gridTopGap: CGFloat = 12
    static let gridBottomGap: CGFloat = 4
    /// Everything above and below the shortcut grid
    static let chromeHeight = padding + headerHeight + searchTopGap + searchBarHeight + gridTopGap + gridBottomGap + footerHeight

    static let defaultScreenSize = NSSize(width: 1200, height: 800)
    static let defaultWindowHeight: CGFloat = 400
    static let minWindowWidth: CGFloat = 460
    static let minWindowHeight: CGFloat = 240
    static let maxScreenHeightRatio: CGFloat = 0.8

    static let cornerRadius: CGFloat = 14
    static let showAnimationDuration: TimeInterval = 0.16

    struct Row {
        static let height: CGFloat = 26
        static let horizontalPadding: CGFloat = 8
        static let actionToKeysGap: CGFloat = 16
        static let cornerRadius: CGFloat = 6
    }

    struct Keycap {
        static let height: CGFloat = 18
        static let minWidth: CGFloat = 18
        static let horizontalPadding: CGFloat = 5
        static let cornerRadius: CGFloat = 5
        static let spacing: CGFloat = 3
        static let chordSpacing: CGFloat = 8
    }

    struct Group {
        static let padding: CGFloat = 12
        static let innerSpacing: CGFloat = 16
        static let minInnerColumnWidth: CGFloat = 220
        static let cornerRadius: CGFloat = 10
        static let accentBarWidth: CGFloat = 2
        /// Groups with more items than this spread their categories across columns
        static let singleColumnItemLimit = 10
        static let maxInnerColumns = 4
    }

    struct Colors {
        static let windowBorderColor = NSColor.white.withAlphaComponent(0.10)

        static let containerBackgroundColor = NSColor.white.withAlphaComponent(0.03)
        static let containerBorderColor = NSColor.white.withAlphaComponent(0.08)

        static let appNameTextColor = NSColor.white.withAlphaComponent(0.95)
        static let countTextColor = NSColor.white.withAlphaComponent(0.5)
        static let footerTextColor = NSColor.white.withAlphaComponent(0.5)
        static let settingsButtonTint = NSColor.white.withAlphaComponent(0.6)

        static let actionTextColor = NSColor.white.withAlphaComponent(0.85)
        static let rowHoverColor = NSColor.white.withAlphaComponent(0.06)

        static let keycapTextColor = NSColor.white.withAlphaComponent(0.9)
        static let keycapFillColor = NSColor.white.withAlphaComponent(0.08)
        static let keycapBorderColor = NSColor.white.withAlphaComponent(0.12)

        /// Group title (top-level, e.g. "Neovim") — larger, brighter
        static let groupHeaderTextColor = NSColor.white
        static let groupDescriptionTextColor = NSColor.white.withAlphaComponent(0.55)
        /// Category title (inside group or standalone, e.g. "Basic Movement") — small caps, muted
        static let categoryHeaderTextColor = NSColor.white.withAlphaComponent(0.55)
        static let categoryDescriptionTextColor = NSColor.white.withAlphaComponent(0.5)

        static let emptyStateTextColor = NSColor.white.withAlphaComponent(0.7)
        static let emptyStateHintColor = NSColor.white.withAlphaComponent(0.45)
    }

    struct FontSizes {
        static let appName: CGFloat = 13
        static let search: CGFloat = 14
        static let groupHeader: CGFloat = 13
        static let categoryHeader: CGFloat = 10.5
        static let action: CGFloat = 12
        static let keycap: CGFloat = 11
        static let description: CGFloat = 10.5
        static let footer: CGFloat = 11
    }
}
