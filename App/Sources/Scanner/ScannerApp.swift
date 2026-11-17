import SwiftUI

@main
struct ScannerApp: App {
    @NSApplicationDelegateAdaptor private var appDelegate: AppDelegate
    @StateObject private var controller = ScanController()

    var body: some Scene {
        Window("Scanner", id: "main") {
            ContentView()
                .environmentObject(controller)
                .frame(minWidth: 960, minHeight: 620)
                .onAppear { appDelegate.controller = controller }
        }
        .windowResizability(.contentMinSize)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    weak var controller: ScanController?

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    @MainActor func applicationWillTerminate(_ notification: Notification) {
        controller?.scanner.stop()   // close the Image Capture session cleanly
    }
}
