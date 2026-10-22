import Foundation
import SwiftUI

// Code the Apple Watch app and its complications both need. Neither can see
// the phone's App Group — it is on another device — so the watch keeps its
// own copy of what the phone last sent, in the watch's own App Group, where
// the complications read it. The same identifier as the phone's: App Groups
// are per device, so the two containers never meet.

/// What the phone last sent, and the taps it has not answered yet.
enum WatchStore {
    static let appGroupIdentifier = "group.app.zeitkonto"

    private static let contextFile = "watch-context.json"
    private static let pendingFile = "watch-pending.json"

    private static func url(_ name: String) -> URL? {
        FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: appGroupIdentifier)?
            .appendingPathComponent(name)
    }

    static func readContext() -> WatchContext? {
        guard let url = url(contextFile), let data = try? Data(contentsOf: url) else { return nil }
        return WatchContext(data: data)
    }

    static func write(_ context: WatchContext) {
        guard let url = url(contextFile), let data = context.encoded() else { return }
        try? data.write(to: url, options: .atomic)
    }

    static func readPending() -> [WatchCommand] {
        guard let url = url(pendingFile), let data = try? Data(contentsOf: url) else { return [] }
        return (try? JSONDecoder().decode([WatchCommand].self, from: data)) ?? []
    }

    static func write(pending: [WatchCommand]) {
        guard let url = url(pendingFile), let data = try? JSONEncoder().encode(pending) else { return }
        try? data.write(to: url, options: .atomic)
    }
}

/// The app's colours, as the widgets use them.
enum WatchPalette {
    static let amber = Color(red: 0xff / 255, green: 0xb0 / 255, blue: 0x2e / 255)
    static let mist = Color(red: 0x9f / 255, green: 0xb0 / 255, blue: 0xe8 / 255)
    static let running = Color(red: 0x34 / 255, green: 0xc7 / 255, blue: 0x59 / 255)
    static let positive = Color(red: 0x4c / 255, green: 0xd9 / 255, blue: 0x64 / 255)
    static let stop = Color(red: 0xff / 255, green: 0x45 / 255, blue: 0x3a / 255)
}
