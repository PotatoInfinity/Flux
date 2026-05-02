import Foundation
import AppKit

struct ClipboardItem: Codable, Identifiable {
    let id: UUID
    let timestamp: Date
    let text: String
}

class ClipboardManager {
    static let shared = ClipboardManager()
    private var history: [ClipboardItem] = []
    
    init() {
        loadHistory()
    }
    
    func loadHistory() {
        do {
            let data = try Data(contentsOf: ConfigManager.shared.clipboardFile)
            history = try JSONDecoder().decode([ClipboardItem].self, from: data)
        } catch {
            history = []
        }
    }
    
    func saveHistory() {
        do {
            let data = try JSONEncoder().encode(history)
            try data.write(to: ConfigManager.shared.clipboardFile)
        } catch {
            print("Failed to save clipboard history: \(error)")
        }
    }
    
    func add(text: String) {
        // Prevent duplicate consecutive entries
        if history.first?.text == text { return }
        
        let item = ClipboardItem(id: UUID(), timestamp: Date(), text: text)
        history.insert(item, at: 0)
        
        // Keep only last 100 items
        if history.count > 100 {
            history = Array(history.prefix(100))
        }
        saveHistory()
    }
    
    func getHistory() -> [ClipboardItem] {
        return history
    }
    
    func copyItem(at index: Int) -> Bool {
        guard index >= 0 && index < history.count else { return false }
        let text = history[index].text
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        return pasteboard.setString(text, forType: .string)
    }
}
