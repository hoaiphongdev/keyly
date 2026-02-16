import Foundation
import Cocoa

struct WindowConstants {
    static let columnWidth: CGFloat = 200
    static let columnSpacing: CGFloat = 20
    static let rowSpacing: CGFloat = 12
    static let padding: CGFloat = 16
    static let footerHeight: CGFloat = 32
    static let bannerHeight: CGFloat = 48
    static let searchBarHeight: CGFloat = 32

    static let defaultScreenSize = NSSize(width: 1200, height: 800)
    static let screenWidthRatio: CGFloat = 0.7
    static let defaultWindowHeight: CGFloat = 400
    static let minWindowHeight: CGFloat = 200
    static let minSearchWindowHeight: CGFloat = 300
    static let minSearchWindowWidth: CGFloat = 500
    static let maxScreenHeightRatio: CGFloat = 0.8

    static let cornerRadius: CGFloat = 12
    static let bannerCornerRadius: CGFloat = 8

    struct Colors {
        static let readyBannerColor = NSColor.systemGreen.withAlphaComponent(0.2)
        static let updateBannerColor = NSColor.systemBlue.withAlphaComponent(0.2)

        /// Main window background (dark gray, less harsh than pure black)
        static let windowBackgroundColor = NSColor(white: 0.11, alpha: 1)
        /// Card/container background (slightly elevated so cards are visible)
        static let containerBackgroundColor = NSColor(white: 0.16, alpha: 1)
        static let containerBorderColor = NSColor.white.withAlphaComponent(0.15)

        static let settingsButtonTint = NSColor.white.withAlphaComponent(0.75)
        static let escLabelColor = NSColor.white.withAlphaComponent(0.5)

        static let primaryTextColor = NSColor.white.withAlphaComponent(0.95)
        static let secondaryTextColor = NSColor.white.withAlphaComponent(0.85)
        static let tertiaryTextColor = NSColor.white.withAlphaComponent(0.6)

        static let modifiersTextColor = NSColor.white.withAlphaComponent(0.9)
        static let keyTextColor = NSColor.white.withAlphaComponent(0.9)
        static let actionTextColor = NSColor.white.withAlphaComponent(0.7)

        /// Group title (top-level, e.g. "Neovim") — larger, brighter
        static let groupHeaderTextColor = NSColor.white
        static let groupDescriptionTextColor = NSColor.white.withAlphaComponent(0.55)
        /// Category title (inside group or standalone, e.g. "Basic Movement") — smaller, muted
        static let categoryHeaderTextColor = NSColor.white.withAlphaComponent(0.75)
        static let categoryDescriptionTextColor = NSColor.white.withAlphaComponent(0.5)
    }

    struct FontSizes {
        static let groupHeader: CGFloat = 14
        static let categoryHeader: CGFloat = 11
        static let medium: CGFloat = 12
        static let small: CGFloat = 11
        static let tiny: CGFloat = 10
    }

    struct Spacing {
        static let iconSize: CGFloat = 18
        static let settingsButtonSize: CGFloat = 24
        static let spinnerSize: CGFloat = 16
        static let columnSpacing: CGFloat = 5
        static let buttonSpacing: CGFloat = 8
        static let edgeSpacing: CGFloat = 8
        static let smallSpacing: CGFloat = 10
        static let mediumSpacing: CGFloat = 12
        static let largeSpacing: CGFloat = 14
    }
}
