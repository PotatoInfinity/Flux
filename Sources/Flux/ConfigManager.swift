import Foundation

struct ConfigManager {
    static let shared = ConfigManager()
    
    let configDirectory: URL
    let clipboardFile: URL
    let snippetsFile: URL
    let templatesDirectory: URL
    
    init() {
        let homeDir = FileManager.default.homeDirectoryForCurrentUser
        configDirectory = homeDir.appendingPathComponent(".openpowerclick")
        clipboardFile = configDirectory.appendingPathComponent("clipboard.json")
        snippetsFile = configDirectory.appendingPathComponent("snippets.json")
        templatesDirectory = configDirectory.appendingPathComponent("templates")
    }
    
    func setup() throws {
        let fm = FileManager.default
        if !fm.fileExists(atPath: configDirectory.path) {
            try fm.createDirectory(at: configDirectory, withIntermediateDirectories: true)
        }
        if !fm.fileExists(atPath: templatesDirectory.path) {
            try fm.createDirectory(at: templatesDirectory, withIntermediateDirectories: true)
        }
        if !fm.fileExists(atPath: clipboardFile.path) {
            try "[]".write(to: clipboardFile, atomically: true, encoding: .utf8)
        }
        if !fm.fileExists(atPath: snippetsFile.path) {
            try "{}".write(to: snippetsFile, atomically: true, encoding: .utf8)
        }
    }
}
