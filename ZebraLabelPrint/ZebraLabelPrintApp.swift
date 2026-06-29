import SwiftUI

@main
struct ZebraLabelPrintApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        // wider form column; preview uses remaining window space at full size
        .defaultSize(width: 1640, height: 1040)
    }
}
