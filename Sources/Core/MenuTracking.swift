import Foundation

/// The rules a Dock menu follows while it's open, kept apart from drawing so they can be tested.
enum MenuTracking {
    enum Trigger { case rightClick, controlClick, hold, keyboard }
    enum Release: Equatable { case choose, stayOpen, close }

    /// What letting go of the mouse button does.
    /// - Parameters:
    ///   - enteredMenu: the pointer has been over the menu since it opened.
    ///   - overItem: it's over a row that can be chosen now.
    ///   - overMenu: it's over one of the menu's panels at all.
    ///
    /// Let go over a row you dragged to: that row. Let go without having gone into the menu (a quick
    /// right-click, or a click-and-hold that just opened it): the menu stays open to be clicked. Let go
    /// elsewhere after going into it: the menu closes.
    static func release(enteredMenu: Bool, overItem: Bool, overMenu: Bool) -> Release {
        if overItem, enteredMenu { return .choose }
        if !enteredMenu || overMenu { return .stayOpen }
        return .close
    }

    /// The next row that can be chosen, going `step` (+1 down, -1 up) from `current`, wrapping around.
    static func next(from current: Int?, step: Int, selectable: [Bool]) -> Int? {
        let n = selectable.count
        guard n > 0, selectable.contains(true) else { return nil }
        var i = current ?? (step > 0 ? -1 : n)
        for _ in 0..<n {
            i = ((i + step) % n + n) % n
            if selectable[i] { return i }
        }
        return nil
    }

    /// Type-select: the first choosable row whose title starts with what's been typed, searching from
    /// the highlighted row (so typing the same letter again moves on).
    static func typeSelect(_ typed: String, titles: [String], selectable: [Bool], from current: Int?) -> Int? {
        let needle = typed.lowercased()
        guard !needle.isEmpty else { return nil }
        let n = titles.count
        let start = current ?? -1
        // A repeated single letter moves to the next match; longer text keeps the current one if it fits.
        let repeating = needle.count > 1 && Set(needle).count == 1
        let probe = repeating ? String(needle.prefix(1)) : needle
        let first = (repeating || needle.count == 1) ? start + 1 : max(start, 0)
        for k in 0..<n {
            let i = (first + k) % n
            if selectable[i], titles[i].lowercased().hasPrefix(probe) { return i }
        }
        return nil
    }
}
