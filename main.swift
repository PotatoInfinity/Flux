import Foundation
import AppKit

// MARK: - Config Manager
struct ConfigManager {
    static let shared = ConfigManager()
    let configDirectory: URL
    let clipboardFile: URL
    let snippetsFile: URL
    let templatesDirectory: URL
    
    init() {
        let homeDir = FileManager.default.homeDirectoryForCurrentUser
        configDirectory = homeDir.appendingPathComponent(".flux")
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

// MARK: - Clipboard Manager
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
            print("Failed to save clipboard history: " + error.localizedDescription)
        }
    }
    
    func add(text: String) {
        if history.first?.text == text { return }
        let item = ClipboardItem(id: UUID(), timestamp: Date(), text: text)
        history.insert(item, at: 0)
        if history.count > 100 {
            history = Array(history.prefix(100))
        }
        saveHistory()
    }
    
    func getHistory() -> [ClipboardItem] { return history }
    
    func copyItem(at index: Int) -> Bool {
        guard index >= 0 && index < history.count else { return false }
        let text = history[index].text
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        return pasteboard.setString(text, forType: .string)
    }
}

// MARK: - Commands

func runDaemon() {
    print("Flux Daemon started...")
    let pasteboard = NSPasteboard.general
    var lastChangeCount = pasteboard.changeCount
    
    while true {
        if pasteboard.changeCount != lastChangeCount {
            lastChangeCount = pasteboard.changeCount
            if let text = pasteboard.string(forType: .string) {
                ClipboardManager.shared.add(text: text)
            }
        }
        Thread.sleep(forTimeInterval: 0.5)
    }
}

func listHistory() {
    let history = ClipboardManager.shared.getHistory()
    if history.isEmpty {
        print("Clipboard history is empty.")
        return
    }
    for (index, item) in history.enumerated() {
        let preview = item.text.replacingOccurrences(of: "\n", with: " ").prefix(50)
        let suffix = item.text.count > 50 ? "..." : ""
        print("[" + String(index) + "] " + String(preview) + suffix)
    }
}

func loadSnippets() throws -> [String: String] {
    let data = try Data(contentsOf: ConfigManager.shared.snippetsFile)
    return try JSONDecoder().decode([String: String].self, from: data)
}

func saveSnippets(_ snippets: [String: String]) throws {
    let data = try JSONEncoder().encode(snippets)
    try data.write(to: ConfigManager.shared.snippetsFile)
}

func installDaemon() {
    let plistName = "com.flux.daemon.plist"
    let homeDir = FileManager.default.homeDirectoryForCurrentUser
    let launchAgentsDir = homeDir.appendingPathComponent("Library/LaunchAgents")
    let plistURL = launchAgentsDir.appendingPathComponent(plistName)
    
    do {
        let fm = FileManager.default
        if !fm.fileExists(atPath: launchAgentsDir.path) {
            try fm.createDirectory(at: launchAgentsDir, withIntermediateDirectories: true)
        }
        
        let absoluteExecutablePath = URL(fileURLWithPath: CommandLine.arguments[0]).standardizedFileURL.path
        
        let plistContent = [
            "<?xml version=\"1.0\" encoding=\"UTF-8\"?>",
            "<!DOCTYPE plist PUBLIC \"-//Apple//DTD PLIST 1.0//EN\" \"http://www.apple.com/DTDs/PropertyList-1.0.dtd\">",
            "<plist version=\"1.0\">",
            "<dict>",
            "    <key>Label</key>",
            "    <string>com.flux.daemon</string>",
            "    <key>ProgramArguments</key>",
            "    <array>",
            "        <string>" + absoluteExecutablePath + "</string>",
            "        <string>daemon</string>",
            "    </array>",
            "    <key>RunAtLoad</key>",
            "    <true/>",
            "    <key>KeepAlive</key>",
            "    <true/>",
            "</dict>",
            "</plist>"
        ].joined(separator: "\n")
        
        try plistContent.write(to: plistURL, atomically: true, encoding: .utf8)
        print("Installed launch agent to " + plistURL.path)
        
        let task1 = Process()
        task1.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        task1.arguments = ["unload", plistURL.path]
        try? task1.run()
        task1.waitUntilExit()
        
        let task2 = Process()
        task2.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        task2.arguments = ["load", plistURL.path]
        try task2.run()
        task2.waitUntilExit()
        
        print("Daemon started successfully.")
    } catch {
        print("Error: " + error.localizedDescription)
    }
}

