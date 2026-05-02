import Foundation
import ArgumentParser

struct InstallQuickAction: AsyncParsableCommand {
    static var configuration = CommandConfiguration(
        commandName: "install-quick-action",
        abstract: "Install the Finder Quick Action for right-click file creation."
    )
    
    mutating func run() async throws {
        let homeDir = FileManager.default.homeDirectoryForCurrentUser
        let servicesDir = homeDir.appendingPathComponent("Library/Services")
        let workflowDir = servicesDir.appendingPathComponent("OpenPowerClick: New File.workflow")
        let contentsDir = workflowDir.appendingPathComponent("Contents")
        
        let fm = FileManager.default
        if !fm.fileExists(atPath: contentsDir.path) {
            try fm.createDirectory(at: contentsDir, withIntermediateDirectories: true)
        }
        
        // Find path to current executable
        let executablePath = Bundle.main.executablePath ?? CommandLine.arguments[0]
        let absoluteExecutablePath = URL(fileURLWithPath: executablePath).standardizedFileURL.path
        
        // We will generate the Info.plist and document.wflow
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
                        <string>OpenPowerClick: New File</string>
                    </dict>
                    <key>NSMessage</key>
                    <string>runWorkflowAsService</string>
                    <key>NSRequiredContext</key>
                    <dict>
                        <key>NSApplicationIdentifier</key>
                        <string>com.apple.finder</string>
                    </dict>
                </dict>
            </array>
        </dict>
        </plist>
        """
        
        let script = """
        on run {input, parameters}
            tell application "Finder"
                if exists insertion location then
                    set targetDir to POSIX path of (insertion location as alias)
                else
                    set targetDir to POSIX path of (path to desktop folder as alias)
                end if
            end tell
            
            tell application "System Events"
                activate
                set fileName to text returned of (display dialog "Enter new file name:" default answer "index.html" with title "OpenPowerClick New File")
            end tell
            
            do shell script "\(absoluteExecutablePath) create-file " & quoted form of targetDir & " " & quoted form of fileName
            return input
        end run
        """
        
        // XML for document.wflow
        let wflow = """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
            <key>AMApplicationBuild</key>
            <string>523</string>
            <key>AMApplicationVersion</key>
            <string>2.10</string>
            <key>AMDocumentVersion</key>
            <string>2</string>
            <key>actions</key>
            <array>
                <dict>
                    <key>action</key>
                    <dict>
                        <key>AMAccepts</key>
                        <dict>
                            <key>Container</key>
                            <string>List</string>
                            <key>Optional</key>
                            <true/>
                            <key>Types</key>
                            <array>
                                <string>com.apple.applescript.object</string>
                            </array>
                        </dict>
                        <key>AMActionVersion</key>
                        <string>1.0.2</string>
                        <key>AMApplication</key>
                        <array>
                            <string>Automator</string>
                        </array>
                        <key>AMParameterProperties</key>
                        <dict>
                            <key>source</key>
                            <dict/>
                        </dict>
                        <key>AMProvides</key>
                        <dict>
                            <key>Container</key>
                            <string>List</string>
                            <key>Types</key>
                            <array>
                                <string>com.apple.applescript.object</string>
                            </array>
                        </dict>
                        <key>ActionBundlePath</key>
                        <string>/System/Library/Automator/Run AppleScript.action</string>
                        <key>ActionName</key>
                        <string>Run AppleScript</string>
                        <key>ActionParameters</key>
                        <dict>
                            <key>source</key>
                            <string>\(script.replacingOccurrences(of: "<", with: "&lt;").replacingOccurrences(of: ">", with: "&gt;").replacingOccurrences(of: "&", with: "&amp;"))</string>
                        </dict>
                        <key>BundleIdentifier</key>
                        <string>com.apple.Automator.RunScript</string>
                        <key>CFBundleVersion</key>
                        <string>1.0.2</string>
                        <key>CanShowSelectedItemsWhenRun</key>
                        <false/>
                        <key>CanShowWhenRun</key>
                        <true/>
                        <key>Category</key>
                        <array>
                            <string>AMCategoryUtilities</string>
                        </array>
                        <key>Class Name</key>
                        <string>RunScriptAction</string>
                        <key>InputUUID</key>
                        <string>E7C817C6-0A05-4309-B4A1-21B0A06540EB</string>
                        <key>Keywords</key>
                        <array>
                            <string>Run</string>
                        </array>
                        <key>OutputUUID</key>
                        <string>29B53A37-9759-4D2A-8B8D-A8A1C50C3A0A</string>
                        <key>UUID</key>
                        <string>8D0C95CC-9407-4C01-BA37-77CD05F2BA3C</string>
                        <key>UnlocalizedApplications</key>
                        <array>
                            <string>Automator</string>
                        </array>
                        <key>arguments</key>
                        <dict>
                            <key>0</key>
                            <dict>
                                <key>default value</key>
                                <string>on run {input, parameters}\n\n\t(* Your script goes here *)\n\n\treturn input\nend run</string>
                                <key>name</key>
                                <string>source</string>
                                <key>required</key>
                                <string>0</string>
                                <key>type</key>
                                <string>0</string>
                                <key>uuid</key>
                                <string>0</string>
                            </dict>
                        </dict>
                        <key>conversionLabel</key>
                        <integer>0</integer>
                        <key>isViewVisible</key>
                        <integer>1</integer>
                        <key>location</key>
                        <string>309.000000:315.000000</string>
                        <key>nibPath</key>
                        <string>/System/Library/Automator/Run AppleScript.action/Contents/Resources/Base.lproj/main.nib</string>
                    </dict>
                    <key>isViewVisible</key>
                    <integer>1</integer>
                </dict>
            </array>
            <key>connectors</key>
            <dict/>
            <key>workflowMetaData</key>
            <dict>
                <key>applicationBundleIDsByPath</key>
                <dict/>
                <key>applicationPaths</key>
                <array/>
                <key>inputTypeIdentifier</key>
                <string>com.apple.Automator.nothing</string>
                <key>outputTypeIdentifier</key>
                <string>com.apple.Automator.nothing</string>
                <key>presentationMode</key>
                <integer>11</integer>
                <key>processesInput</key>
                <false/>
                <key>serviceApplicationBundleID</key>
                <string>com.apple.finder</string>
                <key>serviceApplicationPath</key>
                <string>/System/Library/CoreServices/Finder.app</string>
                <key>serviceInputTypeIdentifier</key>
                <string>com.apple.Automator.nothing</string>
                <key>serviceOutputTypeIdentifier</key>
                <string>com.apple.Automator.nothing</string>
                <key>serviceProcessesInput</key>
                <false/>
                <key>systemImageName</key>
                <string>NSTouchBarDocument</string>
                <key>useAutomaticInputType</key>
                <false/>
                <key>workflowTypeIdentifier</key>
                <string>com.apple.Automator.servicesMenu</string>
            </dict>
        </dict>
        </plist>
        """
        
        try infoPlist.write(to: contentsDir.appendingPathComponent("Info.plist"), atomically: true, encoding: .utf8)
        try wflow.write(to: contentsDir.appendingPathComponent("document.wflow"), atomically: true, encoding: .utf8)
        
        print("Quick Action installed successfully to \(workflowDir.path)")
        print("You may need to enable it in System Settings > Keyboard > Keyboard Shortcuts > Services > Files and Folders.")
    }
}
