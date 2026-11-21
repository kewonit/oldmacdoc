import AppKit
import ApplicationServices

// Small Accessibility helpers, shared by the menus (AppMenus.swift) and DockClearanceController. They can be
// called from any thread.

func ax(_ element: AXUIElement, _ attribute: String) -> AnyObject? {
    var value: AnyObject?
    return AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success ? value : nil
}

func axChildren(_ element: AXUIElement) -> [AXUIElement] {
    ax(element, kAXChildrenAttribute) as? [AXUIElement] ?? []
}

func axRole(_ element: AXUIElement) -> String { ax(element, kAXRoleAttribute) as? String ?? "" }

/// An attribute whose value is another element (an app's focused window, say).
func axElement(_ element: AXUIElement, _ attribute: String) -> AXUIElement? {
    guard let value = ax(element, attribute), CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
    return (value as! AXUIElement)
}

/// A window's frame in Accessibility coordinates (origin at the main display's top left, y down).
func axFrame(_ element: AXUIElement) -> CGRect? {
    guard let position = ax(element, kAXPositionAttribute), let size = ax(element, kAXSizeAttribute),
          CFGetTypeID(position) == AXValueGetTypeID(), CFGetTypeID(size) == AXValueGetTypeID() else { return nil }
    var origin = CGPoint.zero, extent = CGSize.zero
    guard AXValueGetValue(position as! AXValue, .cgPoint, &origin),
          AXValueGetValue(size as! AXValue, .cgSize, &extent) else { return nil }
    return CGRect(origin: origin, size: extent)
}

@discardableResult
func axSetSize(_ element: AXUIElement, _ size: CGSize) -> Bool {
    var size = size
    guard let value = AXValueCreate(.cgSize, &size) else { return false }
    return AXUIElementSetAttributeValue(element, kAXSizeAttribute as CFString, value) == .success
}

@discardableResult
func axSetPosition(_ element: AXUIElement, _ point: CGPoint) -> Bool {
    var point = point
    guard let value = AXValueCreate(.cgPoint, &point) else { return false }
    return AXUIElementSetAttributeValue(element, kAXPositionAttribute as CFString, value) == .success
}

func axIsSettable(_ element: AXUIElement, _ attribute: String) -> Bool {
    var settable: DarwinBoolean = false
    return AXUIElementIsAttributeSettable(element, attribute as CFString, &settable) == .success && settable.boolValue
}

/// The window server's number for a window (`_AXUIElementGetWindow`, private, looked up at runtime: Rectangle,
/// AltTab and yabai use it). Nil when the call is missing or the element isn't a window.
func axWindowNumber(_ element: AXUIElement) -> CGWindowID? {
    guard let getWindow = AXPrivate.getWindow else { return nil }
    var id: CGWindowID = 0
    return getWindow(element, &id) == .success && id != 0 ? id : nil
}

private enum AXPrivate {
    typealias GetWindow = @convention(c) (AXUIElement, UnsafeMutablePointer<CGWindowID>) -> AXError
    static let getWindow: GetWindow? = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "_AXUIElementGetWindow")
        .map { unsafeBitCast($0, to: GetWindow.self) }
}