func installQuickAction() {
    do {
        let homeDir = FileManager.default.homeDirectoryForCurrentUser
        let servicesDir = homeDir.appendingPathComponent("Library/Services")
        let workflowDir = servicesDir.appendingPathComponent("Flux New File.workflow")
        let contentsDir = workflowDir.appendingPathComponent("Contents")
        
        let fm = FileManager.default
        if !fm.fileExists(atPath: contentsDir.path) {
            try fm.createDirectory(at: contentsDir, withIntermediateDirectories: true)
        }
        
        let absoluteExecutablePath = URL(fileURLWithPath: CommandLine.arguments[0]).standardizedFileURL.path
        
        let infoPlist = [
            "<?xml version=\"1.0\" encoding=\"UTF-8\"?>",
            "<!DOCTYPE plist PUBLIC \"-//Apple//DTD PLIST 1.0//EN\" \"http://www.apple.com/DTDs/PropertyList-1.0.dtd\">",
            "<plist version=\"1.0\">",
            "<dict>",
            "    <key>NSServices</key>",
            "    <array>",
            "        <dict>",
            "            <key>NSMenuItem</key>",
            "            <dict>",
            "                <key>default</key>",
            "                <string>Flux: New File</string>",
            "            </dict>",
            "            <key>NSMessage</key>",
            "            <string>runWorkflowAsService</string>",
            "            <key>NSRequiredContext</key>",
            "            <dict>",
            "                <key>NSApplicationIdentifier</key>",
            "                <string>com.apple.finder</string>",
            "            </dict>",
            "        </dict>",
            "    </array>",
            "</dict>",
            "</plist>"
        ].joined(separator: "\n")
        
        let scriptLines = [
            "on run {input, parameters}",
            "    tell application \"Finder\"",
            "        if exists insertion location then",
            "            set targetDir to POSIX path of (insertion location as alias)",
            "        else",
            "            set targetDir to POSIX path of (path to desktop folder as alias)",
            "        end if",
            "    end tell",
            "    ",
            "    tell application \"System Events\"",
            "        activate",
            "        set fileName to text returned of (display dialog \"Enter new file name:\" default answer \"index.html\" with title \"Flux New File\")",
            "    end tell",
            "    ",
            "    do shell script \"" + absoluteExecutablePath + " create-file \" & quoted form of targetDir & \" \" & quoted form of fileName",
            "    return input",
            "end run"
        ]
        let script = scriptLines.joined(separator: "\n")
        let safeScript = script.replacingOccurrences(of: "<", with: "&lt;").replacingOccurrences(of: ">", with: "&gt;").replacingOccurrences(of: "&", with: "&amp;")
        
        let scriptParam = "on run {input, parameters}\n\n\t(* Your script goes here *)\n\n\treturn input\nend run"
        
        let wflow = [
            "<?xml version=\"1.0\" encoding=\"UTF-8\"?>",
            "<!DOCTYPE plist PUBLIC \"-//Apple//DTD PLIST 1.0//EN\" \"http://www.apple.com/DTDs/PropertyList-1.0.dtd\">",
            "<plist version=\"1.0\">",
            "<dict>",
            "    <key>AMApplicationBuild</key>",
            "    <string>523</string>",
            "    <key>AMApplicationVersion</key>",
            "    <string>2.10</string>",
            "    <key>AMDocumentVersion</key>",
            "    <string>2</string>",
            "    <key>actions</key>",
            "    <array>",
            "        <dict>",
            "            <key>action</key>",
            "            <dict>",
            "                <key>AMAccepts</key>",
            "                <dict>",
            "                    <key>Container</key>",
            "                    <string>List</string>",
            "                    <key>Optional</key>",
            "                    <true/>",
            "                    <key>Types</key>",
            "                    <array>",
            "                        <string>com.apple.applescript.object</string>",
            "                    </array>",
            "                </dict>",
            "                <key>AMActionVersion</key>",
            "                <string>1.0.2</string>",
            "                <key>AMApplication</key>",
            "                <array>",
            "                    <string>Automator</string>",
            "                </array>",
            "                <key>AMParameterProperties</key>",
            "                <dict>",
            "                    <key>source</key>",
            "                    <dict/>",
            "                </dict>",
            "                <key>AMProvides</key>",
            "                <dict>",
            "                    <key>Container</key>",
            "                    <string>List</string>",
            "                    <key>Types</key>",
            "                    <array>",
            "                        <string>com.apple.applescript.object</string>",
            "                    </array>",
            "                </dict>",
            "                <key>ActionBundlePath</key>",
            "                <string>/System/Library/Automator/Run AppleScript.action</string>",
            "                <key>ActionName</key>",
            "                <string>Run AppleScript</string>",
            "                <key>ActionParameters</key>",
            "                <dict>",
            "                    <key>source</key>",
            "                    <string>" + safeScript + "</string>",
            "                </dict>",
            "                <key>BundleIdentifier</key>",
            "                <string>com.apple.Automator.RunScript</string>",
            "                <key>CFBundleVersion</key>",
            "                <string>1.0.2</string>",
            "                <key>CanShowSelectedItemsWhenRun</key>",
            "                <false/>",
            "                <key>CanShowWhenRun</key>",
            "                <true/>",
            "                <key>Category</key>",
            "                <array>",
            "                    <string>AMCategoryUtilities</string>",
            "                </array>",
            "                <key>Class Name</key>",
            "                <string>RunScriptAction</string>",
            "                <key>InputUUID</key>",
            "                <string>E7C817C6-0A05-4309-B4A1-21B0A06540EB</string>",
            "                <key>Keywords</key>",
            "                <array>",
            "                    <string>Run</string>",
            "                </array>",
            "                <key>OutputUUID</key>",
            "                <string>29B53A37-9759-4D2A-8B8D-A8A1C50C3A0A</string>",
            "                <key>UUID</key>",
            "                <string>8D0C95CC-9407-4C01-BA37-77CD05F2BA3C</string>",
            "                <key>UnlocalizedApplications</key>",
            "                <array>",
            "                    <string>Automator</string>",
            "                </array>",
            "                <key>arguments</key>",
            "                <dict>",
            "                    <key>0</key>",
            "                    <dict>",
            "                        <key>default value</key>",
            "                        <string>" + scriptParam + "</string>",
            "                        <key>name</key>",
            "                        <string>source</string>",
            "                        <key>required</key>",
            "                        <string>0</string>",
            "                        <key>type</key>",
            "                        <string>0</string>",
            "                        <key>uuid</key>",
            "                        <string>0</string>",
            "                    </dict>",
            "                </dict>",
            "                <key>conversionLabel</key>",
            "                <integer>0</integer>",
            "                <key>isViewVisible</key>",
            "                <integer>1</integer>",
            "                <key>location</key>",
            "                <string>309.000000:315.000000</string>",
            "                <key>nibPath</key>",
            "                <string>/System/Library/Automator/Run AppleScript.action/Contents/Resources/Base.lproj/main.nib</string>",
            "            </dict>",
            "            <key>isViewVisible</key>",
            "            <integer>1</integer>",
            "        </dict>",
            "    </array>",
            "    <key>connectors</key>",
            "    <dict/>",
            "    <key>workflowMetaData</key>",
            "    <dict>",
            "        <key>applicationBundleIDsByPath</key>",
            "        <dict/>",
            "        <key>applicationPaths</key>",
            "        <array/>",
            "        <key>inputTypeIdentifier</key>",
            "        <string>com.apple.Automator.nothing</string>",
            "        <key>outputTypeIdentifier</key>",
            "        <string>com.apple.Automator.nothing</string>",
            "        <key>presentationMode</key>",
            "        <integer>11</integer>",
            "        <key>processesInput</key>",
            "        <false/>",
            "        <key>serviceApplicationBundleID</key>",
            "        <string>com.apple.finder</string>",
            "        <key>serviceApplicationPath</key>",
            "        <string>/System/Library/CoreServices/Finder.app</string>",
            "        <key>serviceInputTypeIdentifier</key>",
            "        <string>com.apple.Automator.nothing</string>",
            "        <key>serviceOutputTypeIdentifier</key>",
            "        <string>com.apple.Automator.nothing</string>",
            "        <key>serviceProcessesInput</key>",
            "        <false/>",
            "        <key>systemImageName</key>",
            "        <string>NSTouchBarDocument</string>",
            "        <key>useAutomaticInputType</key>",
            "        <false/>",
            "        <key>workflowTypeIdentifier</key>",
            "        <string>com.apple.Automator.servicesMenu</string>",
            "    </dict>",
            "</dict>",
            "</plist>"
        ].joined(separator: "\n")
        
        try infoPlist.write(to: contentsDir.appendingPathComponent("Info.plist"), atomically: true, encoding: .utf8)
        try wflow.write(to: contentsDir.appendingPathComponent("document.wflow"), atomically: true, encoding: .utf8)
        
        print("Quick Action installed successfully to " + workflowDir.path)
        print("Enable it in System Settings > Keyboard > Keyboard Shortcuts > Services > Files and Folders.")
    } catch {
        print("Failed to install quick action: " + error.localizedDescription)
    }
}

