import AppKit
import Foundation

let root = URL(fileURLWithPath: CommandLine.arguments.dropFirst().first ?? FileManager.default.currentDirectoryPath)
let resources = root.appendingPathComponent("Resources", isDirectory: true)
let work = root.appendingPathComponent("work/icon-source", isDirectory: true)
let fileManager = FileManager.default
try fileManager.createDirectory(at: resources, withIntermediateDirectories: true)
try fileManager.createDirectory(at: work, withIntermediateDirectories: true)

let canvas = 1024
guard let bitmap = NSBitmapImageRep(
    bitmapDataPlanes: nil,
    pixelsWide: canvas,
    pixelsHigh: canvas,
    bitsPerSample: 8,
    samplesPerPixel: 4,
    hasAlpha: true,
    isPlanar: false,
    colorSpaceName: .deviceRGB,
    bytesPerRow: 0,
    bitsPerPixel: 0
) else {
    fatalError("无法创建图标画布")
}

NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
NSGraphicsContext.current?.imageInterpolation = .high
// 透明外边距 + 圆角底板，是 macOS App 图标的标准结构。
NSColor.clear.setFill()
NSRect(x: 0, y: 0, width: canvas, height: canvas).fill()

let tileRect = NSRect(x: 92, y: 92, width: 840, height: 840)
let tile = NSBezierPath(roundedRect: tileRect, xRadius: 186, yRadius: 186)
NSColor(srgbRed: 0.18, green: 0.49, blue: 0.92, alpha: 1).setFill()
tile.fill()

NSGraphicsContext.restoreGraphicsState()
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
NSGraphicsContext.current?.imageInterpolation = .high

// 后层窗口：扁平实色，表达“窗口层叠”。
let back = NSBezierPath(
    roundedRect: NSRect(x: 236, y: 474, width: 438, height: 286),
    xRadius: 28,
    yRadius: 28
)
NSColor(srgbRed: 0.74, green: 0.83, blue: 0.96, alpha: 1).setFill()
back.fill()
NSColor(srgbRed: 0.55, green: 0.68, blue: 0.86, alpha: 1).setStroke()
back.lineWidth = 3
back.stroke()

// 前层窗口：单一主色，不做渐变和透明叠色。
let front = NSBezierPath(
    roundedRect: NSRect(x: 350, y: 352, width: 438, height: 286),
    xRadius: 28,
    yRadius: 28
)
NSColor.white.setFill()
front.fill()
NSColor(srgbRed: 0.80, green: 0.87, blue: 0.97, alpha: 1).setStroke()
front.lineWidth = 3
front.stroke()

// 标题栏和三个控制点，保留 macOS 窗口的识别特征。
let titleBar = NSBezierPath(
    roundedRect: NSRect(x: 350, y: 586, width: 438, height: 52),
    xRadius: 24,
    yRadius: 24
)
NSColor(srgbRed: 0.90, green: 0.94, blue: 1.00, alpha: 1).setFill()
titleBar.fill()

for index in 0..<3 {
    let dot = NSBezierPath(
        ovalIn: NSRect(
            x: 372 + CGFloat(index) * 18,
            y: 606,
            width: 10,
            height: 10
        )
    )
    NSColor(srgbRed: 0.18, green: 0.49, blue: 0.92, alpha: 1).setFill()
    dot.fill()
}

// 底部两条白线表示透明度调节刻度。
for index in 0..<2 {
    let line = NSBezierPath(
        roundedRect: NSRect(
            x: 388 + CGFloat(index) * 42,
            y: 390,
            width: 30,
            height: 8
        ),
        xRadius: 4,
        yRadius: 4
    )
    NSColor(srgbRed: 0.18, green: 0.49, blue: 0.92, alpha: 1)
        .withAlphaComponent(index == 0 ? 0.95 : 0.55)
        .setFill()
    line.fill()
}

NSGraphicsContext.restoreGraphicsState()

guard let png = bitmap.representation(using: .png, properties: [:]) else {
    fatalError("无法编码图标 PNG")
}
let masterURL = work.appendingPathComponent("AppIcon-1024.png")
try png.write(to: masterURL)

let iconset = work.appendingPathComponent("AppIcon.iconset", isDirectory: true)
if fileManager.fileExists(atPath: iconset.path) {
    try fileManager.removeItem(at: iconset)
}
try fileManager.createDirectory(at: iconset, withIntermediateDirectories: true)

let sizes: [(String, Int)] = [
    ("icon_16x16.png", 16),
    ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32),
    ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128),
    ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256),
    ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512),
    ("icon_512x512@2x.png", 1024)
]

for (name, size) in sizes {
    let destination = iconset.appendingPathComponent(name)
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/sips")
    process.arguments = [
        "-z", "\(size)", "\(size)",
        masterURL.path,
        "--out", destination.path
    ]
    process.standardOutput = FileHandle.nullDevice
    process.standardError = FileHandle.nullDevice
    try process.run()
    process.waitUntilExit()
    guard process.terminationStatus == 0 else {
        fatalError("sips 生成 \(name) 失败")
    }
}

let icns = resources.appendingPathComponent("AppIcon.icns")
let iconutil = Process()
iconutil.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
iconutil.arguments = ["-c", "icns", iconset.path, "-o", icns.path]
try iconutil.run()
iconutil.waitUntilExit()
guard iconutil.terminationStatus == 0 else {
    fatalError("iconutil 生成 AppIcon.icns 失败")
}

print("图标已生成：\(icns.path)")
