/// The existing log is checked before appending, not the projected entry size.
public enum DebugLogRotation {
    /// 1 MB in decimal bytes. Exactly at the limit, do not rotate yet;
    /// after exceeding it, rotate before the following write.
    public static let maximumFileSize: UInt64 = 1_000_000

    public static func shouldRotate(fileSize: UInt64) -> Bool {
        fileSize > maximumFileSize
    }
}
