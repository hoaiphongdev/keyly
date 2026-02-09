import Foundation
import Cocoa

struct WindowConstants {
    static let columnWidth: CGFloat = 200
    static let columnSpacing: CGFloat = 20
    static let rowSpacing: CGFloat = 12
    static let padding: CGFloat = 16
    static let footerHeight: CGFloat = 32
    static let bannerHeight: CGFloat = 48
    
    static let defaultScreenSize = NSSize(width: 1200, height: 800)
    static let screenWidthRatio: CGFloat = 0.75
    static let defaultWindowHeight: CGFloat = 400
    static let maxScreenHeightRatio: CGFloat = 0.8
    
    static let cornerRadius: CGFloat = 12
    static let bannerCornerRadius: CGFloat = 8
    
    struct Colors {
        static let readyBannerColor = NSColor.systemGreen.withAlphaComponent(0.2)
        static let updateBannerColor = NSColor.systemBlue.withAlphaComponent(0.2)
        static let settingsButtonTint = NSColor.white.withAlphaComponent(0.6)
        static let escLabelColor = NSColor.white.withAlphaComponent(0.6)
        static let descriptionTextColor = NSColor.white.withAlphaComponent(0.5)
        static let modifiersTextColor = NSColor.white.withAlphaComponent(0.55)
        static let keyTextColor = NSColor(calibratedRed: 0.4, green: 0.85, blue: 1.0, alpha: 1.0)
        static let actionTextColor = NSColor.white.withAlphaComponent(0.85)
    }
    
    struct FontSizes {
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