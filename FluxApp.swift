import SwiftUI
import AppKit
import Carbon
import WebKit
import ServiceManagement

// MARK: - Models & Logic
struct ClipboardItem: Codable, Identifiable {
    let id: UUID
    let timestamp: Date
    let text: String
}

struct Scratchpad: Codable, Identifiable {
    let id: UUID
    var title: String
    var content: String
    var lastEdit: Date
}

struct CustomExtension: Codable, Identifiable, Equatable {
    var id = UUID()
    var name: String
    var ext: String
    var iconName: String
}

struct AppInfo: Identifiable, Comparable {
    let id: String // bundleId
    let name: String
    
    static func < (lhs: AppInfo, rhs: AppInfo) -> Bool {
        lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
    }
}

struct Language: Codable, Identifiable, Hashable {
    let id: String
    let name: String
}

struct Shortcut: Codable, Equatable {
    var key: String
    var keyCode: UInt16
    var modifiers: UInt
    
    var displayString: String {
        var str = ""
        let mods = NSEvent.ModifierFlags(rawValue: modifiers)
        if mods.contains(.control) { str += "⌃" }
        if mods.contains(.option) { str += "⌥" }
        if mods.contains(.shift) { str += "⇧" }
        if mods.contains(.command) { str += "⌘" }
        return str + key.uppercased()
    }
}

// 0=Control, 1=Command, 2=Option, 3=Custom
struct AppSettings: Codable {
    var clipboardLimit: Int = 1000
    var toggleShortcut: Shortcut? = Shortcut(key: "Space", keyCode: 49, modifiers: NSEvent.ModifierFlags.control.rawValue)
    var toggleModifierMode: Int = 0  // 0=Control, 1=Command, 2=Option, 3=Custom
    var tabShortcuts: [Int: Shortcut] = [
        0: Shortcut(key: "1", keyCode: 18, modifiers: NSEvent.ModifierFlags.command.rawValue),
        1: Shortcut(key: "2", keyCode: 19, modifiers: NSEvent.ModifierFlags.command.rawValue),
        2: Shortcut(key: "3", keyCode: 20, modifiers: NSEvent.ModifierFlags.command.rawValue),
        3: Shortcut(key: "4", keyCode: 21, modifiers: NSEvent.ModifierFlags.command.rawValue),
        4: Shortcut(key: "5", keyCode: 23, modifiers: NSEvent.ModifierFlags.command.rawValue)
    ]
    var hasOnboarded: Bool = false
    var isDraggable: Bool = true
    var isResizable: Bool = false
    var glassOpacity: Double = 0.0  // 0=fully transparent glass, 1=fully opaque dark bg
    var launchAtLogin: Bool = false
    var customExtensions: [CustomExtension] = []
    var language: String = "en"
    
    enum CodingKeys: String, CodingKey {
        case clipboardLimit
        case toggleShortcut
        case toggleModifierMode
        case tabShortcuts
        case hasOnboarded
        case isDraggable
        case isResizable
        case glassOpacity
        case launchAtLogin
        case customExtensions
        case language
        case blacklistedApps
    }
    
    var blacklistedApps: [String] = []
    
    init() {}
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        clipboardLimit = try container.decodeIfPresent(Int.self, forKey: .clipboardLimit) ?? 1000
        toggleShortcut = try container.decodeIfPresent(Shortcut.self, forKey: .toggleShortcut) ?? Shortcut(key: "Space", keyCode: 49, modifiers: NSEvent.ModifierFlags.control.rawValue)
        toggleModifierMode = try container.decodeIfPresent(Int.self, forKey: .toggleModifierMode) ?? 0
        tabShortcuts = try container.decodeIfPresent([Int: Shortcut].self, forKey: .tabShortcuts) ?? [
            0: Shortcut(key: "1", keyCode: 18, modifiers: NSEvent.ModifierFlags.command.rawValue),
            1: Shortcut(key: "2", keyCode: 19, modifiers: NSEvent.ModifierFlags.command.rawValue),
            2: Shortcut(key: "3", keyCode: 20, modifiers: NSEvent.ModifierFlags.command.rawValue),
            3: Shortcut(key: "4", keyCode: 21, modifiers: NSEvent.ModifierFlags.command.rawValue),
            4: Shortcut(key: "5", keyCode: 23, modifiers: NSEvent.ModifierFlags.command.rawValue)
        ]
        hasOnboarded = try container.decodeIfPresent(Bool.self, forKey: .hasOnboarded) ?? false
        isDraggable = try container.decodeIfPresent(Bool.self, forKey: .isDraggable) ?? true
        isResizable = try container.decodeIfPresent(Bool.self, forKey: .isResizable) ?? false
        glassOpacity = try container.decodeIfPresent(Double.self, forKey: .glassOpacity) ?? 0.0
        launchAtLogin = try container.decodeIfPresent(Bool.self, forKey: .launchAtLogin) ?? false
        customExtensions = try container.decodeIfPresent([CustomExtension].self, forKey: .customExtensions) ?? []
        language = try container.decodeIfPresent(String.self, forKey: .language) ?? "en"
        blacklistedApps = try container.decodeIfPresent([String].self, forKey: .blacklistedApps) ?? []
    }
}

class FluxStore: ObservableObject {
    @Published var history: [ClipboardItem] = []
    @Published var snippets: [String: String] = [:]
    @Published var recentColors: [String] = []
    @Published var scratchpads: [Scratchpad] = []
    @Published var selectedTab: Int = 0
    @Published var saveColorHistory: Bool = true
    @Published var settings = AppSettings()
    @Published var hasAccessibilityPermission: Bool = AXIsProcessTrusted()
    @Published var isServiceInstalled: Bool = false
    
    @Published var translations: [String: String] = [:]
    @Published var supportedLanguages: [Language] = [Language(id: "en", name: "English")]
    @Published var installedApps: [AppInfo] = []
    
    var allTranslations: [String: [String: String]] = [:]
    var translationInProgress = Set<String>()
    let translationsFile: URL
    
    let brandGlossary = ["Flux": "Flux"]
    
    private var lastCreationTime: Date = .distantPast
    private var lastChangeCount: Int = NSPasteboard.general.changeCount
    
