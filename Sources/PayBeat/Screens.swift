import AppKit

private func displayID(_ screen: NSScreen) -> CGDirectDisplayID? {
    (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value
}

/// Value stored in `Config.notchScreen` for this screen: "display:<UUID>", stable across reconnects.
func screenTag(_ screen: NSScreen) -> String? {
    guard let id = displayID(screen), let uuid = CGDisplayCreateUUIDFromDisplayID(id)?.takeRetainedValue() else {
        return nil
    }
    return "display:" + (CFUUIDCreateString(nil, uuid) as String)
}

func screenName(_ screen: NSScreen) -> String {
    if let id = displayID(screen), CGDisplayIsBuiltin(id) != 0 { return L("内建显示器") }
    return screen.localizedName
}

/// Screen for the notch island: the chosen display while it is connected,
/// otherwise the screen with a notch, otherwise the main screen.
func notchScreen(_ choice: String) -> NSScreen? {
    if !choice.isEmpty, let pinned = NSScreen.screens.first(where: { screenTag($0) == choice }) {
        return pinned
    }
    return NSScreen.screens.first(where: { $0.safeAreaInsets.top > 0 }) ?? NSScreen.main
}
