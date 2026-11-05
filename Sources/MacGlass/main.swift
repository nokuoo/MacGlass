import AppKit
import Darwin
import Foundation

@MainActor
private func runApplication() {
    let application = NSApplication.shared

    if CommandLine.arguments.contains("--diagnose") {
        application.setActivationPolicy(.accessory)
        Task { @MainActor in
            let report = await YabaiEngine().inspect()
            print(report.diagnosticText)
            fflush(stdout)
            exit(report.isReady ? 0 : 2)
        }
        application.run()
    } else {
        application.setActivationPolicy(.accessory)
        let delegate = AppDelegate()
        application.delegate = delegate
        application.run()
    }
}

MainActor.assumeIsolated {
    runApplication()
}
