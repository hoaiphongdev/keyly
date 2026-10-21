import Foundation
import Cocoa

struct AppConstants {
    static let escapeKeyCode: UInt16 = 53
    static let doubleClickTimeInterval: TimeInterval = 0.5
    static let aboutIconSize = NSSize(width: 64, height: 64)
    static let globalTemplateFileName = "global.keyly"
    static let isDevMode = ProcessInfo.processInfo.environment["KEYLY_DEV"] == "1"
    
    struct KeyCodes {
        /// Names accepted as the main key of `super_key` in setting.conf
        static let names: [UInt16: String] = [
            0: "a", 1: "s", 2: "d", 3: "f", 4: "h", 5: "g", 6: "z", 7: "x", 8: "c", 9: "v",
            11: "b", 12: "q", 13: "w", 14: "e", 15: "r", 17: "t", 16: "y", 32: "u", 34: "i", 31: "o",
            35: "p", 33: "[", 30: "]", 36: "return", 38: "l", 40: "k", 37: ";", 41: "'", 42: "\\",
            43: ",", 47: ".", 44: "/", 49: "space", 39: "`",

            29: "0", 18: "1", 19: "2", 20: "3", 21: "4", 23: "5", 22: "6", 26: "7", 28: "8", 25: "9",

            122: "f1", 120: "f2", 99: "f3", 118: "f4", 96: "f5", 97: "f6", 98: "f7", 100: "f8",
            101: "f9", 109: "f10", 103: "f11", 111: "f12",

            54: "cmd", 55: "cmd", 59: "ctrl", 62: "ctrl", 58: "alt", 61: "alt", 56: "shift", 60: "shift",
            63: "fn",

            126: "up", 125: "down", 123: "left", 124: "right",

            51: "delete", 117: "forward_delete", 53: "escape", 48: "tab", 76: "enter",
            116: "page_up", 121: "page_down", 115: "home", 119: "end"
        ]

        static let cmdLeft: UInt16 = 54
        static let cmdRight: UInt16 = 55
        static let ctrlLeft: UInt16 = 59
        static let ctrlRight: UInt16 = 62
        static let altLeft: UInt16 = 58
        static let altRight: UInt16 = 61
        static let shiftLeft: UInt16 = 56
        static let shiftRight: UInt16 = 60
        static let fn: UInt16 = 63
        static let capsLock: UInt16 = 57
        
        static let a: UInt16 = 0
        static let s: UInt16 = 1
        static let d: UInt16 = 2
        static let f: UInt16 = 3
        static let h: UInt16 = 4
        static let g: UInt16 = 5
        static let z: UInt16 = 6
        static let x: UInt16 = 7
        static let c: UInt16 = 8
        static let v: UInt16 = 9
        static let b: UInt16 = 11
        static let q: UInt16 = 12
        static let w: UInt16 = 13
        static let e: UInt16 = 14
        static let r: UInt16 = 15
        static let t: UInt16 = 17
        static let y: UInt16 = 16
        static let u: UInt16 = 32
        static let i: UInt16 = 34
        static let o: UInt16 = 31
        static let p: UInt16 = 35
        static let leftBracket: UInt16 = 33
        static let rightBracket: UInt16 = 30
        static let returnKey: UInt16 = 36
        static let l: UInt16 = 38
        static let k: UInt16 = 40
        static let semicolon: UInt16 = 37
        static let quote: UInt16 = 41
        static let backslash: UInt16 = 42
        static let comma: UInt16 = 43
        static let period: UInt16 = 47
        static let slash: UInt16 = 44
        static let space: UInt16 = 49
        static let backtick: UInt16 = 39
        
        static let zero: UInt16 = 29
        static let one: UInt16 = 18
        static let two: UInt16 = 19
        static let three: UInt16 = 20
        static let four: UInt16 = 21
        static let five: UInt16 = 23
        static let six: UInt16 = 22
        static let seven: UInt16 = 26
        static let eight: UInt16 = 28
        static let nine: UInt16 = 25
        
        static let f1: UInt16 = 122
        static let f2: UInt16 = 120
        static let f3: UInt16 = 99
        static let f4: UInt16 = 118
        static let f5: UInt16 = 96
        static let f6: UInt16 = 97
        static let f7: UInt16 = 98
        static let f8: UInt16 = 100
        static let f9: UInt16 = 101
        static let f10: UInt16 = 109
        static let f11: UInt16 = 103
        static let f12: UInt16 = 111
        
        static let up: UInt16 = 126
        static let down: UInt16 = 125
        static let left: UInt16 = 123
        static let right: UInt16 = 124
        
        static let delete: UInt16 = 51
        static let forwardDelete: UInt16 = 117
        static let escape: UInt16 = 53
        static let tab: UInt16 = 48
        static let enter: UInt16 = 76
        static let pageUp: UInt16 = 116
        static let pageDown: UInt16 = 121
        static let home: UInt16 = 115
        static let end: UInt16 = 119
    }
}