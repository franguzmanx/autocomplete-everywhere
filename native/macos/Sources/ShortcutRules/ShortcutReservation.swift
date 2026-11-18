/// Fixed actions cannot be reassigned. Keep the desktop schema in sync.
public enum ShortcutReservation {
    public static func isReserved(keyCode: Int, modifiers: Int) -> Bool {
        modifiers == 2048 && ([48, 125, 126].contains(keyCode) || transformNumber(keyCode: keyCode) != nil)
    }

    public static func transformNumber(keyCode: Int) -> Int? {
        [18: 1, 19: 2, 20: 3, 21: 4, 23: 5, 22: 6, 26: 7, 28: 8, 25: 9][keyCode]
    }
}
