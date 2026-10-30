import AppKit
import Foundation
import SwiftUI

struct DiskEntry: Identifiable, Hashable {
    let name: String
    let path: String
    let size: Int64
    let isFolder: Bool
    let itemCount: Int

    var id: String { path }
}

struct FileRecord {
    let name: String
    let size: Int64
}

private struct FileIdentity: Hashable {
    let device: UInt64
    let inode: UInt64
}

final class FolderNode {
    let name: String
    let path: String
    var size: Int64 = 0
    var folders: [FolderNode] = []
    var files: [FileRecord] = []

    init(name: String, path: String) {
        self.name = name
        self.path = path
    }
}

struct ScanResult {
    let root: FolderNode
    let index: [String: FolderNode]
    let largestFiles: [DiskEntry]
    let fileCount: Int
    let skipped: Int
}

enum DiskScanner {
    static func scan(_ path: String, progress: @escaping (Int, Int, String) -> Void) -> ScanResult {
        let root = FolderNode(name: URL(fileURLWithPath: path).lastPathComponent, path: path)
        var index: [String: FolderNode] = [path: root]
        var largest: [DiskEntry] = []
        var hardLinks = Set<FileIdentity>()
        var fileCount = 0
        var folderCount = 0
        var skipped = 0
        var stack: [(FolderNode, Bool)] = [(root, false)]
        let manager = FileManager.default

        while let (folder, finished) = stack.popLast() {
            if finished {
                folder.size += folder.folders.reduce(0) { $0 + $1.size }
                continue
            }
            stack.append((folder, true))
            guard let names = try? manager.contentsOfDirectory(atPath: folder.path) else {
                skipped += 1
                continue
            }
            for name in names {
                let childPath = (folder.path as NSString).appendingPathComponent(name)
                var details = stat()
                guard childPath.withCString({ lstat($0, &details) }) == 0 else {
                    skipped += 1
                    continue
                }
                let kind = details.st_mode & mode_t(S_IFMT)
                if kind == mode_t(S_IFDIR) {
                    if path == "/" && (childPath == "/System/Volumes" || childPath == "/Volumes") {
                        skipped += 1
                        continue
                    }
                    let child = FolderNode(name: name, path: childPath)
                    folder.folders.append(child)
                    index[childPath] = child
                    folderCount += 1
                    stack.append((child, false))
                } else if kind == mode_t(S_IFREG) {
                    var size = max(0, Int64(details.st_blocks) * 512)
                    if details.st_nlink > 1 {
                        let identity = FileIdentity(device: UInt64(details.st_dev), inode: UInt64(details.st_ino))
                        if !hardLinks.insert(identity).inserted { size = 0 }
                    }
                    folder.files.append(FileRecord(name: name, size: size))
                    folder.size += size
                    fileCount += 1
                    if largest.count < 40 || size > (largest.last?.size ?? 0) {
                        largest.append(DiskEntry(name: name, path: childPath, size: size, isFolder: false, itemCount: 0))
                        largest.sort { $0.size > $1.size }
                        if largest.count > 40 { largest.removeLast() }
                    }
                }
                if (fileCount + folderCount) % 1000 == 0 {
                    progress(fileCount, folderCount, folder.path)
                }
            }
        }
        return ScanResult(root: root, index: index, largestFiles: largest,
                          fileCount: fileCount, skipped: skipped)
    }
}

@MainActor
final class DiskModel: ObservableObject {
    enum Phase { case idle, scanning, complete }

    @Published var phase: Phase = .idle
    @Published var rootPath = NSHomeDirectory()
    @Published var currentPath = NSHomeDirectory()
    @Published var entries: [DiskEntry] = []
    @Published var largestFiles: [DiskEntry] = []
    @Published var selected: DiskEntry?
    @Published var fileCount = 0
    @Published var folderCount = 0
    @Published var skipped = 0
    @Published var scannedSize: Int64 = 0
    @Published var currentScanPath = ""
    @Published var message: String?
    @Published var diskTotal: Int64 = 0
    @Published var diskFree: Int64 = 0

