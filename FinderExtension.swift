import Cocoa
import FinderSync

class FinderSync: FIFinderSync {
    override init() {
        super.init()
        FIFinderSyncController.default().directoryURLs = [URL(fileURLWithPath: "/")]
    }
    
    override func menu(for menuKind: FIMenuKind) -> NSMenu? {
        let menu = NSMenu(title: "")
        let item = NSMenuItem(title: "Copy Exact Path", action: #selector(copyPath(_:)), keyEquivalent: "")
        item.image = NSImage(systemSymbolName: "doc.on.doc", accessibilityDescription: nil)
        menu.addItem(item)
        return menu
    }
    
    @objc func copyPath(_ sender: AnyObject?) {
        guard let items = FIFinderSyncController.default().selectedItemURLs() else { return }
        
        if let first = items.first {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(first.path, forType: .string)
        } else if let target = FIFinderSyncController.default().targetedURL() {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(target.path, forType: .string)
        }
    }
}
