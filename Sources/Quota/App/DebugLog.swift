import Foundation

/// Writes a line to stderr in DEBUG builds only (no-op in release).
@inline(__always)
func debugLog(_ message: String) {
#if DEBUG
    FileHandle.standardError.write((message + "\n").data(using: .utf8) ?? Data())
#endif
}