    let configDir = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".flux")
    let clipboardFile: URL
    let snippetsFile: URL
    let colorsFile: URL
    let scratchpadsFile: URL
    let settingsFile: URL
    
    init() {
        clipboardFile = configDir.appendingPathComponent("clipboard.json")
        snippetsFile = configDir.appendingPathComponent("snippets.json")
        colorsFile = configDir.appendingPathComponent("colors.json")
        scratchpadsFile = configDir.appendingPathComponent("scratchpads.json")
        settingsFile = configDir.appendingPathComponent("settings.json")
        translationsFile = configDir.appendingPathComponent("translations.json")
        
        // Ensure configuration directory exists before loading/saving
        try? FileManager.default.createDirectory(at: configDir, withIntermediateDirectories: true)
        
        if let data = try? Data(contentsOf: translationsFile),
           let dict = try? JSONDecoder().decode([String: [String: String]].self, from: data) {
            allTranslations = dict
        }
        
        if let saveHistory = UserDefaults.standard.object(forKey: "saveColorHistory") as? Bool {
            saveColorHistory = saveHistory
        }
        loadAll()
        fetchLanguages()
        
        if scratchpads.isEmpty {
            scratchpads = [Scratchpad(id: UUID(), title: "Main Notes", content: "", lastEdit: Date())]
            saveScratchpads()
        }
        
        setLanguage(settings.language)
        checkServiceInstallation()
        startMonitoring()
        scanInstalledApps()
        
        // Safety: Ensure Flux is never in the blacklist
        if settings.blacklistedApps.contains("com.flux.ui") {
            settings.blacklistedApps.removeAll { $0 == "com.flux.ui" }
            saveSettings()
        }
    }
    
    func checkServiceInstallation() {
        let servicesDir = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Services")
        let workflowDir = servicesDir.appendingPathComponent("Copy Exact Path.workflow")
        isServiceInstalled = FileManager.default.fileExists(atPath: workflowDir.path)
    }
    
    func startMonitoring() {
        Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { _ in
            let pb = NSPasteboard.general
            if pb.changeCount != self.lastChangeCount {
                self.lastChangeCount = pb.changeCount
                
                // Don't save if the pasteboard content is sensitive/concealed
                let concealedType = NSPasteboard.PasteboardType("org.nspasteboard.ConcealedType")
                if pb.types?.contains(concealedType) == true { return }
                
                // Don't save if the source app is blacklisted
                if let frontmost = NSWorkspace.shared.frontmostApplication?.bundleIdentifier {
                    if self.settings.blacklistedApps.contains(frontmost) { return }
                }

                if let str = pb.string(forType: .string), !str.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    DispatchQueue.main.async {
                        if self.history.first?.text != str {
                            let item = ClipboardItem(id: UUID(), timestamp: Date(), text: str)
                            self.history.insert(item, at: 0)
                            self.saveHistory()
                        }
                    }
                }
            }
        }
    }
    
    func loadAll() {
        do {
            if let data = try? Data(contentsOf: clipboardFile) {
                history = try JSONDecoder().decode([ClipboardItem].self, from: data)
            }
            if let data = try? Data(contentsOf: snippetsFile) {
                snippets = try JSONDecoder().decode([String: String].self, from: data)
            }
            if let data = try? Data(contentsOf: colorsFile) {
                recentColors = try JSONDecoder().decode([String].self, from: data)
            }
            if let data = try? Data(contentsOf: scratchpadsFile) {
                scratchpads = try JSONDecoder().decode([Scratchpad].self, from: data)
            }
            if let data = try? Data(contentsOf: settingsFile) {
                settings = try JSONDecoder().decode(AppSettings.self, from: data)
            } else {
                saveSettings()
            }
        } catch { 
            print("Settings loading error: \(error)")
        }
    }
    
    func saveHistory() {
        if history.count > settings.clipboardLimit { history = Array(history.prefix(settings.clipboardLimit)) }
        if let data = try? JSONEncoder().encode(history) { try? data.write(to: clipboardFile) }
    }

    func clearHistory() {
        history = []
        saveHistory()
    }
    
    func deleteHistoryItem(id: UUID) {
        history.removeAll(where: { $0.id == id })
        saveHistory()
    }
    
    func saveSnippets() {
        if let data = try? JSONEncoder().encode(snippets) { try? data.write(to: snippetsFile) }
    }
    
    func saveColors() {
        if let data = try? JSONEncoder().encode(recentColors) { try? data.write(to: colorsFile) }
    }
    
    func saveSettings() {
        do {
            let data = try JSONEncoder().encode(settings)
            try data.write(to: settingsFile)
        } catch {
            print("Failed to save settings: \(error)")
        }
    }
    
    func toggleColorHistory() {
        saveColorHistory.toggle()
        UserDefaults.standard.set(saveColorHistory, forKey: "saveColorHistory")
    }
    
    func saveScratchpads() {
        if let data = try? JSONEncoder().encode(scratchpads) { try? data.write(to: scratchpadsFile) }
    }
    
    func getActiveFinderPath() -> String {
        let script = """
        tell application "Finder"
            try
                if (count of selection) > 0 then
                    set theItem to item 1 of selection
                    set theKind to (kind of theItem)
                    if theKind is "Folder" or theKind is "Volume" or theKind is "Disk" or theKind is "Disk Image" then
                        return POSIX path of (theItem as text)
                    else
                        return POSIX path of (container of theItem as text)
                    end if
                else if (count of Finder windows) > 0 then
                    return POSIX path of (target of front Finder window as text)
                else
                    return POSIX path of (path to desktop folder as text)
                end if
            on error
                return POSIX path of (path to desktop folder as text)
            end try
        end tell
        """
        let task = Process()
        task.launchPath = "/usr/bin/osascript"
        task.arguments = ["-e", script]
        let pipe = Pipe(); task.standardOutput = pipe; task.launch()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let result = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return result.isEmpty ? (FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Desktop").path) : result
    }

    func createFile(extension ext: String, at path: String? = nil) {
        if Date().timeIntervalSince(lastCreationTime) < 0.4 { return }
        lastCreationTime = Date()
        
        let targetDirStr = path ?? getActiveFinderPath()
        let targetDir = URL(fileURLWithPath: targetDirStr)
        var finalURL = targetDir.appendingPathComponent("untitled." + ext.lowercased())
        var count = 1
        while FileManager.default.fileExists(atPath: finalURL.path) {
            count += 1
            finalURL = targetDir.appendingPathComponent("untitled \(count)." + ext.lowercased())
        }
        FileManager.default.createFile(atPath: finalURL.path, contents: Data())
    }
    
    func prepareDragFile(extension ext: String) -> URL {
        let tempDir = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("flux_drag")
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        let fileURL = tempDir.appendingPathComponent("untitled." + ext)
        if !FileManager.default.fileExists(atPath: fileURL.path) {
            FileManager.default.createFile(atPath: fileURL.path, contents: Data())
        }
        return fileURL
    }
    
    func setLanguage(_ lang: String) {
        settings.language = lang
        saveSettings()
        if lang == "en" {
            translations = [:]
        } else {
            translations = allTranslations[lang] ?? [:]
        }
    }

    func T(_ text: String, context: String? = nil) -> String {
        let lang = settings.language
        if lang == "en" || lang.isEmpty { return text }
        
        // Always respect brand glossary for exact matches
        if let brand = brandGlossary[text] { return brand }
        
        // Use a composite key for context-specific translations
        let key = context != nil ? "\(text)|\(context!)" : text
        
        if let translated = translations[key] {
            // Safety check: if any protected term was in the original but
            // got dropped by the translator, return the original to be safe.
            let protected = ["Flux", "Copy Exact Path", "Services"]
            for term in protected {
                if text.contains(term) && !translated.contains(term) {
                    return text
                }
            }
            return translated
        }
        
        if !translationInProgress.contains(key) {
            translationInProgress.insert(key)
            translateBackground(text: text, context: context, to: lang)
        }
        return text
    }

    private func translateBackground(text: String, context: String?, to lang: String) {
        let key = context != nil ? "\(text)|\(context!)" : text
        
        // Protected terms that must survive translation unchanged.
        // Each entry is (original term, unique placeholder).
        let protectedTerms: [(String, String)] = [
            ("Copy Exact Path",  "COPY_EXACT_PATH_TOKEN"),
            ("Services",         "SERVICES_TOKEN"),
            ("Flux",             "FLUX_BRAND_TOKEN"),
        ]
        
        var preparedText = text
        for (term, token) in protectedTerms {
            preparedText = preparedText.replacingOccurrences(of: term, with: token)
        }
        
        guard let encoded = preparedText.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "https://translate.googleapis.com/translate_a/single?client=gtx&sl=en&tl=\(lang)&dt=t&q=\(encoded)") else { return }
        
        URLSession.shared.dataTask(with: url) { data, response, error in
            DispatchQueue.main.async { self.translationInProgress.remove(key) }
            if let data = data,
               let json = try? JSONSerialization.jsonObject(with: data, options: []) as? [Any],
               let sentences = json.first as? [[Any]] {
                var translatedText = ""
                for sentence in sentences {
                    if let part = sentence.first as? String { translatedText += part }
                }
                
                // Restore each protected term, handling common translator mutations
                // (lowercasing, splitting on underscores, adding spaces, etc.)
                for (term, token) in protectedTerms {
                    let variations = [
                        token,
                        token.lowercased(),
                        token.replacingOccurrences(of: "_", with: " "),
                        token.lowercased().replacingOccurrences(of: "_", with: " "),
                    ]
                    for v in variations {
                        translatedText = translatedText.replacingOccurrences(of: v, with: term)
                    }
                }
                
                if !translatedText.isEmpty {
                    DispatchQueue.main.async {
                        var langDict = self.allTranslations[lang] ?? [:]
                        langDict[key] = translatedText
                        self.allTranslations[lang] = langDict
                        if self.settings.language == lang {
                            self.translations[key] = translatedText
                        }
                        if let data = try? JSONEncoder().encode(self.allTranslations) {
                            try? data.write(to: self.translationsFile)
                        }
                    }
                }
            }
        }.resume()
    }

    func fetchLanguages() {
        guard let url = URL(string: "https://translate.googleapis.com/translate_a/l?client=gtx&hl=en") else { return }
        URLSession.shared.dataTask(with: url) { data, response, error in
            if let data = data,
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let tl = json["tl"] as? [String: String] {
                let langs = tl.map { Language(id: $0.key, name: $0.value) }
                    .sorted { $0.name < $1.name }
                DispatchQueue.main.async {
                    self.supportedLanguages = langs
                }
            }
        }.resume()
    }

    func scanInstalledApps() {
        DispatchQueue.global(qos: .userInitiated).async {
            let fm = FileManager.default
            let appDirs = ["/Applications", "/System/Applications", NSHomeDirectory() + "/Applications"]
            var found = Set<String>()
            var apps: [AppInfo] = []
            
            for dir in appDirs {
                guard let contents = try? fm.contentsOfDirectory(atPath: dir) else { continue }
                for item in contents where item.hasSuffix(".app") {
                    let path = dir + "/" + item
                    if let bundle = Bundle(path: path), let bid = bundle.bundleIdentifier {
                        // Prevent blacklisting Flux itself
                        if bid == "com.flux.ui" { continue }
                        
                        if !found.contains(bid) {
                            let name = bundle.infoDictionary?["CFBundleName"] as? String 
                                    ?? bundle.infoDictionary?["CFBundleDisplayName"] as? String 
                                    ?? item.replacingOccurrences(of: ".app", with: "")
                            apps.append(AppInfo(id: bid, name: name))
                            found.insert(bid)
                        }
                    }
                }
            }
            
            let sorted = apps.sorted()
            DispatchQueue.main.async {
                self.installedApps = sorted
            }
        }
    }

    func installCopyPathService() {
        let fm = FileManager.default
        let tempDir = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let workflowDir = tempDir.appendingPathComponent("Copy Exact Path.workflow")
        let contentsDir = workflowDir.appendingPathComponent("Contents")
        
        do {
            if !fm.fileExists(atPath: contentsDir.path) {
                try fm.createDirectory(at: contentsDir, withIntermediateDirectories: true)
            }
            
            let infoPlist = """
            <?xml version="1.0" encoding="UTF-8"?>
            <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
            <plist version="1.0">
            <dict>
                <key>NSServices</key>
                <array>
                    <dict>
                        <key>NSMenuItem</key>
                        <dict>
                            <key>default</key>
                            <string>Copy Exact Path</string>
                        </dict>
                        <key>NSMessage</key>
                        <string>runWorkflowAsService</string>
                        <key>NSRequiredContext</key>
                        <dict>
                            <key>NSApplicationIdentifier</key>
                            <string>com.apple.finder</string>
                        </dict>
                        <key>NSSendTypes</key>
                        <array>
                            <string>public.item</string>
                            <string>public.file-url</string>
                        </array>
                    </dict>
                </array>
            </dict>
            </plist>
            """
            
            let documentWflow = """
            <?xml version="1.0" encoding="UTF-8"?>
            <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
            <plist version="1.0">
            <dict>
                <key>actions</key>
                <array>
                    <dict>
                        <key>action</key>
                        <dict>
                            <key>ActionParameters</key>
                            <dict>
                                <key>COMMAND_STRING</key>
                                <string>printf "%s" "$1" | pbcopy</string>
                                <key>CheckedForUserDefaultShell</key>
                                <true/>
                                <key>inputMethod</key>
                                <integer>1</integer>
                                <key>shell</key>
                                <string>/bin/bash</string>
                                <key>source</key>
                                <string></string>
                            </dict>
                            <key>BundleIdentifier</key>
                            <string>com.apple.RunShellScript</string>
                        </dict>
                    </dict>
                </array>
                <key>workflowMetaData</key>
                <dict>
                    <key>serviceInputTypeIdentifier</key>
                    <string>com.apple.Automator.fileSystemObject</string>
                    <key>workflowTypeIdentifier</key>
                    <string>com.apple.Automator.servicesMenu</string>
                </dict>
            </dict>
            </plist>
            """
            
            try infoPlist.write(to: contentsDir.appendingPathComponent("Info.plist"), atomically: true, encoding: .utf8)
            try documentWflow.write(to: contentsDir.appendingPathComponent("document.wflow"), atomically: true, encoding: .utf8)
            
            // Open the workflow file - macOS will detect it's a Service 
            // and show the native "Do you want to install this?" dialog.
            NSWorkspace.shared.open(workflowDir)
            
            // Start a small timer to check if the user completed the install
            Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] timer in
                self?.checkServiceInstallation()
                if self?.isServiceInstalled == true {
                    timer.invalidate()
                }
            }
            
        } catch {
            print("Failed to prepare service installer: \(error)")
        }
    }
}

