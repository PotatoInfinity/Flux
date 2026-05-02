import Foundation
import ArgumentParser

struct Clipboard: AsyncParsableCommand {
    static var configuration = CommandConfiguration(
        commandName: "history",
        abstract: "Manage clipboard history.",
        subcommands: [List.self, Copy.self],
        defaultSubcommand: List.self
    )
    
    struct List: AsyncParsableCommand {
        static var configuration = CommandConfiguration(
            commandName: "list",
            abstract: "List recent clipboard history."
        )
        
        mutating func run() async throws {
            try ConfigManager.shared.setup()
            let history = ClipboardManager.shared.getHistory()
            if history.isEmpty {
                print("Clipboard history is empty.")
                return
            }
            for (index, item) in history.enumerated() {
                let preview = item.text.replacingOccurrences(of: "\n", with: " ").prefix(50)
                let suffix = item.text.count > 50 ? "..." : ""
                print("[\(index)] \(preview)\(suffix)")
            }
        }
    }
    
    struct Copy: AsyncParsableCommand {
        static var configuration = CommandConfiguration(
            commandName: "copy",
            abstract: "Copy an item from history back to the clipboard."
        )
        
        @Argument(help: "The index of the item to copy.")
        var index: Int
        
        mutating func run() async throws {
            try ConfigManager.shared.setup()
            if ClipboardManager.shared.copyItem(at: index) {
                print("Copied item \(index) to clipboard.")
            } else {
                print("Invalid index.")
            }
        }
    }
}
