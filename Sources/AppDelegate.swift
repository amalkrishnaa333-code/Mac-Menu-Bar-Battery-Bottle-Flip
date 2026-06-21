import AppKit

class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var bottleView: BottleView!

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: 26)
        guard let button = statusItem.button else { return }

        button.image = nil
        button.title = ""
        button.target = nil
        button.action = nil

        bottleView = BottleView(frame: NSRect(x: 0, y: 0, width: 26, height: 22))
        bottleView.autoresizingMask = [.width, .height]
        button.addSubview(bottleView)

        bottleView.waterLevel = BatteryMonitor.shared.getBatteryLevel()
        BatteryMonitor.shared.onChange = { [weak self] level in
            DispatchQueue.main.async {
                self?.bottleView.waterLevel = level
            }
        }
        BatteryMonitor.shared.startMonitoring()
    }
}
