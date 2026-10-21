import Cocoa
import Testing
@testable import Keyly

@Suite struct TriggerTests {
    private func trigger(_ superKey: String) -> Trigger {
        SettingsParser.parse("super_key = \(superKey)").settings.trigger
    }

    @Test func modifiersMustMatchExactly() {
        let ctrlK = trigger("ctrl+k")
        #expect(ctrlK.matchesKey(AppConstants.KeyCodes.k, flags: .control))
        #expect(!ctrlK.matchesKey(AppConstants.KeyCodes.k, flags: [.control, .command]))
        #expect(!ctrlK.matchesKey(AppConstants.KeyCodes.k, flags: []))
        #expect(!ctrlK.matchesKey(AppConstants.KeyCodes.l, flags: .control))
    }

    @Test func capsLockAndFnFlagsAreIgnoredUnlessAsked() {
        let ctrlK = trigger("ctrl+k")
        #expect(ctrlK.matchesKey(AppConstants.KeyCodes.k, flags: [.control, .capsLock, .function, .numericPad]))
        #expect(trigger("fn+f1").matchesKey(AppConstants.KeyCodes.f1, flags: [.function]))
        #expect(!trigger("fn+f1").matchesKey(AppConstants.KeyCodes.f1, flags: []))
    }

    @Test func modifierOnlyTrigger() {
        let cmd = trigger("cmd")
        #expect(cmd.isModifierOnly)
        #expect(cmd.matchesModifiers(.command))
        #expect(!cmd.matchesModifiers([.command, .shift]))
        #expect(!trigger("capslock").isModifierOnly)
    }
}

