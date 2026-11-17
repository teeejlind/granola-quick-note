// app-windows: print "<windowID> <width>x<height> <title>" for every normal-layer window
// owned by the app with the given bundle ID, on every Space.
//
// Why this exists: Hammerspoon (Accessibility) only sees windows on the Spaces that are
// currently visible. CoreGraphics lists windows on all Spaces, which is what the Spoon
// needs to find a window parked on another Space and switch to it.
//
// Usage: app-windows <bundle-id>
// Exit codes: 0 ok, 1 app not running, 2 bad arguments.
import AppKit
import CoreGraphics

guard CommandLine.arguments.count == 2 else { exit(2) }
let bundleID = CommandLine.arguments[1]
let pids = Set(NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
  .map { $0.processIdentifier })
guard !pids.isEmpty else { exit(1) }

let options: CGWindowListOption = [.optionAll, .excludeDesktopElements]
let windows = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] ?? []
for window in windows {
  guard let pid = window[kCGWindowOwnerPID as String] as? pid_t, pids.contains(pid),
        (window[kCGWindowLayer as String] as? Int) == 0,
        let number = window[kCGWindowNumber as String] as? Int,
        let bounds = window[kCGWindowBounds as String] as? [String: CGFloat] else { continue }
  let width = Int(bounds["Width"] ?? 0), height = Int(bounds["Height"] ?? 0)
  let title = window[kCGWindowName as String] as? String ?? ""
  print("\(number) \(width)x\(height) \(title)")
}
