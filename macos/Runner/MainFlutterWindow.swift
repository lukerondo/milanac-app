import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    self.contentViewController = flutterViewController

    // L'app è pensata per il telefono: finestra in verticale al centro dello schermo,
    // mai più alta dello spazio libero tra la barra dei menu e il Dock.
    self.title = "MILANAC"
    self.contentMinSize = NSSize(width: 380, height: 700)
    var windowFrame = self.frameRect(forContentRect: NSRect(x: 0, y: 0, width: 430, height: 900))
    if let visible = (self.screen ?? NSScreen.main)?.visibleFrame {
      windowFrame.size.height = min(windowFrame.size.height, visible.size.height)
    }
    self.setFrame(windowFrame, display: true)
    self.center()

    RegisterGeneratedPlugins(registry: flutterViewController)

    super.awakeFromNib()
  }
}