// MARK: - Main Logic
do {
    try ConfigManager.shared.setup()
} catch {
    print("Failed to setup config: " + error.localizedDescription)
    exit(1)
}

let args = CommandLine.arguments
if args.count < 2 {
    print("Usage: flux <command>")
    print("Commands:")
    print("  daemon                  Run background daemon")
    print("  install-daemon          Install and start daemon via launchctl")
    print("  install-quick-action    Install Finder quick action")
    print("  history list            List clipboard history")
    print("  history copy <index>    Copy clipboard item")
    print("  snippet add <name> <t>  Add a snippet")
    print("  snippet list            List snippets")
    print("  snippet copy <name>     Copy snippet")
    print("  create-file <dir> <nm>  Create file from template")
    exit(0)
}

let command = args[1]

switch command {
case "daemon":
    runDaemon()
case "install-daemon":
    installDaemon()
case "install-quick-action":
    installQuickAction()
case "history":
    if args.count > 2 && args[2] == "copy" {
        if args.count > 3, let idx = Int(args[3]) {
            if ClipboardManager.shared.copyItem(at: idx) {
                print("Copied item.")
            } else { print("Invalid index.") }
        }
    } else {
        listHistory()
    }
case "snippet":
    if args.count > 2 {
        let sub = args[2]
        do {
            var snippets = try loadSnippets()
            if sub == "add" && args.count > 4 {
                snippets[args[3]] = args[4]
                try saveSnippets(snippets)
                print("Added snippet.")
            } else if sub == "copy" && args.count > 3 {
                if let t = snippets[args[3]] {
                    let pb = NSPasteboard.general
                    pb.clearContents()
                    pb.setString(t, forType: .string)
                    print("Copied snippet.")
                } else { print("Not found.") }
            } else {
                for (k, v) in snippets {
                    print(k + ": " + v)
                }
            }
        } catch { print("Error loading snippets.") }
    } else {
        do {
            let snippets = try loadSnippets()
            for (k, v) in snippets {
                print(k + ": " + v)
            }
        } catch {}
    }
case "create-file":
    if args.count > 3 {
        let targetDir = args[2]
        let fileName = args[3]
        let ext = (fileName as NSString).pathExtension
        let fm = FileManager.default
        let targetURL = URL(fileURLWithPath: targetDir).appendingPathComponent(fileName)
        
        if fm.fileExists(atPath: targetURL.path) {
            print("File already exists at " + targetURL.path)
            exit(1)
        }
        
        var templateFound = false
        if !ext.isEmpty {
            if let templates = try? fm.contentsOfDirectory(atPath: ConfigManager.shared.templatesDirectory.path) {
                for template in templates {
                    if (template as NSString).pathExtension == ext {
                        let templateURL = ConfigManager.shared.templatesDirectory.appendingPathComponent(template)
                        try? fm.copyItem(at: templateURL, to: targetURL)
                        templateFound = true
                        print("Created " + fileName + " from template " + template)
                        break
                    }
                }
            }
        }
        if !templateFound {
            fm.createFile(atPath: targetURL.path, contents: Data(), attributes: nil)
            print("Created empty file " + fileName)
        }
    }
default:
    print("Unknown command: " + command)
}