    private var result: ScanResult?
    private var scanID = UUID()

    init() { refreshDiskSpace() }

    var home: String { NSHomeDirectory() }
    var canGoBack: Bool { phase == .complete && currentPath != rootPath }
    var canTrashSelected: Bool {
        guard let selected else { return false }
        let home = URL(fileURLWithPath: NSHomeDirectory()).resolvingSymlinksInPath().path
        let target = URL(fileURLWithPath: selected.path).resolvingSymlinksInPath().path
        return target.hasPrefix(home + "/") && selected.path != rootPath
    }

    func refreshDiskSpace() {
        if let attributes = try? FileManager.default.attributesOfFileSystem(forPath: NSHomeDirectory()) {
            diskTotal = (attributes[.systemSize] as? NSNumber)?.int64Value ?? 0
            diskFree = (attributes[.systemFreeSize] as? NSNumber)?.int64Value ?? 0
        }
    }

    func startScan(_ path: String) {
        guard phase != .scanning else { return }
        let normalized = URL(fileURLWithPath: path).standardizedFileURL.path
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: normalized, isDirectory: &isDirectory),
              isDirectory.boolValue else {
            message = "无法访问这个文件夹。"
            return
        }
        rootPath = normalized
        currentPath = normalized
        selected = nil
        entries = []
        largestFiles = []
        result = nil
        phase = .scanning
        fileCount = 0
        folderCount = 0
        skipped = 0
        scannedSize = 0
        currentScanPath = normalized
        refreshDiskSpace()
        let token = UUID()
        scanID = token
        DispatchQueue.global(qos: .userInitiated).async {
            let scanned = DiskScanner.scan(normalized) { files, folders, location in
                DispatchQueue.main.async {
                    guard self.scanID == token else { return }
                    self.fileCount = files
                    self.folderCount = folders
                    self.currentScanPath = location
                }
            }
            DispatchQueue.main.async {
                guard self.scanID == token else { return }
                self.result = scanned
                self.fileCount = scanned.fileCount
                self.folderCount = scanned.index.count - 1
                self.skipped = scanned.skipped
                self.scannedSize = scanned.root.size
                self.largestFiles = scanned.largestFiles
                self.phase = .complete
                self.refreshDiskSpace()
                self.openFolder(normalized)
            }
        }
    }

    func openFolder(_ path: String) {
        guard let folder = result?.index[path] else { return }
        currentPath = path
        selected = nil
        var contents = folder.folders.map {
            DiskEntry(name: $0.name, path: $0.path, size: $0.size,
                      isFolder: true, itemCount: $0.folders.count + $0.files.count)
        }
        contents += folder.files.map {
            DiskEntry(name: $0.name, path: (path as NSString).appendingPathComponent($0.name),
                      size: $0.size, isFolder: false, itemCount: 0)
        }
        entries = contents.sorted {
            $0.size == $1.size ? $0.name.localizedStandardCompare($1.name) == .orderedAscending : $0.size > $1.size
        }
    }

    func goBack() {
        guard canGoBack else { return }
        openFolder((currentPath as NSString).deletingLastPathComponent)
    }

    func folderEntry(at path: String) -> DiskEntry? {
        guard let folder = result?.index[path] else { return nil }
        return DiskEntry(name: folder.name, path: folder.path, size: folder.size,
                         isFolder: true, itemCount: folder.folders.count + folder.files.count)
    }

    func reveal(_ entry: DiskEntry) {
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: entry.path)])
    }

    func moveToTrash(_ entry: DiskEntry) {
        guard canTrashSelected, selected?.path == entry.path else { return }
        let url = URL(fileURLWithPath: entry.path)
        NSWorkspace.shared.recycle([url]) { _, error in
            DispatchQueue.main.async {
                if let error {
                    self.message = "无法移到废纸篓：\(error.localizedDescription)"
                } else {
                    self.message = "已移到废纸篓。清空废纸篓后，磁盘空间才会真正释放。"
                    self.startScan(self.rootPath)
                }
            }
        }
    }
}

func sizeText(_ bytes: Int64) -> String {
    ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
}
