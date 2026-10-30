# 空间地图 (mac-space-atlas)

直接双击 **`空间地图.app`** 启动 macOS 客户端，不需要浏览器或常驻服务。首次打开会自动扫描个人主目录。左侧可以切换下载文件夹、应用程序、整个启动磁盘，或选择任意文件夹。

## 功能

- **空间概览**：启动磁盘已用/剩余容量一目了然。
- **最大文件夹**：首页直接列出占用空间最多的文件夹，快速定位空间去向。
- **逐层浏览**：点击文件夹深入，按占用空间排序；支持筛选当前列表。
- **最大文件**：切换到“最大文件”标签，查看扫描范围内最大的单个文件。
- **安全清理**：选中项目可在 Finder 中定位；确认后移到废纸篓（可恢复），不会自动永久删除。

## 快速开始

```sh
git clone https://github.com/Felixgithub2017/mac-space-atlas.git
cd mac-space-atlas
./build-mac-app.sh
open 空间地图.app
```

构建只需要 macOS 自带的 Swift 命令行工具（Xcode Command Line Tools），无第三方依赖。

## 使用须知

- 选中项目后可在 Finder 中定位。点击“移到废纸篓”并再次确认才会移动文件或整个文件夹；不会自动清理或永久删除。
- 为避免误删，应用内只允许将**个人主目录下、非当前扫描根目录**的项目移到废纸篓。系统目录只提供查看和 Finder 定位。
- **移到废纸篓不会立即释放磁盘空间。** 确认不再需要后，须自行在 Finder 中清空废纸篓；清空前仍可恢复。
- 扫描在本机进行，不跟随符号链接，也不上传数据。大小使用文件实际分配的磁盘块；APFS 快照、共享块等可能使扫描合计与 macOS 显示的已使用量不同。无权限读取的文件夹会被跳过。需要扫描更多系统目录时，可以在“系统设置 → 隐私与安全性 → 完全磁盘访问权限”中为“空间地图”授权。

## 网页版（可选）

不装客户端也可以用网页版：`python3 app.py` 后打开 http://127.0.0.1:8766 。

## 构建

`./build-mac-app.sh` 使用 MacOSX26.5 SDK 编译 Swift 源码并打包 `空间地图.app`；图标源文件为 `NativeApp/MakeIcon.swift`（生成 `icon-1024.png`）与 `NativeApp/SpaceAtlas.icns`。

## 测试

`python3 -m unittest -v test_app.py`；Swift 扫描器测试位于 `NativeApp/ScannerTests.swift`。

## License

MIT
