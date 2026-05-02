import Foundation
import ArgumentParser

struct InstallDaemon: AsyncParsableCommand {
    static var configuration = CommandConfiguration(
        commandName: "install-daemon",
        abstract: "Install and start the background clipboard daemon."
    )
    
    mutating func run() async throws {
        let plistName = "com.openpowerclick.daemon.plist"
        let homeDir = FileManager.default.homeDirectoryForCurrentUser
        let launchAgentsDir = homeDir.appendingPathComponent("Library/LaunchAgents")
        let plistURL = launchAgentsDir.appendingPathComponent(plistName)
        
        let fm = FileManager.default
        if !fm.fileExists(atPath: launchAgentsDir.path) {
            try fm.createDirectory(at: launchAgentsDir, withIntermediateDirectories: true)
        }
        
        // Find path to current executable
        let executablePath = Bundle.main.executablePath ?? CommandLine.arguments[0]
        let absoluteExecutablePath = URL(fileURLWithPath: executablePath).standardizedFileURL.path
        
        let plistContent = """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
            <key>Label</key>
            <string>com.openpowerclick.daemon</string>
            <key>ProgramArguments</key>
            <array>
                <string>\(absoluteExecutablePath)</string>
                <string>daemon</string>
            </array>
            <key>RunAtLoad</key>
            <true/>
            <key>KeepAlive</key>
            <true/>
            <key>StandardOutPath</key>
            <string>\(homeDir.path)/.openpowerclick/daemon.log</string>
            <key>StandardErrorPath</key>
            <string>\(homeDir.path)/.openpowerclick/daemon.err</string>
        </dict>
        </plist>
        """
        
        try plistContent.write(to: plistURL, atomically: true, encoding: .utf8)
        print("Installed launch agent to \(plistURL.path)")
        
        // Unload first if it's already loaded, then load
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
    }
}
