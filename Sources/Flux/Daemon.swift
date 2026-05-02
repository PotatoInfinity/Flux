import Foundation
import ArgumentParser
import AppKit

struct Daemon: AsyncParsableCommand {
    static var configuration = CommandConfiguration(
        commandName: "daemon",
        abstract: "Run the clipboard monitoring daemon."
    )
    
    mutating func run() async throws {
        try ConfigManager.shared.setup()
        let pasteboard = NSPasteboard.general
        var lastChangeCount = pasteboard.changeCount
        
        print("OpenPowerClick Daemon started...")
        
        while true {
            if pasteboard.changeCount != lastChangeCount {
                lastChangeCount = pasteboard.changeCount
                if let text = pasteboard.string(forType: .string) {
                    ClipboardManager.shared.add(text: text)
                }
            }
            try await Task.sleep(nanoseconds: 500_000_000) // 0.5s
        }
    }
}
