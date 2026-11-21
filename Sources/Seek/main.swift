import AppKit

if CommandLine.arguments.contains("--self-test") {
    let ok = SeekSelfTest.runAllTests()
    exit(ok ? 0 : 1)
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