// Removed Event Tap (SnippetExpander) due to persistent macOS security/sandbox interference.
// Snippets are now used strictly as a manual template library in the UI.

// MARK: - UI Components
struct SVGView: View {
    let filename: String
    @Environment(\.colorScheme) var colorScheme
    
    func makeNSView(context: Context) -> WKWebView {
        let webView = WKWebView(); webView.setValue(false, forKey: "drawsBackground"); return webView
    }
    
    func updateNSView(_ nsView: WKWebView, context: Context) {
        let bundlePath = Bundle.main.path(forResource: filename, ofType: "svg", inDirectory: "Icons")
        let homePath = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".flux/icons/\(filename).svg").path
        
        let finalPath = bundlePath ?? homePath
        
        if var svg = try? String(contentsOfFile: finalPath) {
            // Standardize colors
            if ["markdown", "txt", "json", "gear"].contains(filename) { 
                svg = svg.replacingOccurrences(of: "stroke=\"currentColor\"", with: "stroke=\"white\"")
                         .replacingOccurrences(of: "fill=\"currentColor\"", with: "fill=\"white\"")
            }
            let html = "<html><body style=\"margin:0;padding:0;display:flex;justify-content:center;align-items:center;background:transparent;user-select:none;-webkit-user-select:none;cursor:default;\">\(svg)</body><style>svg { width: 100%; height: 100%; pointer-events: none; color: white; } * { color: white !important; }</style></html>"
            nsView.loadHTMLString(html, baseURL: nil)
        }
    }
}
extension SVGView: NSViewRepresentable {}

struct VisualEffectView: NSViewRepresentable {
    var glassOpacity: Double = 0.0  // 0 = pure glass, 1 = opaque dark
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.blendingMode = .behindWindow
        view.state = .active
        view.material = .popover
        return view
    }
    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.alphaValue = 1.0 - CGFloat(glassOpacity)
    }
}

struct OnboardingStep {
    let icon: String
    let title: String
    let body: String
    let highlightTab: Int?   // which tab to visually spotlight (-1 = none, -2 = settings gear)
}

let onboardingSteps: [OnboardingStep] = [
    OnboardingStep(icon: "hand.wave.fill",       title: "Welcome to Flux",         body: "Your all-in-one macOS productivity dashboard — living quietly in your menu bar. This quick tour will show you every feature.",               highlightTab: nil),
    OnboardingStep(icon: "plus.viewfinder",       title: "Create Files Instantly",   body: "Tab 1: Tap any file type icon to create that file in the currently active Finder folder. You can also drag the icon directly into any Finder window.", highlightTab: 0),
    OnboardingStep(icon: "doc.on.clipboard",     title: "Clipboard History",         body: "Tab 2: Everything you copy is saved here automatically. Click any item to copy it again. The list is searchable.",                                    highlightTab: 1),
    OnboardingStep(icon: "text.quote",            title: "Snippet Library",           body: "Tab 3: Save reusable text snippets — emails, templates, code. Click to copy to clipboard instantly.",                                                  highlightTab: 2),
    OnboardingStep(icon: "paintpalette.fill",     title: "Color Picker",              body: "Tab 4: Pick any pixel color on your screen with the eyedropper. Values are shown in HEX, RGB and HSL — click each to copy.",                         highlightTab: 3),
    OnboardingStep(icon: "pencil.and.outline",    title: "Scratchpad",                body: "Tab 5: A private multi-note scratchpad. Hover the left edge to show the sidebar, click + to add notes, and right-click to rename or delete.",        highlightTab: 4),
    OnboardingStep(icon: "doc.badge.arrow.up",    title: "Copy Exact File Path",     body: "Right-click any file in Finder and choose 'Copy Exact Path' from the Services menu. You can install this shortcut now with one click below.",  highlightTab: nil),
    OnboardingStep(icon: "keyboard",              title: "Global Hotkey",             body: "Press your configured hotkey to show or hide Flux. Default is Ctrl. Use Cmd + 1-5 to quickly switch between tabs. Change these in Settings.",                        highlightTab: -2),
]

struct OnboardingView: View {
    @ObservedObject var store: FluxStore
    @Binding var isShowingSettings: Bool
    @State private var step = 0
    @Environment(\.colorScheme) var colorScheme

    var current: OnboardingStep { onboardingSteps[step] }
    var isLast: Bool { step == onboardingSteps.count - 1 }

    var body: some View {
        ZStack {
            // Dim overlay
            Color.black.opacity(0.75)
                .edgesIgnoringSafeArea(.all)

            VStack(spacing: 0) {
                Spacer()

                // Step card
                VStack(spacing: 20) {
                    // Progress dots
                    HStack(spacing: 6) {
                        ForEach(0..<onboardingSteps.count, id: \.self) { i in
                            Circle()
                                .fill(i == step ? Color.blue : Color.primary.opacity(0.2))
                                .frame(width: i == step ? 8 : 5, height: i == step ? 8 : 5)
                                .animation(.easeInOut(duration: 0.3), value: step)
                        }
                    }

                    Image(systemName: current.icon)
                        .font(.system(size: 48, weight: .light))
                        .foregroundStyle(Color.blue)
                        .transition(.scale.combined(with: .opacity))
                        .id(current.icon)

                    VStack(spacing: 8) {
                        Text(store.T(current.title, context: "Onboarding title"))
                            .font(.system(size: 22, weight: .bold))
                            .foregroundColor(.primary)
                            .multilineTextAlignment(.center)
                        Text(store.T(current.body, context: "Onboarding description for \(current.title)"))
                            .font(.system(size: 14))
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                            .lineSpacing(3)
                            
                        if step == 0 {
                            Picker("", selection: Binding(
                                get: { store.settings.language },
                                set: { store.setLanguage($0) }
                            )) {
                                ForEach(store.supportedLanguages) { lang in
                                    Text(lang.name).tag(lang.id)
                                }
                            }
                            .pickerStyle(.menu)
                            .frame(width: 200)
                            .labelsHidden()
                            .padding(.top, 16)
                        }
                        
                        if step == 6 {
                            if store.isServiceInstalled {
                                HStack(spacing: 12) {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundColor(.green)
                                        .font(.system(size: 24))
                                    Text(store.T("Installed Successfully!"))
                                        .font(.headline)
                                        .foregroundColor(.green)
                                }
                                .padding(.top, 16)
                                .transition(.scale.combined(with: .opacity))
                            } else {
                                Button(action: {
                                    withAnimation(.spring(response: 0.5, dampingFraction: 0.7)) {
                                        store.installCopyPathService()
                                    }
                                }) {
                                    HStack {
                                        Image(systemName: "plus.circle.fill")
                                        Text(store.T("Install Shortcut Now"))
                                    }
                                    .font(.headline)
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 20).padding(.vertical, 10)
                                    .background(Color.green)
                                    .cornerRadius(10)
                                }
                                .buttonStyle(.plain)
                                .padding(.top, 16)
                                .transition(.opacity)
                            }
                        }
                    }

                    // Nav buttons
                    HStack(spacing: 12) {
                        if step > 0 {
                            Button(action: { withAnimation(.easeInOut(duration: 0.3)) { step -= 1 } }) {
                                Text(store.T("← Previous"))
                                    .foregroundColor(.primary.opacity(0.6))
                                    .padding(.horizontal, 16).padding(.vertical, 10)
                                    .background(Color.primary.opacity(0.08))
                                    .cornerRadius(10)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                        Spacer()
                        if isLast {
                            Button(action: {
                                withAnimation {
                                    store.settings.hasOnboarded = true
                                    store.saveSettings()
                                    isShowingSettings = true
                                }
                            }) {
                                Text(store.T("Get Started →"))
                                    .font(.headline)
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 24).padding(.vertical, 10)
                                    .background(Color.blue)
                                    .cornerRadius(10)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        } else {
                            Button(action: { withAnimation(.easeInOut(duration: 0.3)) { step += 1 } }) {
                                Text(store.T("Next →"))
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 24).padding(.vertical, 10)
                                    .background(Color.blue)
                                    .cornerRadius(10)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .padding(28)
                .background(
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .fill(colorScheme == .dark ? Color(white: 0.12).opacity(0.98) : Color.white.opacity(0.98))
                        .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).stroke(Color.primary.opacity(0.08), lineWidth: 1))
                )
                .padding(.horizontal, 20)

                Spacer().frame(height: 32)
            }
        }
        .animation(.easeInOut(duration: 0.25), value: step)
    }
}

struct MainView: View {
    @ObservedObject var store: FluxStore
    @Environment(\.colorScheme) var colorScheme
    @State private var searchText = ""
    @State private var customExt = ""
    @State private var isShowingOther = false
    @State private var isShowingAddSnippet = false
    @State private var isShowingSettings = false
    @State private var forceExpandSidebar = false
    
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                if isShowingSettings {
                    Text(store.T("Settings", context: "Header title for settings view")).font(.system(size: 18, weight: .bold)).foregroundColor(.primary).transition(.opacity)
                } else if store.selectedTab != 0 && !isShowingAddSnippet {
                    HStack {
                        Image(systemName: "magnifyingglass").foregroundColor(.gray)
                        TextField(store.T("Search...", context: "Search bar placeholder"), text: $searchText).textFieldStyle(.plain)
                    }
                    .padding(10).background(Color.primary.opacity(0.1)).cornerRadius(12).transition(.move(edge: .top).combined(with: .opacity))
                    .onHover { inside in
                        if store.selectedTab == 4 {
                            withAnimation(.easeInOut(duration: 0.3)) {
                                forceExpandSidebar = inside
                            }
                        }
                    }
                } else if isShowingOther {
                    HStack(spacing: 10) {
                        Image(systemName: "doc.badge.plus").foregroundColor(.blue)
                        TextField(store.T("Extension (e.g. go, rs)"), text: $customExt)
                            .textFieldStyle(.plain)
                            .onSubmit {
                                let ext = customExt.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
                                if !ext.isEmpty { store.createFile(extension: ext) }
                                customExt = ""
                                withAnimation { isShowingOther = false }
                            }
                        Button(action: {
                            withAnimation { isShowingOther = false; customExt = "" }
                        }) { Image(systemName: "xmark.circle.fill").foregroundColor(.gray) }.buttonStyle(.plain)
                    }.padding(10).background(Color.primary.opacity(0.1)).cornerRadius(12).transition(.move(edge: .top).combined(with: .opacity))
                } else if isShowingAddSnippet {
                    Text(store.T("Snippet Editor")).font(.headline).foregroundColor(.blue).transition(.opacity)
                } else {
                    Text(store.T("Flux")).font(.system(size: 18, weight: .bold)).foregroundColor(.primary).transition(.opacity)
                }
                Spacer()
                
                if !isShowingSettings && !isShowingOther && !isShowingAddSnippet && (store.selectedTab == 0 || searchText.isEmpty) {
                    Picker("", selection: Binding(get: { store.selectedTab }, set: { store.selectedTab = $0 })) {
                        Image(systemName: "plus.viewfinder").tag(0)
                        Image(systemName: "doc.on.clipboard").tag(1)
                        Image(systemName: "text.quote").tag(2)
                        Image(systemName: "paintpalette.fill").tag(3)
                        Image(systemName: "pencil.and.outline").tag(4)
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 220)
                    .onChange(of: store.selectedTab) { _ in searchText = "" }
                }
                
                Button(action: { withAnimation(.easeInOut(duration: 0.3)) { isShowingSettings.toggle() } }) {
                    ZStack {
                        Circle()
                            .fill(isShowingSettings ? Color.blue.opacity(0.3) : Color.white.opacity(0.05))
                            .frame(width: 32, height: 32)
                        SVGView(filename: "gear")
                            .frame(width: 18, height: 18)
                            .foregroundColor(isShowingSettings ? .blue : .white)
                    }
                }
                .buttonStyle(.plain)
                .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.white.opacity(0.1), lineWidth: 0.5))
            }
            .padding()
            
            Divider().background(Color.white.opacity(0.1))
            
            ZStack {
                if isShowingSettings {
                    SettingsView(store: store)
                        .transition(.asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity), removal: .move(edge: .trailing).combined(with: .opacity)))
                } else {
                    Group {
                        if store.selectedTab == 0 {
                            FileGridView(store: store, isShowingOther: $isShowingOther)
                                .transition(.asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity), removal: .move(edge: .leading).combined(with: .opacity)))
                                .id(0)
                        } else if store.selectedTab == 1 {
                            ClipboardView(store: store, search: searchText)
                                .transition(.asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity), removal: .move(edge: .leading).combined(with: .opacity)))
                                .id(1)
                        } else if store.selectedTab == 2 {
                            SnippetView(store: store, search: searchText, isShowingAdd: $isShowingAddSnippet)
                                .transition(.asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity), removal: .move(edge: .leading).combined(with: .opacity)))
                                .id(2)
                        } else if store.selectedTab == 3 {
                            ColorPickerView(store: store)
                                .transition(.asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity), removal: .move(edge: .leading).combined(with: .opacity)))
                                .id(3)
                        } else {
                            ScratchpadView(store: store, search: searchText, forceExpand: $forceExpandSidebar)
                                .transition(.asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity), removal: .move(edge: .leading).combined(with: .opacity)))
                                .id(4)
                        }
                    }
                }
            }
        }
        .animation(.easeInOut(duration: 0.3), value: store.selectedTab)
        .animation(.easeInOut(duration: 0.3), value: isShowingAddSnippet)
        .animation(.easeInOut(duration: 0.3), value: isShowingOther)
        .animation(.easeInOut(duration: 0.3), value: isShowingSettings)
        .frame(width: 520, height: 480)
        .background(VisualEffectView(glassOpacity: store.settings.glassOpacity))
        .background(
            LinearGradient(
                colors: [Color.black.opacity(0.15 + store.settings.glassOpacity * 0.6), Color.blue.opacity(0.05 + store.settings.glassOpacity * 0.15)],
                startPoint: .topLeading, endPoint: .bottomTrailing
            )
        )
        .colorScheme(.dark)
        .clipShape(RoundedRectangle(cornerRadius: 32, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 32, style: .continuous).stroke(Color.white.opacity(0.1), lineWidth: 0.5))
        .overlay(
            Group {
                if !store.settings.hasOnboarded {
                    OnboardingView(store: store, isShowingSettings: $isShowingSettings)
                        .transition(.opacity)
                        .colorScheme(colorScheme)
                }
            }
        )
    }
}

