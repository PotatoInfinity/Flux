import Foundation
import ArgumentParser
import AppKit

struct Snippet: AsyncParsableCommand {
    static var configuration = CommandConfiguration(
        commandName: "snippet",
        abstract: "Manage snippet library.",
        subcommands: [Add.self, List.self, Copy.self],
        defaultSubcommand: List.self
    )
    
    static func loadSnippets() throws -> [String: String] {
        let data = try Data(contentsOf: ConfigManager.shared.snippetsFile)
        return try JSONDecoder().decode([String: String].self, from: data)
    }
    
    static func saveSnippets(_ snippets: [String: String]) throws {
        let data = try JSONEncoder().encode(snippets)
        try data.write(to: ConfigManager.shared.snippetsFile)
    }
    
    struct Add: AsyncParsableCommand {
        static var configuration = CommandConfiguration(commandName: "add", abstract: "Add a snippet.")
        
        @Argument(help: "The name of the snippet.")
        var name: String
        
        @Argument(help: "The snippet text.")
        var text: String
        
        mutating func run() async throws {
            try ConfigManager.shared.setup()
            var snippets = try Snippet.loadSnippets()
            snippets[name] = text
            try Snippet.saveSnippets(snippets)
            print("Snippet '\(name)' added.")
        }
    }
    
    struct List: AsyncParsableCommand {
        static var configuration = CommandConfiguration(commandName: "list", abstract: "List all snippets.")
        
        mutating func run() async throws {
            try ConfigManager.shared.setup()
            let snippets = try Snippet.loadSnippets()
            if snippets.isEmpty {
                print("No snippets found.")
                return
            }
            for (name, text) in snippets {
                let preview = text.replacingOccurrences(of: "\n", with: " ").prefix(40)
                let suffix = text.count > 40 ? "..." : ""
                print("\(name): \(preview)\(suffix)")
            }
        }
    }
    
    struct Copy: AsyncParsableCommand {
        static var configuration = CommandConfiguration(commandName: "copy", abstract: "Copy a snippet to the clipboard.")
        
        @Argument(help: "The name of the snippet to copy.")
        var name: String
        
        mutating func run() async throws {
            try ConfigManager.shared.setup()
            let snippets = try Snippet.loadSnippets()
            if let text = snippets[name] {
                let pasteboard = NSPasteboard.general
                pasteboard.clearContents()
                if pasteboard.setString(text, forType: .string) {
                    print("Copied snippet '\(name)' to clipboard.")
                }
            } else {
                print("Snippet '\(name)' not found.")
            }
        }
    }
}
