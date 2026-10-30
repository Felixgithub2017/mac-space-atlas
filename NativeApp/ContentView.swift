import AppKit
import SwiftUI

private enum Palette {
    static let pine = Color(red: 0.09, green: 0.23, blue: 0.20)
    static let green = Color(red: 0.19, green: 0.40, blue: 0.30)
    static let mint = Color(red: 0.86, green: 0.94, blue: 0.85)
    static let paper = Color(red: 0.97, green: 0.98, blue: 0.96)
    static let muted = Color(red: 0.49, green: 0.57, blue: 0.52)
}

struct ContentView: View {
    @ObservedObject var model: DiskModel
    @State private var search = ""
    @State private var showLargest = false
    @State private var confirmTrash = false

    private var displayedEntries: [DiskEntry] {
        let source = showLargest ? model.largestFiles : model.entries
        return search.isEmpty ? source : source.filter { $0.name.localizedCaseInsensitiveContains(search) }
    }

    var body: some View {
        HStack(spacing: 0) {
            sidebar
            ScrollView {
                VStack(alignment: .leading, spacing: 25) {
                    header
                    if let message = model.message {
                        HStack(spacing: 10) {
                            Image(systemName: "info.circle")
                            Text(message).frame(maxWidth: .infinity, alignment: .leading)
                            Button { model.message = nil } label: { Image(systemName: "xmark") }
                                .buttonStyle(.plain)
                        }
                        .font(.system(size: 12))
                        .foregroundStyle(Palette.green)
                        .padding(13)
                        .background(Palette.mint.opacity(0.55), in: RoundedRectangle(cornerRadius: 10))
                    }
                    capacityCard
                    if model.phase == .scanning { scanningCard }
                    if model.phase == .complete {
                        if model.currentPath == model.rootPath { highlights }
                        explorer
                    }
                    if model.phase == .idle {
                        Button("开始扫描") { model.startScan(model.home) }
                            .buttonStyle(.borderedProminent)
                    }
                    Text("根据实际分配的磁盘块统计。APFS 快照和共享数据可能使扫描合计与磁盘已使用量不同；无权限的文件夹会跳过。")
                        .font(.system(size: 11))
                        .foregroundStyle(Palette.muted)
                        .padding(.bottom, 22)
                }
                .padding(.horizontal, 34)
                .padding(.top, 30)
                .frame(maxWidth: 1320, alignment: .leading)
                .frame(maxWidth: .infinity)
            }
            .background(Palette.paper)
        }
        .preferredColorScheme(.light)
        .alert("移到废纸篓？", isPresented: $confirmTrash) {
            Button("移到废纸篓", role: .destructive) {
                if let entry = model.selected { model.moveToTrash(entry) }
            }
            Button("取消", role: .cancel) {}
        } message: {
            if let entry = model.selected {
                Text("“\(entry.name)”（\(sizeText(entry.size))）将移到废纸篓。\n\(entry.path)\n\n文件夹会连同内部所有内容一起移动；清空废纸篓后才会释放空间。")
            }
        }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 11) {
                Image(systemName: "square.grid.2x2.fill")
                    .font(.system(size: 19))
                    .foregroundStyle(Color(red: 0.84, green: 0.92, blue: 0.63))
                    .frame(width: 38, height: 38)
                    .background(.white.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
                VStack(alignment: .leading, spacing: 2) {
                    Text("空间地图").font(.system(size: 19, weight: .bold, design: .rounded))
                    Text("SPACE ATLAS").font(.system(size: 8, weight: .bold)).tracking(2)
                        .foregroundStyle(.white.opacity(0.48))
                }
            }
            .padding(.bottom, 49)
            Text("扫描位置")
                .font(.system(size: 10, weight: .bold))
                .tracking(2)
                .foregroundStyle(.white.opacity(0.47))
                .padding(.horizontal, 10)
                .padding(.bottom, 14)
            sidebarButton("我的空间", icon: "house", path: model.home)
            sidebarButton("下载文件夹", icon: "arrow.down.circle", path: model.home + "/Downloads")
            sidebarButton("应用程序", icon: "square.grid.2x2", path: "/Applications")
            sidebarButton("整个启动磁盘", icon: "externaldrive", path: "/")
            Button(action: chooseFolder) {
                Label("选择其他文件夹…", systemImage: "folder.badge.plus")
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 12)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.white.opacity(0.66))
            .disabled(model.phase == .scanning)
            Spacer()
            VStack(alignment: .leading, spacing: 9) {
                Image(systemName: "sparkle").font(.system(size: 24))
                    .foregroundStyle(Color(red: 0.83, green: 0.92, blue: 0.63))
                Text("先看清，再整理。").font(.system(size: 13, weight: .bold))
                Text("不会自动清理文件。只有你确认后，才会将所选内容移到废纸篓。")
                    .font(.system(size: 11)).lineSpacing(4).foregroundStyle(.white.opacity(0.67))
            }
            .padding(17)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
            Text("●  本机运行 · 数据不上传")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.white.opacity(0.5))
                .padding(.top, 22)
                .padding(.leading, 5)
        }
        .padding(.horizontal, 18)
        .padding(.top, 36)
        .padding(.bottom, 24)
        .frame(width: 228)
        .frame(maxHeight: .infinity)
        .background(Palette.pine)
        .foregroundStyle(.white)
    }

    private func sidebarButton(_ title: String, icon: String, path: String) -> some View {
        let active = model.rootPath == path
        return Button { model.startScan(path); search = ""; showLargest = false } label: {
            HStack(spacing: 12) {
                Image(systemName: icon).frame(width: 18)
                Text(title)
                Spacer()
                if active { Circle().fill(Color(red: 0.83, green: 0.92, blue: 0.63)).frame(width: 5, height: 5) }
            }
            .font(.system(size: 12, weight: .semibold))
            .padding(.horizontal, 12)
            .padding(.vertical, 13)
            .background(active ? .white.opacity(0.13) : .clear, in: RoundedRectangle(cornerRadius: 9))
            .foregroundStyle(active ? .white : .white.opacity(0.7))
        }
        .buttonStyle(.plain)
        .disabled(model.phase == .scanning)
    }

    private var header: some View {
        HStack(alignment: .bottom) {
            VStack(alignment: .leading, spacing: 8) {
                Text("YOUR STORAGE, DECODED")
                    .font(.system(size: 10, weight: .bold)).tracking(2)
                    .foregroundStyle(Palette.green.opacity(0.6))
                Text("你的空间，都去哪了？")
                    .font(.system(size: 29, weight: .bold, design: .rounded))
                    .foregroundStyle(Palette.pine)
                Text("找到最占空间的文件夹和大文件，决定哪些值得保留。")
                    .font(.system(size: 12)).foregroundStyle(Palette.muted)
            }
            Spacer()
            Button {
                model.startScan(model.rootPath)
                search = ""
            } label: {
                Label("重新扫描", systemImage: "arrow.clockwise")
                    .font(.system(size: 12, weight: .semibold))
            }
            .buttonStyle(.bordered)
            .disabled(model.phase == .scanning)
        }
    }

    private var capacityCard: some View {
        let used = max(0, model.diskTotal - model.diskFree)
        let ratio = model.diskTotal > 0 ? Double(used) / Double(model.diskTotal) : 0
        return HStack(spacing: 30) {
            VStack(alignment: .leading, spacing: 13) {
                Label("启动磁盘使用概况", systemImage: "circle.dotted.circle.fill")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(Palette.green)
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(sizeText(used)).font(.system(size: 34, weight: .bold, design: .rounded))
                        .foregroundStyle(Palette.pine)
                    Text("/ \(sizeText(model.diskTotal)) 已使用")
                        .font(.system(size: 12)).foregroundStyle(Palette.muted)
                }
                Text("剩余 \(sizeText(model.diskFree)) 可用空间")
                    .font(.system(size: 12)).foregroundStyle(Palette.green)
                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Palette.green.opacity(0.12))
                        Capsule().fill(Palette.green).frame(width: geometry.size.width * ratio)
                    }
                }
                .frame(height: 7)
            }
            Spacer(minLength: 10)
            ZStack {
                Circle().stroke(Palette.green.opacity(0.10), lineWidth: 18)
                Circle().trim(from: 0, to: ratio)
                    .stroke(Palette.green, style: StrokeStyle(lineWidth: 18, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                VStack(spacing: 2) {
                    Text("已使用").font(.system(size: 10)).foregroundStyle(Palette.muted)
                    Text("\(Int(ratio * 100))%")
                        .font(.system(size: 23, weight: .bold, design: .rounded))
                        .foregroundStyle(Palette.pine)
                }
            }
            .frame(width: 121, height: 121)
        }
        .padding(.horizontal, 30)
        .padding(.vertical, 26)
        .frame(maxWidth: .infinity)
        .background(
            LinearGradient(colors: [Color(red: 0.89, green: 0.95, blue: 0.88), .white],
                           startPoint: .leading, endPoint: .trailing),
            in: RoundedRectangle(cornerRadius: 17)
        )
    }

    private var scanningCard: some View {
        HStack(spacing: 14) {
            ProgressView().controlSize(.small)
            VStack(alignment: .leading, spacing: 5) {
                Text("正在绘制空间地图…").font(.system(size: 14, weight: .bold))
                Text("已读取 \(model.fileCount.formatted()) 个文件、\(model.folderCount.formatted()) 个文件夹")
                    .font(.system(size: 12)).foregroundStyle(Palette.muted)
                Text(model.currentScanPath).font(.system(size: 10))
                    .foregroundStyle(Palette.muted).lineLimit(1).truncationMode(.middle)
            }
            Spacer()
        }
        .padding(21)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.white, in: RoundedRectangle(cornerRadius: 13))
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "扫描此文件夹"
        if panel.runModal() == .OK, let path = panel.url?.path {
            model.startScan(path)
            search = ""
            showLargest = false
        }
    }
}