struct SettingsView: View {
    @ObservedObject var store: FluxStore
    @State private var isRecordingHotkey: Int? = nil // -1 for main toggle, 0-4 for tabs
    @State private var isShowingAppPicker = false
    @State private var appSearch = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // Window & App Section
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Label(store.T("App Preferences"), systemImage: "macwindow").font(.headline)
                        Spacer()
                        Button(store.T("Show Onboarding")) {
                            store.settings.hasOnboarded = false
                            store.saveSettings()
                        }.buttonStyle(.bordered).controlSize(.small)
                    }
                    Toggle(store.T("Window is Draggable"), isOn: Binding(
                        get: { store.settings.isDraggable },
                        set: { 
                            store.settings.isDraggable = $0
                            store.saveSettings()
                            if let window = NSApp.windows.first(where: { $0 is FluxWindow }) {
                                window.isMovableByWindowBackground = $0
                            }
                        }
                    )).toggleStyle(SwitchToggleStyle(tint: .blue))
                    
                    Toggle(store.T("Launch at Login"), isOn: Binding(
                        get: { store.settings.launchAtLogin },
                        set: { newVal in
                            store.settings.launchAtLogin = newVal
                            store.saveSettings()
                            if #available(macOS 13.0, *) {
                                if newVal {
                                    try? SMAppService.mainApp.register()
                                } else {
                                    try? SMAppService.mainApp.unregister()
                                }
                            }
                        }
                    )).toggleStyle(SwitchToggleStyle(tint: .blue))
                    
                    Divider().background(Color.white.opacity(0.1)).padding(.vertical, 4)
                    
                    HStack {
                        Label(store.T("Language"), systemImage: "globe").font(.headline)
                        Spacer()
                        Picker("", selection: Binding(
                            get: { store.settings.language },
                            set: { store.setLanguage($0) }
                        )) {
                            ForEach(store.supportedLanguages) { lang in
                                Text(lang.name).tag(lang.id)
                            }
                        }.frame(width: 180)
                    }
                }
                .padding().background(Color.white.opacity(0.03)).cornerRadius(16)
                
                // Clipboard Section
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Label(store.T("Clipboard History", context: "Settings section header"), systemImage: "doc.on.clipboard").font(.headline)
                        Spacer()
                        Button(store.T("Reset", context: "Button to reset clipboard limit")) { store.settings.clipboardLimit = 1000; store.saveSettings() }
                            .buttonStyle(.bordered).controlSize(.small)
                    }
                    HStack {
                        Slider(value: Binding(get: { Double(store.settings.clipboardLimit) }, set: { store.settings.clipboardLimit = Int($0) }), in: 10...5000)
                            .accentColor(.blue)
                        Text("\(store.settings.clipboardLimit) " + store.T("items", context: "Clipboard history limit")).font(.system(.body, design: .monospaced)).frame(width: 80)
                    }
                    Text(store.T("Adjust how many items to keep in your clipboard history.")).font(.caption).foregroundColor(.gray)
                }
                .padding().background(Color.white.opacity(0.03)).cornerRadius(16)
                
                // App Blacklist Section
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Label(store.T("Clipboard Blacklist"), systemImage: "nosign").font(.headline)
                        Spacer()
                        
                        Button(action: {
                            isShowingAppPicker = true
                        }) {
                            Label(store.T("Manage Apps"), systemImage: "plus.circle.fill")
                                .font(.subheadline)
                                .foregroundColor(.blue)
                        }
                        .buttonStyle(.plain)
                        .popover(isPresented: $isShowingAppPicker) {
                            VStack(spacing: 0) {
                                HStack {
                                    Image(systemName: "magnifyingglass").foregroundColor(.gray)
                                    TextField(store.T("Search apps..."), text: $appSearch)
                                        .textFieldStyle(.plain)
                                    if !appSearch.isEmpty {
                                        Button(action: { appSearch = "" }) {
                                            Image(systemName: "xmark.circle.fill").foregroundColor(.gray)
                                        }.buttonStyle(.plain)
                                    }
                                }
                                .padding(10)
                                .background(Color.black.opacity(0.2))
                                .cornerRadius(10)
                                .padding()
                                
                                List {
                                    let filtered = store.installedApps.filter { app in
                                        appSearch.isEmpty || app.name.localizedCaseInsensitiveContains(appSearch)
                                    }
                                    
                                    ForEach(filtered) { app in
                                        HStack {
                                            Text(app.name)
                                                .font(.system(size: 13))
                                            Spacer()
                                            if store.settings.blacklistedApps.contains(app.id) {
                                                Image(systemName: "checkmark.circle.fill")
                                                    .foregroundColor(.blue)
                                            }
                                        }
                                        .contentShape(Rectangle())
                                        .onTapGesture {
                                            if store.settings.blacklistedApps.contains(app.id) {
                                                store.settings.blacklistedApps.removeAll { $0 == app.id }
                                            } else {
                                                store.settings.blacklistedApps.append(app.id)
                                            }
                                            store.saveSettings()
                                        }
                                    }
                                }
                                .listStyle(.plain)
                                .frame(width: 300, height: 400)
                            }
                        }
                    }
                    
                    Text(store.T("Flux will not save clipboard history from these applications."))
                        .font(.caption).foregroundColor(.gray)
                    
                    if store.settings.blacklistedApps.isEmpty {
                        Text(store.T("No applications blacklisted"))
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(.gray.opacity(0.5))
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding(.vertical, 10)
                    } else {
                        VStack(spacing: 8) {
                            ForEach(store.settings.blacklistedApps, id: \.self) { bid in
                                HStack {
                                    if let app = NSWorkspace.shared.runningApplications.first(where: { $0.bundleIdentifier == bid }) {
                                        Text(app.localizedName ?? bid)
                                    } else {
                                        Text(bid)
                                    }
                                    Spacer()
                                    Button(action: {
                                        store.settings.blacklistedApps.removeAll { $0 == bid }
                                        store.saveSettings()
                                    }) {
                                        Image(systemName: "xmark.circle.fill").foregroundColor(.red.opacity(0.6))
                                    }.buttonStyle(.plain)
                                }
                                .padding(8)
                                .background(Color.white.opacity(0.05))
                                .cornerRadius(8)
                            }
                        }
                    }
                }
                .padding().background(Color.white.opacity(0.03)).cornerRadius(16)
                
                // Finder Service Section
                VStack(alignment: .leading, spacing: 12) {
                    Label(store.T("Finder Integration"), systemImage: "macwindow.badge.plus").font(.headline)
                    Text(store.T("Add 'Copy Exact Path' to your right-click Services menu."))
                        .font(.caption).foregroundColor(.gray)
                    
                    if store.isServiceInstalled {
                        HStack {
                            Image(systemName: "checkmark.circle.fill")
                            Text(store.T("Shortcut Installed"))
                        }
                        .foregroundColor(.green)
                        .padding(10)
                    } else {
                        Button(action: {
                            store.installCopyPathService()
                        }) {
                            HStack {
                                Image(systemName: "arrow.down.doc.fill")
                                Text(store.T("Install 'Copy Exact Path' Service"))
                            }
                            .frame(maxWidth: .infinity)
                            .padding(10)
                            .background(Color.blue.opacity(0.15))
                            .cornerRadius(10)
                        }
                        .buttonStyle(.plain)
                        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.blue.opacity(0.3), lineWidth: 1))
                    }
                    
                    Text(store.T("Note: You may need to relaunch Finder (Option + Right-click Finder icon -> Relaunch) for it to appear."))
                        .font(.system(size: 10))
                        .foregroundColor(.gray)
                }
                .padding().background(Color.white.opacity(0.03)).cornerRadius(16)
                
                // Keyboard Shortcuts Section
                VStack(alignment: .leading, spacing: 16) {
                    HStack {
                        Label(store.T("Keyboard Shortcuts"), systemImage: "keyboard").font(.headline)
                        Spacer()
                        Button(store.T("Reset All")) {
                            store.settings.toggleModifierMode = 0
                            store.settings.toggleShortcut = Shortcut(key: "Space", keyCode: 49, modifiers: NSEvent.ModifierFlags.control.rawValue)
                            store.settings.tabShortcuts = [
                                0: Shortcut(key: "1", keyCode: 18, modifiers: NSEvent.ModifierFlags.command.rawValue),
                                1: Shortcut(key: "2", keyCode: 19, modifiers: NSEvent.ModifierFlags.command.rawValue),
                                2: Shortcut(key: "3", keyCode: 20, modifiers: NSEvent.ModifierFlags.command.rawValue),
                                3: Shortcut(key: "4", keyCode: 21, modifiers: NSEvent.ModifierFlags.command.rawValue),
                                4: Shortcut(key: "5", keyCode: 23, modifiers: NSEvent.ModifierFlags.command.rawValue)
                            ]
                            store.saveSettings()
                        }
                        .buttonStyle(.bordered).controlSize(.small)
                    }
                    
                    VStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(store.T("Main Window Toggle")).font(.subheadline)
                            Picker(store.T("Toggle Mode"), selection: Binding(
                                get: { store.settings.toggleModifierMode },
                                set: { mode in
                                    store.settings.toggleModifierMode = mode
                                    switch mode {
                                    case 0: store.settings.toggleShortcut = Shortcut(key: "Control", keyCode: 59, modifiers: NSEvent.ModifierFlags.control.rawValue)
                                    case 1: store.settings.toggleShortcut = Shortcut(key: "Command", keyCode: 54, modifiers: NSEvent.ModifierFlags.command.rawValue)
                                    case 2: store.settings.toggleShortcut = Shortcut(key: "Option", keyCode: 58, modifiers: NSEvent.ModifierFlags.option.rawValue)
                                    default: break
                                    }
                                    store.saveSettings()
                                    NotificationCenter.default.post(name: NSNotification.Name("UpdateCarbonHotkey"), object: nil)
                                }
                            )) {
                                Text(store.T("⌃")).tag(0)
                                Text(store.T("⌘")).tag(1)
                                Text(store.T("⌥")).tag(2)
                                Text(store.T("...")).tag(3)
                            }
                            .pickerStyle(.menu)
                            .labelsHidden()
                            
                            if store.settings.toggleModifierMode == 3 {
                                HStack {
                                    Text(store.T("Record custom shortcut:")).font(.caption).foregroundColor(.gray)
                                    Spacer()
                                    Button(action: { isRecordingHotkey = -1 }) {
                                        Text(isRecordingHotkey == -1 ? store.T("Press shortcut...") : (store.settings.toggleShortcut?.displayString ?? store.T("None")))
                                            .frame(minWidth: 100).padding(6)
                                            .background(isRecordingHotkey == -1 ? Color.orange.opacity(0.3) : Color.black.opacity(0.3))
                                            .cornerRadius(8)
                                    }
                                    .buttonStyle(.plain)
                                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(isRecordingHotkey == -1 ? Color.orange : Color.white.opacity(0.1), lineWidth: 1))
                                }
                            }
                        }
                        .padding(10).background(Color.white.opacity(0.04)).cornerRadius(12)
                        
                        Divider().background(Color.white.opacity(0.1))
                        
                        Text(store.T("Tab Shortcuts")).font(.subheadline).foregroundColor(.gray)
                        ForEach(0..<5) { index in
                            HStack {
                                Text(store.T("Switch to Tab") + " \(index + 1)")
                                Spacer()
                                Button(action: { isRecordingHotkey = index }) {
                                    Text(isRecordingHotkey == index ? store.T("Press shortcut...") : (store.settings.tabShortcuts[index]?.displayString ?? store.T("None")))
                                        .frame(minWidth: 100).padding(6).background(isRecordingHotkey == index ? Color.orange.opacity(0.3) : Color.black.opacity(0.3)).cornerRadius(8)
                                }
                                .buttonStyle(.plain)
                                .overlay(RoundedRectangle(cornerRadius: 8).stroke(isRecordingHotkey == index ? Color.orange : Color.white.opacity(0.1), lineWidth: 1))
                            }
                        }
                    }
                }
                .padding().background(Color.white.opacity(0.03)).cornerRadius(16)
            }
            .padding(24)
        }
        .onAppear {
            NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
                if let index = isRecordingHotkey {
                    let mods = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
                    var key = event.charactersIgnoringModifiers?.uppercased() ?? ""
                    if event.keyCode == 49 { key = "Space" }
                    else if event.keyCode == 36 { key = "Return" }
                    else if event.keyCode == 53 { key = "Esc" }
                    else if event.keyCode == 48 { key = "Tab" }
                    if key.isEmpty { key = String(event.keyCode) }
                    
                    let shortcut = Shortcut(key: key, keyCode: event.keyCode, modifiers: mods.rawValue)
                    if index == -1 {
                        store.settings.toggleShortcut = shortcut
                        store.saveSettings()
                        NotificationCenter.default.post(name: NSNotification.Name("UpdateCarbonHotkey"), object: nil)
                    } else {
                        store.settings.tabShortcuts[index] = shortcut
                        store.saveSettings()
                    }
                    isRecordingHotkey = nil
                    return nil
                }
                return event
            }
        }
    }
}

