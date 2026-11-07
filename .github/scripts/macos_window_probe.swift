import CoreGraphics
import Foundation

let pid = Int(CommandLine.arguments[1])!
let windows = CGWindowListCopyWindowInfo([.optionAll, .excludeDesktopElements], kCGNullWindowID)
    as? [[String: Any]] ?? []
for window in windows {
    guard window[kCGWindowOwnerPID as String] as? Int == pid,
          let bounds = window[kCGWindowBounds as String] as? [String: Any],
          let width = bounds["Width"] as? Double,
          let height = bounds["Height"] as? Double,
          width >= 960, height >= 700 else { continue }
    // The runner starts at 800x600. Reaching this size proves the packaged Dart runtime invoked
    // window_manager, in addition to the native process starting successfully.
    let result: [String: Any] = ["windowId": window[kCGWindowNumber as String]!,
                                 "width": width, "height": height]
    print(String(data: try! JSONSerialization.data(withJSONObject: result), encoding: .utf8)!)
    exit(0)
}
exit(1)
