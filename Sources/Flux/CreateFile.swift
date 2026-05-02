import Foundation
import ArgumentParser

struct CreateFile: AsyncParsableCommand {
    static var configuration = CommandConfiguration(
        commandName: "create-file",
        abstract: "Create a file from a template."
    )
    
    @Argument(help: "The target directory path.")
    var targetDirectory: String
    
    @Argument(help: "The name of the file to create (e.g., script.py).")
    var fileName: String
    
    mutating func run() async throws {
        try ConfigManager.shared.setup()
        
        let ext = (fileName as NSString).pathExtension
        let fm = FileManager.default
        let targetURL = URL(fileURLWithPath: targetDirectory).appendingPathComponent(fileName)
        
        if fm.fileExists(atPath: targetURL.path) {
            print("File already exists at \(targetURL.path)")
            return
        }
        
        var templateFound = false
        if !ext.isEmpty {
            // Find a template matching the extension (e.g., Template.py)
            if let templates = try? fm.contentsOfDirectory(atPath: ConfigManager.shared.templatesDirectory.path) {
                for template in templates {
                    if (template as NSString).pathExtension == ext {
                        let templateURL = ConfigManager.shared.templatesDirectory.appendingPathComponent(template)
                        try fm.copyItem(at: templateURL, to: targetURL)
                        templateFound = true
                        print("Created \(fileName) from template \(template).")
                        break
                    }
                }
            }
        }
        
        if !templateFound {
            fm.createFile(atPath: targetURL.path, contents: Data(), attributes: nil)
            print("Created empty file \(fileName).")
        }
    }
}
