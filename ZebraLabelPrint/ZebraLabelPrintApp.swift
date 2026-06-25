import SwiftUI

@main
struct ZebraLabelPrintApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        // big window on purpose — preview needs the space
        .defaultSize(width: 1640, height: 1040)
    }
}
