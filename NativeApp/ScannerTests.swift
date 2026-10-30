import Foundation

@main
struct ScannerTests {
    static func main() throws {
        let base = FileManager.default.temporaryDirectory
            .appendingPathComponent("space-atlas-test-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: base) }

        let folder = base.appendingPathComponent("large", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let file = folder.appendingPathComponent("sample.bin")
        try Data(repeating: 65, count: 8192).write(to: file)
        try FileManager.default.linkItem(at: file, to: base.appendingPathComponent("hard-link.bin"))
        try FileManager.default.createSymbolicLink(
            at: base.appendingPathComponent("shortcut"),
            withDestinationURL: folder
        )

        let result = DiskScanner.scan(base.path) { _, _, _ in }
        var info = stat()
        precondition(file.path.withCString { lstat($0, &info) } == 0)
        precondition(result.root.size == Int64(info.st_blocks) * 512, "Hard links must not count twice")
        precondition(result.fileCount == 2, "Symlinks must not be followed")
        precondition(result.index[folder.path] != nil)
        precondition(result.largestFiles.first?.size == Int64(info.st_blocks) * 512)
        print("Scanner tests passed")
    }
}
