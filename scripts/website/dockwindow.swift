// Prints the window number of the running OldMacDoc's dock, for `screencapture -l`, which captures
// that window on its own: the dock with a transparent background, and no other windows in the shot.
import AppKit

let dockLevel = Int(CGWindowLevelForKey(.dockWindow))
let windows = CGWindowListCopyWindowInfo([.optionAll], kCGNullWindowID) as? [[String: Any]] ?? []
let dock = windows.first { w in
    w[kCGWindowOwnerName as String] as? String == "OldMacDoc" && w[kCGWindowLayer as String] as? Int == dockLevel
}
guard let number = dock?[kCGWindowNumber as String] as? Int else {
    FileHandle.standardError.write(Data("No OldMacDoc dock window found. Is a Debug build running (make run)?\n".utf8))
    exit(1)
}
print(number)