struct FileGridView: View {
    let store: FluxStore; @Binding var isShowingOther: Bool
    @State private var justCreated: String? = nil
    let columns = [GridItem(.adaptive(minimum: 80))]
    let types: [String] = ["swift", "py", "js", "html", "css", "json", "md", "txt"]
    let displayNames: [String: String] = ["swift": "Swift", "py": "Python", "js": "JS", "html": "HTML", "css": "CSS", "json": "JSON", "md": "MD", "txt": "TXT"]
    let iconNames: [String: String] = ["swift": "swift", "py": "python", "js": "javascript", "html": "html5", "css": "css", "json": "json", "md": "markdown", "txt": "txt"]
    
    var body: some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 90))], spacing: 25) {
                ForEach(types, id: \.self) { ext in
                    VStack(spacing: 8) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 20, style: .continuous)
                                .fill(LinearGradient(colors: [Color(white: 0.28), Color(white: 0.22)], startPoint: .topLeading, endPoint: .bottomTrailing))
                                .opacity(0.9)
                                .frame(width: 74, height: 74)
                                .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(justCreated == ext ? Color.green.opacity(0.5) : Color.white.opacity(0.15), lineWidth: justCreated == ext ? 2 : 1))
                                .shadow(color: .black.opacity(0.3), radius: 10, x: 0, y: 5)
                            
                            SVGView(filename: iconNames[ext]!)
                                .frame(width: 38, height: 38)
                                .opacity(justCreated == ext ? 0 : 1)
                            
                            if justCreated == ext {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 30, weight: .bold))
                                    .foregroundColor(.green)
                                    .transition(.scale.combined(with: .opacity))
                            }
                        }
                        Text(store.T(displayNames[ext]!)).font(.system(size: 13, weight: .medium, design: .rounded)).foregroundColor(.white.opacity(0.85))
                    }
                    .onTapGesture {
                        store.createFile(extension: ext)
                        withAnimation(.easeInOut(duration: 0.3)) { justCreated = ext }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { withAnimation { if justCreated == ext { justCreated = nil } } }
                    }
                    .onDrag { NSItemProvider(contentsOf: store.prepareDragFile(extension: ext))! }
                }
                
                // Other — tap to reveal extension input
                VStack(spacing: 8) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .fill(LinearGradient(colors: [Color(white: 0.28), Color(white: 0.22)], startPoint: .topLeading, endPoint: .bottomTrailing))
                            .opacity(0.9)
                            .frame(width: 74, height: 74)
                            .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous)
                                .stroke(Color.white.opacity(0.15), style: StrokeStyle(lineWidth: 1, dash: [4])))
                            .shadow(color: .black.opacity(0.3), radius: 10, x: 0, y: 5)
                        
                        Image(systemName: "plus")
                            .font(.system(size: 28, weight: .bold))
                            .foregroundColor(.white)
                    }
                    Text(store.T("Other")).font(.system(size: 13, weight: .medium, design: .rounded)).foregroundColor(.white.opacity(0.85))
                }
                .onTapGesture { withAnimation { isShowingOther = true } }
            }.padding(24)
        }
    }
}

