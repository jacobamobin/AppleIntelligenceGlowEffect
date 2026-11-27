import Foundation

public final class PipeLineReader {
    private let handle: FileHandle
    private var pending = Data()
    public init(_ handle: FileHandle) { self.handle = handle }
    public func next() throws -> Data? {
        while true {
            if let newline = pending.firstIndex(of: 10) {
                let line = Data(pending[...newline])
                pending.removeSubrange(...newline)
                return line
            }
            guard pending.count <= 100_000 else {
                throw NSError(domain: "MusicGlow.Helper", code: 1, userInfo: [NSLocalizedDescriptionKey: "Helper response is too large"])
            }
            // read(upToCount:) waits to fill its requested length on a persistent pipe.
            // availableData returns the bytes already delivered without waiting for EOF.
            let chunk = handle.availableData
            if chunk.isEmpty { let tail = pending; pending.removeAll(); return tail.isEmpty ? nil : tail }
            pending.append(chunk)
        }
    }
}