private extension ContentView {
    var highlights: some View {
        let folders = Array(model.entries.filter(\.isFolder).prefix(4))
        return VStack(alignment: .leading, spacing: 15) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("空间最大的文件夹")
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                        .foregroundStyle(Palette.pine)
                    Text("从这些地方开始，最容易找到空间的去向。")
                        .font(.system(size: 11)).foregroundStyle(Palette.muted)
                }
                Spacer()
                Text("扫描 \(model.fileCount.formatted()) 个文件")
                    .font(.system(size: 11)).foregroundStyle(Palette.muted)
            }
            HStack(spacing: 11) {
                ForEach(Array(folders.enumerated()), id: \.element.id) { index, folder in
                    Button {
                        model.openFolder(folder.path)
                        search = ""
                        showLargest = false
                    } label: {
                        VStack(alignment: .leading, spacing: 11) {
                            Image(systemName: "folder.fill")
                                .font(.system(size: 19))
                                .foregroundStyle(index == 0 ? .white.opacity(0.85) : Palette.green)
                            Spacer(minLength: 5)
                            Text(folder.name)
                                .font(.system(size: 12, weight: .bold))
                                .lineLimit(1)
                            Text(sizeText(folder.size))
                                .font(.system(size: 18, weight: .bold, design: .rounded))
                            GeometryReader { geometry in
                                Capsule().fill(index == 0 ? .white.opacity(0.23) : Palette.green.opacity(0.11))
                                    .overlay(alignment: .leading) {
                                        Capsule().fill(index == 0 ? .white : Palette.green.opacity(0.6))
                                            .frame(width: geometry.size.width * min(1, Double(folder.size) / Double(max(model.scannedSize, 1))))
                                    }
                            }
                            .frame(height: 5)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .frame(height: 110)
                        .padding(17)
                        .background(index == 0 ? Palette.green : .white,
                                    in: RoundedRectangle(cornerRadius: 13))
                        .foregroundStyle(index == 0 ? .white : Palette.pine)
                    }
                    .buttonStyle(.plain)
                }
            }
            if model.rootPath == model.home {
                quickChecks
            }
        }
    }

    var quickChecks: some View {
        let suggestions = [
            (model.home + "/.cache", "下载的模型与缓存", "可重新下载，但删除后应用可能需要重新获取", "archivebox"),
            (model.home + "/Downloads", "下载文件夹", "检查安装包、压缩包与重复下载", "arrow.down.circle")
        ]
        return HStack(spacing: 11) {
            ForEach(suggestions, id: \.0) { path, title, subtitle, symbol in
                if let folder = model.folderEntry(at: path) {
                    Button {
                        model.openFolder(path)
                        search = ""
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: symbol).font(.system(size: 17))
                                .frame(width: 36, height: 36)
                                .background(Palette.mint, in: RoundedRectangle(cornerRadius: 9))
                            VStack(alignment: .leading, spacing: 4) {
                                Text(title).font(.system(size: 12, weight: .bold))
                                Text(subtitle).font(.system(size: 10))
                                    .foregroundStyle(Palette.muted).lineLimit(1)
                            }
                            Spacer(minLength: 4)
                            Text(sizeText(folder.size))
                                .font(.system(size: 12, weight: .bold)).lineLimit(1)
                        }
                        .padding(12)
                        .background(.white, in: RoundedRectangle(cornerRadius: 10))
                        .foregroundStyle(Palette.pine)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    var explorer: some View {
        VStack(alignment: .leading, spacing: 15) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("文件与文件夹")
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                        .foregroundStyle(Palette.pine)
                    Text("按占用空间排序 · 双击文件夹进入")
                        .font(.system(size: 11)).foregroundStyle(Palette.muted)
                }
                Spacer()
                Text("\(model.skipped) 个项目无法读取")
                    .font(.system(size: 10)).foregroundStyle(Palette.muted)
            }
            HStack(spacing: 11) {
                Button { model.goBack(); search = "" } label: {
                    Image(systemName: "arrow.left")
                        .frame(width: 26, height: 26)
                }
                .buttonStyle(.bordered)
                .disabled(!model.canGoBack)
                Image(systemName: "folder")
                    .foregroundStyle(Palette.green)
                Text(model.currentPath)
                    .font(.system(size: 11, weight: .medium))
                    .lineLimit(1).truncationMode(.middle)
                    .help(model.currentPath)
                Spacer()
                TextField("筛选当前列表…", text: $search)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 190)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(.white, in: RoundedRectangle(cornerRadius: 10))
            HStack(spacing: 4) {
                tabButton("当前目录", icon: "folder", active: !showLargest) { showLargest = false; search = ""; model.selected = nil }
                tabButton("最大文件", icon: "doc.text", active: showLargest) { showLargest = true; search = ""; model.selected = nil }
                Spacer()
                Text("\(displayedEntries.count.formatted()) 项")
                    .font(.system(size: 11)).foregroundStyle(Palette.muted)
            }
            HStack(alignment: .top, spacing: 14) {
                VStack(spacing: 0) {
                    if displayedEntries.isEmpty {
                        Text(search.isEmpty ? "这里没有文件" : "没有匹配的文件")
                            .font(.system(size: 12)).foregroundStyle(Palette.muted)
                            .frame(maxWidth: .infinity, minHeight: 190)
                    } else {
                        LazyVStack(spacing: 0) {
                            ForEach(displayedEntries) { entry in
                                entryRow(entry)
                                if entry.id != displayedEntries.last?.id { Divider().padding(.leading, 53) }
                            }
                        }
                    }
                }
                .background(.white, in: RoundedRectangle(cornerRadius: 12))
                .frame(maxWidth: .infinity)
                inspector
                    .frame(width: 230)
            }
        }
    }

    func tabButton(_ title: String, icon: String, active: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: icon)
                .font(.system(size: 11, weight: .semibold))
                .padding(.horizontal, 12).padding(.vertical, 8)
                .background(active ? Palette.mint : .clear, in: RoundedRectangle(cornerRadius: 8))
                .foregroundStyle(active ? Palette.green : Palette.muted)
        }
        .buttonStyle(.plain)
    }

    func entryRow(_ entry: DiskEntry) -> some View {
        let selected = model.selected?.path == entry.path
        return HStack(spacing: 12) {
            Image(systemName: entry.isFolder ? "folder.fill" : "doc.fill")
                .font(.system(size: 16))
                .foregroundStyle(entry.isFolder ? Palette.green : Palette.muted)
                .frame(width: 33, height: 33)
                .background(entry.isFolder ? Palette.mint.opacity(0.65) : Palette.paper,
                            in: RoundedRectangle(cornerRadius: 8))
            VStack(alignment: .leading, spacing: 4) {
                Text(entry.name)
                    .font(.system(size: 12, weight: .semibold))
                    .lineLimit(1)
                Text(entry.isFolder ? "\(entry.itemCount) 个直接项目" : entry.path)
                    .font(.system(size: 10))
                    .foregroundStyle(Palette.muted)
                    .lineLimit(1).truncationMode(.middle)
            }
            Spacer(minLength: 8)
            Text(sizeText(entry.size))
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(Palette.green)
                .fixedSize()
            if entry.isFolder && !showLargest {
                Button { model.openFolder(entry.path); search = "" } label: {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(Palette.muted)
                        .frame(width: 22, height: 28)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 13)
        .padding(.vertical, 11)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(selected ? Palette.mint.opacity(0.6) : .clear)
        .contentShape(Rectangle())
        .onTapGesture(count: 2) {
            if entry.isFolder { model.openFolder(entry.path); search = ""; showLargest = false }
            else { model.selected = entry }
        }
        .onTapGesture { model.selected = entry }
    }

    var inspector: some View {
        VStack(alignment: .leading, spacing: 15) {
            Text("项目详情")
                .font(.system(size: 12, weight: .bold)).foregroundStyle(Palette.pine)
            if let entry = model.selected {
                Image(systemName: entry.isFolder ? "folder.fill" : "doc.fill")
                    .font(.system(size: 28))
                    .foregroundStyle(Palette.green)
                    .frame(width: 54, height: 54)
                    .background(Palette.mint, in: RoundedRectangle(cornerRadius: 12))
                Text(entry.name)
                    .font(.system(size: 13, weight: .bold))
                    .lineLimit(2)
                    .textSelection(.enabled)
                Text(sizeText(entry.size))
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .foregroundStyle(Palette.green)
                Text(entry.path)
                    .font(.system(size: 10))
                    .foregroundStyle(Palette.muted)
                    .textSelection(.enabled)
                    .lineLimit(4)
                Divider()
                Button { model.reveal(entry) } label: {
                    Label("在 Finder 中显示", systemImage: "arrow.up.forward.app")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                Button { confirmTrash = true } label: {
                    Label("移到废纸篓", systemImage: "trash")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .tint(.red)
                .disabled(!model.canTrashSelected)
                if !model.canTrashSelected {
                    Text("为保护系统，只能在此应用内清理个人主目录中的项目。")
                        .font(.system(size: 10))
                        .foregroundStyle(Palette.muted)
                }
                Spacer(minLength: 0)
            } else {
                Image(systemName: "cursorarrow.click.2")
                    .font(.system(size: 29))
                    .foregroundStyle(Palette.green.opacity(0.45))
                    .padding(.top, 30)
                Text("选中一个项目")
                    .font(.system(size: 13, weight: .semibold))
                Text("查看路径、在 Finder 定位，或确认后移到废纸篓。")
                    .font(.system(size: 11))
                    .foregroundStyle(Palette.muted)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, minHeight: 270, alignment: .topLeading)
        .background(.white, in: RoundedRectangle(cornerRadius: 12))
    }
}