struct ClipboardView: View {
    @ObservedObject var store: FluxStore; var search: String; @State private var copiedID: UUID?
    var filteredItems: [ClipboardItem] { search.isEmpty ? store.history : store.history.filter { $0.text.localizedCaseInsensitiveContains(search) } }
    var body: some View {
        VStack(spacing: 0) {
            if !store.history.isEmpty && search.isEmpty {
                HStack {
                    Spacer()
                    Button(action: {
                        let fluxWindow = NSApp.windows.first(where: { $0 is FluxWindow })
                        let prevLevel = fluxWindow?.level
                        fluxWindow?.level = .modalPanel
                        
                        let alert = NSAlert()
                        alert.messageText = store.T("Clear Clipboard History?", context: "Alert title")
                        alert.informativeText = store.T("This will permanently delete all items in your history.", context: "Alert description")
                        alert.addButton(withTitle: store.T("Clear All", context: "Confirm button"))
                        alert.addButton(withTitle: store.T("Cancel", context: "Cancel button"))
                        alert.alertStyle = .warning
                        let result = alert.runModal()
                        
                        fluxWindow?.level = prevLevel ?? .floating
                        
                        if result == .alertFirstButtonReturn {
                            withAnimation { store.clearHistory() }
                        }
                    }) {
                        HStack(spacing: 6) {
                            Image(systemName: "trash")
                            Text(store.T("Clear History"))
                        }
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.red.opacity(0.8))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Color.red.opacity(0.1))
                        .cornerRadius(8)
                    }
                    .buttonStyle(.plain)
                    .padding(.trailing, 16)
                    .padding(.top, 8)
                }
            }
            
            List(filteredItems) { item in
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(item.text.replacingOccurrences(of: "\n", with: " ")).lineLimit(1).font(.system(size: 14, weight: .semibold, design: .rounded))
                        Text(item.timestamp, style: .time).font(.system(size: 11, design: .monospaced)).foregroundColor(.gray.opacity(0.8))
                    }
                    Spacer()
                    
                    HStack(spacing: 16) {
                        Button(action: {
                            NSPasteboard.general.clearContents(); NSPasteboard.general.setString(item.text, forType: .string)
                            withAnimation(.easeInOut(duration: 0.3)) { copiedID = item.id }
                            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { withAnimation(.easeInOut(duration: 0.3)) { if copiedID == item.id { copiedID = nil } } }
                        }) {
                            ZStack {
                                if copiedID == item.id {
                                    Image(systemName: "checkmark")
                                        .foregroundColor(.green.opacity(0.8))
                                        .transition(.asymmetric(insertion: .scale.combined(with: .opacity), removal: .opacity))
                                } else {
                                    Image(systemName: "doc.on.doc")
                                        .foregroundColor(.blue.opacity(0.8))
                                        .transition(.opacity)
                                }
                            }
                            .font(.system(size: 15, weight: .medium))
                            .scaleEffect(copiedID == item.id ? 1.1 : 1.0)
                        }.buttonStyle(.plain)
                        
                        Button(action: {
                            withAnimation { store.deleteHistoryItem(id: item.id) }
                        }) {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(.gray.opacity(0.5))
                                .font(.system(size: 14))
                        }.buttonStyle(.plain)
                    }
                }
                .padding(.vertical, 10)
                .padding(.horizontal, 12)
                .background(Color.white.opacity(0.03))
                .cornerRadius(12)
                .padding(.horizontal, 8)
            }.listStyle(.plain).scrollContentBackground(.hidden)
        }
    }
}

struct SnippetView: View {
    @ObservedObject var store: FluxStore; var search: String; @Binding var isShowingAdd: Bool; @State private var newName = ""; @State private var newText = ""; @State private var editingKey: String? = nil
    @State private var copiedKey: String? = nil
    @State private var confirmingDeleteFor: String? = nil
    var filteredKeys: [String] { let keys = Array(store.snippets.keys).sorted(); return search.isEmpty ? keys : keys.filter { $0.localizedCaseInsensitiveContains(search) } }
    var body: some View {
        VStack(spacing: 0) {
            if isShowingAdd {
                VStack(spacing: 16) {
                    TextField(store.T("Snippet Name (e.g. email)"), text: $newName).textFieldStyle(.plain).padding(12).background(Color.black.opacity(0.5)).cornerRadius(12)
                    TextEditor(text: $newText).font(.system(.body, design: .monospaced)).scrollContentBackground(.hidden).frame(height: 140).padding(10).background(Color.black.opacity(0.5)).cornerRadius(12)
                    HStack {
                        Button(store.T("Cancel")) { withAnimation(.easeInOut(duration: 0.3)) { isShowingAdd = false; editingKey = nil } }.buttonStyle(.bordered).controlSize(.large)
                        Spacer()
                        Button(editingKey == nil ? store.T("Save Snippet") : store.T("Update Snippet")) {
                            if !newName.isEmpty && !newText.isEmpty {
                                if let old = editingKey { store.snippets.removeValue(forKey: old) }
                                store.snippets[newName] = newText; store.saveSnippets()
                                withAnimation(.easeInOut(duration: 0.3)) { isShowingAdd = false; newName = ""; newText = ""; editingKey = nil }
                            }
                        }.buttonStyle(.borderedProminent).controlSize(.large)
                    }
                }.padding(20).background(Color.white.opacity(0.04)).cornerRadius(20).padding().transition(.move(edge: .top).combined(with: .opacity))
            }
            List(filteredKeys, id: \.self) { key in
                HStack(spacing: 14) {
                    VStack(alignment: .leading, spacing: 4) { 
                        Text(key).font(.system(size: 14, weight: .bold, design: .rounded))
                        Text(store.snippets[key] ?? "").lineLimit(1).font(.system(size: 12, design: .monospaced)).foregroundColor(.gray.opacity(0.7)) 
                    }
                    Spacer()
                    Button(action: {
                        NSPasteboard.general.clearContents(); NSPasteboard.general.setString(store.snippets[key] ?? "", forType: .string)
                        withAnimation(.easeInOut(duration: 0.3)) { copiedKey = key }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { withAnimation(.easeInOut(duration: 0.3)) { if copiedKey == key { copiedKey = nil } } }
                    }) {
                        ZStack {
                            if copiedKey == key {
                                Image(systemName: "checkmark")
                                    .foregroundColor(.green.opacity(0.8))
                                    .transition(.asymmetric(insertion: .scale.combined(with: .opacity), removal: .opacity))
                            } else {
                                Image(systemName: "doc.on.doc")
                                    .foregroundColor(.blue.opacity(0.8))
                                    .transition(.opacity)
                            }
                        }
                        .font(.system(size: 15, weight: .medium))
                        .scaleEffect(copiedKey == key ? 1.1 : 1.0)
                    }.buttonStyle(.plain)
                    Button(action: { newName = key; newText = store.snippets[key] ?? ""; editingKey = key; withAnimation(.easeInOut(duration: 0.3)) { isShowingAdd = true } }) { Image(systemName: "pencil").font(.system(size: 16)).foregroundColor(.orange.opacity(0.8)) }.buttonStyle(.plain)
                    
                    Button(action: {
                        // Prevent the window from hiding while the alert is shown
                        let fluxWindow = NSApp.windows.first(where: { $0 is FluxWindow })
                        let prevLevel = fluxWindow?.level
                        fluxWindow?.level = .modalPanel
                        
                        let alert = NSAlert()
                        alert.messageText = store.T("Delete Snippet?", context: "Alert title")
                        alert.informativeText = store.T("Are you sure you want to delete '\(key)'?", context: "Alert description")
                        alert.addButton(withTitle: store.T("Delete", context: "Confirm delete button"))
                        alert.addButton(withTitle: store.T("Cancel", context: "Cancel button"))
                        alert.alertStyle = .warning
                        let result = alert.runModal()
                        
                        fluxWindow?.level = prevLevel ?? .floating
                        
                        if result == .alertFirstButtonReturn {
                            store.snippets.removeValue(forKey: key)
                            store.saveSnippets()
                            store.loadAll()
                        }
                    }) {
                        Image(systemName: "trash").font(.system(size: 16)).foregroundColor(.red.opacity(0.8))
                    }.buttonStyle(.plain)
                }
                .padding(.vertical, 8)
                .padding(.horizontal, 12)
                .background(Color.white.opacity(0.03))
                .cornerRadius(12)
                .padding(.horizontal, 8)
            }.listStyle(.plain).scrollContentBackground(.hidden)
            if !isShowingAdd {
                Button(action: { withAnimation { isShowingAdd.toggle(); newName = ""; newText = ""; editingKey = nil } }) {
                    Label(store.T("Add New Snippet"), systemImage: "plus.circle.fill").font(.headline).frame(maxWidth: .infinity).padding(12).background(Color.blue).cornerRadius(12)
                }.buttonStyle(.plain).padding().transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
    }
}

// MARK: - Color Picker View
struct ColorPickerView: View {
    @ObservedObject var store: FluxStore
    @State private var selectedColorHex: String? = nil
    
    var body: some View {
        VStack(spacing: 20) {
            HStack {
                Button(action: pickColor) {
                    HStack {
                        Image(systemName: "eyedropper.halffull")
                        Text(store.T("Pick Screen Color"))
                    }.font(.headline).padding(16).background(Color.blue).cornerRadius(12)
                }.buttonStyle(.plain)
                Spacer()
                Toggle(store.T("Save History"), isOn: Binding(get: { store.saveColorHistory }, set: { _ in store.toggleColorHistory() }))
                    .toggleStyle(SwitchToggleStyle(tint: .blue))
            }.padding(.horizontal)
            
            if let hex = selectedColorHex, let color = Color(hex: hex) {
                VStack(spacing: 12) {
                    HStack(spacing: 18) {
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(color)
                            .frame(width: 64, height: 64)
                            .shadow(color: .black.opacity(0.4), radius: 6, x: 0, y: 3)
                            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Color.white.opacity(0.2), lineWidth: 1))
                        
                        VStack(alignment: .leading, spacing: 10) {
                            Text(store.T("Selected Color Stats")).font(.system(size: 12, weight: .bold, design: .rounded)).foregroundColor(.white.opacity(0.4))
                            HStack(spacing: 8) {
                                StatPill(store: store, label: "HEX", value: hex)
                                StatPill(store: store, label: "RGB", value: NSColor(color).toRGBString())
                                StatPill(store: store, label: "HSL", value: NSColor(color).toHSLString())
                            }
                        }
                        Spacer()
                    }
                }
                .padding(18)
                .background(Color.white.opacity(0.06))
                .cornerRadius(20)
                .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(Color.white.opacity(0.1), lineWidth: 0.5))
                .padding(.horizontal, 20)
                .transition(.asymmetric(insertion: .move(edge: .top).combined(with: .opacity), removal: .opacity))
            }
            
            if !store.recentColors.isEmpty {
                VStack(alignment: .leading, spacing: 14) {
                    Text(store.T("Recent Colors")).font(.system(size: 15, weight: .bold, design: .rounded)).foregroundColor(.white.opacity(0.6)).padding(.horizontal, 24)
                    ScrollView {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 100), spacing: 16)], spacing: 16) {
                            ForEach(store.recentColors, id: \.self) { hex in
                                ZStack(alignment: .topTrailing) {
                                    Button(action: { withAnimation(.easeInOut(duration: 0.3)) { selectedColorHex = hex } }) {
                                        VStack(spacing: 8) {
                                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                                .fill(Color(hex: hex) ?? .gray)
                                                .frame(height: 54)
                                                .shadow(color: .black.opacity(0.3), radius: 4, x: 0, y: 2)
                                                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Color.white.opacity(0.1), lineWidth: 1))
                                            Text(hex).font(.system(size: 11, weight: .medium, design: .monospaced)).foregroundColor(.white.opacity(0.8))
                                        }
                                    }.buttonStyle(.plain)
                                    Button(action: { withAnimation { store.recentColors.removeAll(where: { $0 == hex }); store.saveColors() } }) {
                                        Image(systemName: "xmark.circle.fill").font(.system(size: 16)).foregroundColor(.white.opacity(0.9)).background(Circle().fill(Color.black.opacity(0.6)))
                                    }.buttonStyle(.plain).padding(6)
                                }
                            }
                        }.padding(.horizontal, 24)
                    }
                }
            }
            Spacer()
        }.padding(.top)
    }
    
    func pickColor() {
        let sampler = NSColorSampler()
        sampler.show { color in
            if let color = color {
                let hex = color.toHexString()
                DispatchQueue.main.async {
                    withAnimation { selectedColorHex = hex }
                    if store.saveColorHistory {
                        if let idx = store.recentColors.firstIndex(of: hex) { store.recentColors.remove(at: idx) }
                        store.recentColors.insert(hex, at: 0)
                        if store.recentColors.count > 12 { store.recentColors.removeLast() }
                        store.saveColors()
                    }
                    NSPasteboard.general.clearContents(); NSPasteboard.general.setString(hex, forType: .string)
                }
            }
        }
    }
}

