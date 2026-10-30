import AppKit

// 生成应用图标：深绿渐变底 + 四格色块（与应用内品牌一致）
// 用法: MakeIcon <输出.png 路径>

let size = CGFloat(1024)
let image = NSImage(size: NSSize(width: size, height: size))
image.lockFocus()

let context = NSGraphicsContext.current!.cgContext

// macOS 图标内容区约 824/1024，留出系统边距
let margin = size * 0.10
let contentSize = size - margin * 2
let contentRect = NSRect(x: margin, y: margin, width: contentSize, height: contentSize)
let radius = contentSize * 0.225

// 背景：深绿渐变
let clip = NSBezierPath(roundedRect: contentRect, xRadius: radius, yRadius: radius)
clip.addClip()
let background = NSGradient(colors: [
    NSColor(red: 0.13, green: 0.31, blue: 0.27, alpha: 1),
    NSColor(red: 0.07, green: 0.20, blue: 0.17, alpha: 1),
])!
background.draw(in: contentRect, angle: -65)

// 微光效果
let glow = NSGradient(colors: [
    NSColor(white: 1, alpha: 0.14),
    NSColor(white: 1, alpha: 0),
])!
glow.draw(in: NSRect(x: contentRect.minX, y: contentRect.midY,
                     width: contentRect.width, height: contentRect.height / 2),
          angle: -90)

// 四格色块
let gap = contentSize * 0.055
let inset = contentSize * 0.20
let gridRect = contentRect.insetBy(dx: inset, dy: inset)
let tile = (gridRect.width - gap) / 2
let tileRadius = tile * 0.24
let colors: [NSColor] = [
    NSColor(red: 0.83, green: 0.92, blue: 0.63, alpha: 1), // 黄绿
    NSColor(red: 0.52, green: 0.75, blue: 0.66, alpha: 1), // 青绿
    NSColor(red: 0.63, green: 0.84, blue: 0.73, alpha: 1), // 浅绿
    NSColor(red: 0.94, green: 0.82, blue: 0.56, alpha: 1), // 暖黄
]
let positions: [NSPoint] = [
    NSPoint(x: gridRect.minX, y: gridRect.midY + gap / 2),
    NSPoint(x: gridRect.midX + gap / 2, y: gridRect.midY + gap / 2),
    NSPoint(x: gridRect.minX, y: gridRect.minY),
    NSPoint(x: gridRect.midX + gap / 2, y: gridRect.minY),
]
for (index, origin) in positions.enumerated() {
    let rect = NSRect(x: origin.x, y: origin.y, width: tile, height: tile)
    NSColor(white: 0, alpha: 0.18).setFill()
    NSBezierPath(roundedRect: rect.offsetBy(dx: 0, dy: -tile * 0.05),
                 xRadius: tileRadius, yRadius: tileRadius).fill()
    colors[index].setFill()
    NSBezierPath(roundedRect: rect, xRadius: tileRadius, yRadius: tileRadius).fill()
}

// 右上角星光点缀
let star = NSBezierPath()
let starCenter = NSPoint(x: contentRect.maxX - inset * 0.9, y: contentRect.maxY - inset * 0.9)
let starRadius = contentSize * 0.045
for point in 0..<8 {
    let angle = CGFloat(point) * .pi / 4
    let radiusAt = point % 2 == 0 ? starRadius : starRadius * 0.42
    let location = NSPoint(x: starCenter.x + cos(angle) * radiusAt,
                           y: starCenter.y + sin(angle) * radiusAt)
    if point == 0 { star.move(to: location) } else { star.line(to: location) }
}
star.close()
NSColor(white: 1, alpha: 0.9).setFill()
star.fill()

image.unlockFocus()

guard let tiff = image.tiffRepresentation,
      let rep = NSBitmapImageRep(data: tiff),
      let png = rep.representation(using: .png, properties: [:]) else {
    fputs("图标渲染失败\n", stderr)
    exit(1)
}
let output = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "icon.png"
try! png.write(to: URL(fileURLWithPath: output))
print("图标已生成：\(output)")
