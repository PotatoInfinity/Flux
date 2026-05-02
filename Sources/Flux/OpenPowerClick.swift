import ArgumentParser
import Foundation

@main
struct OpenPowerClick: AsyncParsableCommand {
    static var configuration = CommandConfiguration(
        commandName: "openpowerclick",
        abstract: "Open-source PowerClick alternative.",
        subcommands: [
            Daemon.self,
            InstallDaemon.self,
            InstallQuickAction.self,
            Clipboard.self,
            Snippet.self,
            CreateFile.self
        ]
    )
}