struct StatPill: View {
    let store: FluxStore
    let label: String
    let value: String
    @State private var copied = false
    var body: some View {
        Button(action: {
            NSPasteboard.general.clearContents(); NSPasteboard.general.setString(value, forType: .string)
            withAnimation(.easeInOut(duration: 0.3)) { copied = true }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { withAnimation(.easeInOut(duration: 0.3)) { copied = false } }
        }) {
            ZStack {
                if copied {
                    HStack(spacing: 6) {
                        Image(systemName: "checkmark").font(.system(size: 11, weight: .bold))
                        Text(store.T("Copied")).font(.system(size: 11, weight: .bold, design: .rounded))
                    }
                    .foregroundColor(.green.opacity(0.9))
                    .transition(.asymmetric(insertion: .opacity.combined(with: .scale(scale: 0.8)), removal: .opacity))
                } else {
                    HStack(spacing: 4) {
                        Text("\(label):").font(.system(size: 10, weight: .bold, design: .rounded)).foregroundColor(.white.opacity(0.4))
                        Text(value).font(.system(size: 10, weight: .medium, design: .monospaced)).foregroundColor(.white.opacity(0.9)).lineLimit(1)
                    }
                    .transition(.asymmetric(insertion: .opacity, removal: .opacity.combined(with: .scale(scale: 0.8))))
                }
            }
            .padding(.vertical, 8)
            .padding(.horizontal, 12)
            .frame(minWidth: 105, minHeight: 34) // Ensure stable dimensions
            .background(Color.white.opacity(0.08))
            .cornerRadius(10)
        }.buttonStyle(.plain)
    }
}

// MARK: - Scratchpad View
struct ScratchpadView: View {
    @ObservedObject var store: FluxStore
    var search: String
    @Binding var forceExpand: Bool
    @State private var selectedID: UUID?
    @State private var isRenaming: UUID?
    @State private var newTitle: String = ""
    @State private var isSidebarCollapsed = false
    
    var sortedScratchpads: [Scratchpad] {
        let pads = store.scratchpads.sorted { $0.lastEdit > $1.lastEdit }
        if search.isEmpty { return pads }
        return pads.filter { 
            $0.title.localizedCaseInsensitiveContains(search) || 
            $0.content.localizedCaseInsensitiveContains(search)
        }
    }
    
    var body: some View {
        HStack(spacing: 0) {
            // Sidebar
            ZStack(alignment: .top) {
                VStack(spacing: 0) {
                    ScrollView {
                        VStack(spacing: 8) {
                            ForEach(sortedScratchpads) { pad in
                                HStack {
                                    if isRenaming == pad.id {
                                        TextField(store.T("Title"), text: $newTitle, onCommit: {
                                            if let idx = store.scratchpads.firstIndex(where: { $0.id == pad.id }) {
                                                store.scratchpads[idx].title = newTitle
                                                store.saveScratchpads()
                                            }
                                            isRenaming = nil
                                        })
                                        .textFieldStyle(.plain)
                                        .font(.system(size: 13, weight: .medium))
                                    } else {
                                        Text((pad.title == "Main Notes" || pad.title == "New Note") ? store.T(pad.title) : pad.title)
                                            .font(.system(size: 13, weight: .medium))
                                            .lineLimit(1)
                                        Spacer()
                                        if selectedID == pad.id {
                                            Button(action: { newTitle = pad.title; isRenaming = pad.id }) {
                                                Image(systemName: "pencil").font(.system(size: 10))
                                            }.buttonStyle(.plain).foregroundColor(.gray)
                                        }
                                    }
                                }
                                .padding(.vertical, 10)
                                .padding(.horizontal, 12)
                                .background(selectedID == pad.id ? Color.blue.opacity(0.2) : Color.white.opacity(0.03))
                                .cornerRadius(10)
                                .onTapGesture { selectedID = pad.id }
                                .contextMenu {
                                    Button(store.T("Rename", context: "Context menu action")) { newTitle = pad.title; isRenaming = pad.id }
                                    Button(store.T("Delete", context: "Context menu action"), role: .destructive) {
                                        store.scratchpads.removeAll(where: { $0.id == pad.id })
                                        if store.scratchpads.isEmpty {
                                            store.scratchpads = [Scratchpad(id: UUID(), title: "Main Notes", content: "", lastEdit: Date())]
                                        }
                                        if selectedID == pad.id { selectedID = store.scratchpads.first?.id }
                                        store.saveScratchpads()
                                    }
                                }
                            }
                        }
                        .padding(12)
                    }
                    
                    Divider().background(Color.white.opacity(0.1))
                    
                    Button(action: {
                        let newPad = Scratchpad(id: UUID(), title: "New Note", content: "", lastEdit: Date())
                        store.scratchpads.append(newPad)
                        selectedID = newPad.id
                        store.saveScratchpads()
                    }) {
                        Label(store.T("Add Note"), systemImage: "plus.circle.fill")
                            .font(.system(size: 13, weight: .semibold))
                            .frame(maxWidth: .infinity)
                            .padding(12)
                    }
                    .buttonStyle(.plain)
                    .foregroundColor(.blue)
                }
                .opacity(isSidebarCollapsed ? 0 : 1)
                
                if isSidebarCollapsed {
                    VStack {
                        Spacer()
                        Button(action: { withAnimation(.easeInOut(duration: 0.3)) { isSidebarCollapsed = false } }) {
                            Image(systemName: "chevron.right.circle.fill")
                                .font(.system(size: 18))
                                .foregroundColor(.blue.opacity(0.5))
                                .padding(.bottom, 20)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .frame(width: (isSidebarCollapsed && !forceExpand && search.isEmpty) ? 30 : 160)
            .clipped()
            .background(Color.black.opacity(0.1))
            
            Divider().background(Color.white.opacity(0.1))
            
            // Editor
            if let id = selectedID, let index = store.scratchpads.firstIndex(where: { $0.id == id }) {
                TextEditor(text: Binding(get: { store.scratchpads[index].content }, set: { 
                    store.scratchpads[index].content = $0
                    store.scratchpads[index].lastEdit = Date()
                    store.saveScratchpads()
                }))
                .font(.system(.body, design: .monospaced))
                .scrollContentBackground(.hidden)
                .padding(12)
                .background(Color.black.opacity(0.2))
                .cornerRadius(16)
                .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Color.white.opacity(0.05), lineWidth: 1))
                .padding(20)
                .onHover { inside in
                    if inside && isRenaming == nil {
                        withAnimation(.easeInOut(duration: 0.3)) { isSidebarCollapsed = true }
                    } else if !inside {
                        withAnimation(.easeInOut(duration: 0.3)) { isSidebarCollapsed = false }
                    }
                }
            } else {
                VStack {
                    Image(systemName: "pencil.and.outline").font(.system(size: 48)).foregroundColor(.gray.opacity(0.3))
                    Text(store.T("Select a scratchpad to start writing")).font(.headline).foregroundColor(.gray.opacity(0.5))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .onChange(of: forceExpand) { newValue in
            if newValue { withAnimation(.easeInOut(duration: 0.3)) { isSidebarCollapsed = false } }
        }
        .onChange(of: search) { newValue in
            if !newValue.isEmpty { withAnimation(.easeInOut(duration: 0.3)) { isSidebarCollapsed = false } }
        }
        .onAppear {
            if selectedID == nil { selectedID = sortedScratchpads.first?.id }
        }
    }
}

// MARK: - App & Hotkey Management
class FluxWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}
@main struct FluxApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    var body: some Scene { Settings { EmptyView() } }
}
class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    var statusItem: NSStatusItem?; var window: FluxWindow?; var store: FluxStore?
    var isTogglingFromStatusBar = false
    var carbonHotKey: EventHotKeyRef?
    var eventHandler: EventHandlerRef?
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        
        let store = FluxStore(); self.store = store
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem?.button {
            button.image = NSImage(systemSymbolName: "rectangle.grid.2x2.fill", accessibilityDescription: "Flux")
            button.action = #selector(toggleWindow); button.target = self
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
        let contentView = MainView(store: store)
        
        window = FluxWindow(contentRect: NSRect(x: 0, y: 0, width: 520, height: 480), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        window?.isReleasedWhenClosed = false
        window?.level = .floating
        window?.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window?.hasShadow = true; window?.backgroundColor = .clear; window?.isOpaque = false
        window?.isMovableByWindowBackground = store.settings.isDraggable
        window?.delegate = self
        window?.contentView = NSHostingView(rootView: contentView)
        window?.center()
        
        setupModifierHotkey(); setupTabShortcuts()
        updateCarbonHotkey()
        
        NotificationCenter.default.addObserver(forName: NSNotification.Name("UpdateCarbonHotkey"), object: nil, queue: .main) { [weak self] _ in
            self?.updateCarbonHotkey()
        }
        
        DispatchQueue.main.async { self.toggleWindow() }
    }
    
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if let window = window, !window.isVisible {
            toggleWindow()
        }
        return true
    }
    
    func setupModifierHotkey() {
        var lastModifierFlags: NSEvent.ModifierFlags = []
        var potentialTap: UInt16? = nil

        let handleFlagsChanged: (NSEvent) -> Void = { [weak self] event in
            guard let self = self, let store = self.store else { return }
            if store.settings.toggleModifierMode == 3 { return }
            
            let currentFlags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            if currentFlags.rawValue > lastModifierFlags.rawValue {
                potentialTap = event.keyCode
            } else if currentFlags.rawValue < lastModifierFlags.rawValue {
                if let tap = potentialTap, event.keyCode == tap {
                    var isMatch = false
                    if store.settings.toggleModifierMode == 0 && (tap == 59 || tap == 62) { isMatch = true }
                    else if store.settings.toggleModifierMode == 1 && (tap == 54 || tap == 55) { isMatch = true }
                    else if store.settings.toggleModifierMode == 2 && (tap == 58 || tap == 61) { isMatch = true }
                    
                    if isMatch {
                        DispatchQueue.main.async { self.toggleWindow() }
                    }
                }
                potentialTap = nil
            }
            lastModifierFlags = currentFlags
        }

        let handleKeyDown: (NSEvent) -> NSEvent? = { event in
            potentialTap = nil
            return event
        }

        NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { event in handleFlagsChanged(event); return event }
        NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged) { event in handleFlagsChanged(event) }
        
        NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in return handleKeyDown(event) }
        NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { event in _ = handleKeyDown(event) }
    }
    
    func updateCarbonHotkey() {
        if let hotKey = carbonHotKey {
            UnregisterEventHotKey(hotKey)
            carbonHotKey = nil
        }
        
        guard let store = self.store, store.settings.toggleModifierMode == 3, let shortcut = store.settings.toggleShortcut else { return }
        
        var carbonFlags: UInt32 = 0
        if shortcut.modifiers & NSEvent.ModifierFlags.command.rawValue != 0 { carbonFlags |= UInt32(cmdKey) }
        if shortcut.modifiers & NSEvent.ModifierFlags.option.rawValue != 0 { carbonFlags |= UInt32(optionKey) }
        if shortcut.modifiers & NSEvent.ModifierFlags.control.rawValue != 0 { carbonFlags |= UInt32(controlKey) }
        if shortcut.modifiers & NSEvent.ModifierFlags.shift.rawValue != 0 { carbonFlags |= UInt32(shiftKey) }
        
        let hotKeyID = EventHotKeyID(signature: 0x464C5558, id: 1) // "FLUX"
        
        RegisterEventHotKey(UInt32(shortcut.keyCode), carbonFlags, hotKeyID, GetApplicationEventTarget(), 0, &carbonHotKey)
        
        if eventHandler == nil {
            var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
            let handler: EventHandlerUPP = { (nextHandler, theEvent, userData) -> OSStatus in
                guard let userData = userData else { return noErr }
                let appDelegate = Unmanaged<AppDelegate>.fromOpaque(userData).takeUnretainedValue()
                DispatchQueue.main.async { appDelegate.toggleWindow() }
                return noErr
            }
            InstallEventHandler(GetApplicationEventTarget(), handler, 1, &eventType, Unmanaged.passUnretained(self).toOpaque(), &eventHandler)
        }
    }
    
    func setupTabShortcuts() {
        NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self = self, let store = self.store else { return event }
            let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            
            for (index, shortcut) in store.settings.tabShortcuts {
                if event.keyCode == shortcut.keyCode && modifiers.rawValue == shortcut.modifiers {
                    store.selectedTab = index
                    return nil
                }
            }
            return event
        }
    }
    @objc func toggleWindow() {
        if let event = NSApp.currentEvent, event.type == .rightMouseUp {
            let menu = NSMenu()
            menu.addItem(withTitle: store?.T("About Flux", context: "Menu bar item") ?? "About Flux", action: #selector(showAbout), keyEquivalent: "")
            menu.addItem(NSMenuItem.separator())
            menu.addItem(withTitle: store?.T("Quit Flux", context: "Menu bar item") ?? "Quit Flux", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
            statusItem?.menu = menu
            statusItem?.button?.performClick(nil)
            statusItem?.menu = nil
            return
        }
        
        isTogglingFromStatusBar = true
        defer {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                self.isTogglingFromStatusBar = false
            }
        }
        if let window = window {
            if window.isVisible {
                NSAnimationContext.runAnimationGroup({ context in
                    context.duration = 0.2
                    window.animator().alphaValue = 0
                }, completionHandler: {
                    window.orderOut(nil)
                })
            } else {
                window.alphaValue = 0
                window.makeKeyAndOrderFront(nil)
                NSApp.activate(ignoringOtherApps: true)
                NSAnimationContext.runAnimationGroup({ context in
                    context.duration = 0.2
                    window.animator().alphaValue = 1.0
                })
            }
        }
    }
    func windowDidResignKey(_ notification: Notification) {
        // Don't hide if we're in the middle of a status bar toggle (avoids show-then-immediately-hide race)
        guard !isTogglingFromStatusBar else { return }
        if let window = window, window.isVisible {
            NSAnimationContext.runAnimationGroup({ context in
                context.duration = 0.2
                window.animator().alphaValue = 0
            }, completionHandler: {
                window.orderOut(nil)
            })
        }
    }
    
    @objc func showAbout() {
        NSApp.orderFrontStandardAboutPanel(nil)
    }
}

// Helper Extensions
extension NSColor {
    func toHexString() -> String {
        guard let rgbColor = usingColorSpace(.deviceRGB) else { return "#FFFFFF" }
        let r = Int(round(rgbColor.redComponent * 255))
        let g = Int(round(rgbColor.greenComponent * 255))
        let b = Int(round(rgbColor.blueComponent * 255))
        return String(format: "#%02X%02X%02X", r, g, b)
    }
    func toRGBString() -> String {
        guard let rgbColor = usingColorSpace(.deviceRGB) else { return "rgb(255, 255, 255)" }
        let r = Int(round(rgbColor.redComponent * 255))
        let g = Int(round(rgbColor.greenComponent * 255))
        let b = Int(round(rgbColor.blueComponent * 255))
        return "rgb(\(r), \(g), \(b))"
    }
    func toHSLString() -> String {
        guard let rgbColor = usingColorSpace(.deviceRGB) else { return "hsl(0, 0%, 100%)" }
        let r = rgbColor.redComponent
        let g = rgbColor.greenComponent
        let b = rgbColor.blueComponent
        
        let maxColor = max(r, max(g, b))
        let minColor = min(r, min(g, b))
        var h: CGFloat = 0
        var s: CGFloat = 0
        let l: CGFloat = (maxColor + minColor) / 2
        
        if maxColor != minColor {
            let d = maxColor - minColor
            s = l > 0.5 ? d / (2 - maxColor - minColor) : d / (maxColor + minColor)
            if maxColor == r { h = (g - b) / d + (g < b ? 6 : 0) }
            else if maxColor == g { h = (b - r) / d + 2 }
            else { h = (r - g) / d + 4 }
            h /= 6
        }
        
        if h < 0 { h += 1 }
        return String(format: "hsl(%d, %d%%, %d%%)", Int(round(h * 360)), Int(round(s * 100)), Int(round(l * 100)))
    }
}

extension Color {
    init?(hex: String) {
        var hexSanitized = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        hexSanitized = hexSanitized.replacingOccurrences(of: "#", with: "")
        var rgb: UInt64 = 0
        guard Scanner(string: hexSanitized).scanHexInt64(&rgb) else { return nil }
        self.init(red: Double((rgb & 0xFF0000) >> 16) / 255.0, green: Double((rgb & 0x00FF00) >> 8) / 255.0, blue: Double(rgb & 0x0000FF) / 255.0)
    }
}
