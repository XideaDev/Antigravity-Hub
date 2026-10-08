import AppKit

// Target Dimensions (Retina @2x)
let widthPt: CGFloat = 640
let heightPt: CGFloat = 420
let scale: CGFloat = 2.0
let widthPx = Int(widthPt * scale)
let heightPx = Int(heightPt * scale)

let rootURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let baseTextureURL = rootURL.appendingPathComponent("Resources/dmg/DMG_installer_background_image_2026-10-08T07-31-18.png")
let outputURL = rootURL.appendingPathComponent("Resources/dmg/background.png")

guard let baseImage = NSImage(contentsOf: baseTextureURL) else {
    print("Cannot load base paper texture")
    exit(1)
}

let rep = NSBitmapImageRep(
    bitmapDataPlanes: nil,
    pixelsWide: widthPx,
    pixelsHigh: heightPx,
    bitsPerSample: 8,
    samplesPerPixel: 4,
    hasAlpha: true,
    isPlanar: false,
    colorSpaceName: .deviceRGB,
    bytesPerRow: 0,
    bitsPerPixel: 0
)!
rep.size = NSSize(width: widthPt, height: heightPt)

NSGraphicsContext.saveGraphicsState()
let ctx = NSGraphicsContext(bitmapImageRep: rep)!
NSGraphicsContext.current = ctx

let bounds = NSRect(x: 0, y: 0, width: widthPt, height: heightPt)

// --- A. Draw paper texture base ---
baseImage.draw(in: bounds)

// Clean texture patches from raw paper regions
let cleanTop = NSRect(x: 20, y: 620, width: 490, height: 160)
let cleanBottom = NSRect(x: 20, y: 20, width: 490, height: 160)
baseImage.draw(in: NSRect(x: 20, y: 70, width: 280, height: 280), from: cleanBottom, operation: .sourceOver, fraction: 1.0)
baseImage.draw(in: NSRect(x: 340, y: 70, width: 280, height: 280), from: cleanTop, operation: .sourceOver, fraction: 1.0)
baseImage.draw(in: NSRect(x: 200, y: 140, width: 240, height: 140), from: cleanBottom, operation: .sourceOver, fraction: 1.0)

// Subtle warm paper vignette & border
let innerFrame = bounds.insetBy(dx: 14, dy: 14)
let framePath = NSBezierPath(roundedRect: innerFrame, xRadius: 12, yRadius: 12)
NSColor(white: 0.2, alpha: 0.04).setStroke()
framePath.lineWidth = 1.0
framePath.stroke()

// --- B. Top Header (Brand Typography) ---
let titleFont = NSFont.systemFont(ofSize: 22, weight: .bold)
let titleStyle = NSMutableParagraphStyle()
titleStyle.alignment = .center

let titleAttrs: [NSAttributedString.Key: Any] = [
    .font: titleFont,
    .foregroundColor: NSColor(red: 0.14, green: 0.13, blue: 0.12, alpha: 1.0),
    .paragraphStyle: titleStyle,
    .kern: 0.8
]
let titleStr = NSAttributedString(string: "Antigravity Hub", attributes: titleAttrs)
titleStr.draw(in: NSRect(x: 0, y: heightPt - 68, width: widthPt, height: 30))

let subFont = NSFont.systemFont(ofSize: 12.5, weight: .regular)
let subStyle = NSMutableParagraphStyle()
subStyle.alignment = .center

let subAttrs: [NSAttributedString.Key: Any] = [
    .font: subFont,
    .foregroundColor: NSColor(red: 0.44, green: 0.42, blue: 0.39, alpha: 1.0),
    .paragraphStyle: subStyle,
    .kern: 0.3
]
let subStr = NSAttributedString(string: "Google Antigravity · macOS 原生多分身与沙箱环境管理器", attributes: subAttrs)
subStr.draw(in: NSRect(x: 0, y: heightPt - 92, width: widthPt, height: 20))

// --- C. Pedestals (Card Drop Zones) ---
// Total item height (96px icon + gap + text) is ~116pt.
// We set card size to 148 x 156 pt to comfortably fit BOTH the icon AND the label with 20pt padding!
// Finder icon image center is at y = 180 (from top), Cocoa y = 420 - 180 = 240.
// Center of the whole [Icon + Label] cluster is at Cocoa y = 230.
let leftCenter = NSPoint(x: 160, y: 230)
let rightCenter = NSPoint(x: 480, y: 230)
let cardSize = NSSize(width: 148, height: 156)

func drawCard(at center: NSPoint) {
    let cardRect = NSRect(
        x: center.x - cardSize.width / 2,
        y: center.y - cardSize.height / 2,
        width: cardSize.width,
        height: cardSize.height
    )
    
    // Soft shadow under pedestal
    let shadow = NSShadow()
    shadow.shadowColor = NSColor(white: 0, alpha: 0.05)
    shadow.shadowOffset = NSSize(width: 0, height: -3)
    shadow.shadowBlurRadius = 8
    
    NSGraphicsContext.saveGraphicsState()
    shadow.set()
    
    let path = NSBezierPath(roundedRect: cardRect, xRadius: 22, yRadius: 22)
    NSColor(red: 0.98, green: 0.97, blue: 0.95, alpha: 0.78).setFill()
    path.fill()
    NSGraphicsContext.restoreGraphicsState()
    
    NSColor(red: 0.85, green: 0.82, blue: 0.77, alpha: 0.8).setStroke()
    path.lineWidth = 1.2
    path.stroke()

    let innerRect = cardRect.insetBy(dx: 6, dy: 6)
    let innerPath = NSBezierPath(roundedRect: innerRect, xRadius: 18, yRadius: 18)
    let pattern: [CGFloat] = [4, 4]
    innerPath.setLineDash(pattern, count: 2, phase: 0)
    NSColor(red: 0.88, green: 0.85, blue: 0.81, alpha: 0.55).setStroke()
    innerPath.lineWidth = 1.0
    innerPath.stroke()
}

drawCard(at: leftCenter)
drawCard(at: rightCenter)

// --- D. Directional Arrow & Action Pill in Center ---
// Arrow aligns with the center of the icon images (Cocoa y = 240)
let iconCenterY: CGFloat = 240
let arrowStartX: CGFloat = leftCenter.x + cardSize.width / 2 + 14 // 160 + 74 + 14 = 248
let arrowEndX: CGFloat = rightCenter.x - cardSize.width / 2 - 14   // 480 - 74 - 14 = 392

let pillWidth: CGFloat = 144
let pillHeight: CGFloat = 24
let pillRect = NSRect(x: (widthPt - pillWidth) / 2, y: iconCenterY + 16, width: pillWidth, height: pillHeight)

let pillPath = NSBezierPath(roundedRect: pillRect, xRadius: 12, yRadius: 12)
NSColor(red: 0.93, green: 0.91, blue: 0.87, alpha: 0.92).setFill()
pillPath.fill()
NSColor(red: 0.82, green: 0.79, blue: 0.74, alpha: 0.85).setStroke()
pillPath.lineWidth = 1.0
pillPath.stroke()

let pillStyle = NSMutableParagraphStyle()
pillStyle.alignment = .center
let pillAttrs: [NSAttributedString.Key: Any] = [
    .font: NSFont.systemFont(ofSize: 11, weight: .semibold),
    .foregroundColor: NSColor(red: 0.28, green: 0.26, blue: 0.24, alpha: 1.0),
    .paragraphStyle: pillStyle
]
let pillText = NSAttributedString(string: "拖拽至此处完成安装", attributes: pillAttrs)
pillText.draw(in: NSRect(x: pillRect.minX, y: pillRect.minY + 4, width: pillWidth, height: 16))

let arrowPath = NSBezierPath()
arrowPath.move(to: NSPoint(x: arrowStartX, y: iconCenterY - 4))
arrowPath.line(to: NSPoint(x: arrowEndX, y: iconCenterY - 4))
arrowPath.lineWidth = 2.2
NSColor(red: 0.35, green: 0.33, blue: 0.30, alpha: 0.75).setStroke()
arrowPath.stroke()

let headPath = NSBezierPath()
let headTip = NSPoint(x: arrowEndX + 2, y: iconCenterY - 4)
headPath.move(to: headTip)
headPath.line(to: NSPoint(x: arrowEndX - 10, y: iconCenterY + 3))
headPath.line(to: NSPoint(x: arrowEndX - 10, y: iconCenterY - 11))
headPath.close()
NSColor(red: 0.35, green: 0.33, blue: 0.30, alpha: 0.75).setFill()
headPath.fill()

// --- E. Bottom Footer ---
let footerY: CGFloat = 46
let footerFont = NSFont.monospacedSystemFont(ofSize: 10.5, weight: .regular)

let footerLeftAttrs: [NSAttributedString.Key: Any] = [
    .font: footerFont,
    .foregroundColor: NSColor(red: 0.50, green: 0.47, blue: 0.43, alpha: 1.0)
]
let fLeft = NSAttributedString(string: "⌘ 原生 Swift 5 · 零运行时依赖", attributes: footerLeftAttrs)
fLeft.draw(at: NSPoint(x: 36, y: footerY))

let footerRightStyle = NSMutableParagraphStyle()
footerRightStyle.alignment = .right
let footerRightAttrs: [NSAttributedString.Key: Any] = [
    .font: footerFont,
    .foregroundColor: NSColor(red: 0.50, green: 0.47, blue: 0.43, alpha: 1.0),
    .paragraphStyle: footerRightStyle
]
let fRight = NSAttributedString(string: "物理沙箱 · 独立 Google 账号 · MIT 协议", attributes: footerRightAttrs)
fRight.draw(in: NSRect(x: widthPt - 330, y: footerY, width: 294, height: 16))

NSGraphicsContext.restoreGraphicsState()

guard let data = rep.representation(using: .png, properties: [:]) else {
    print("Failed to encode PNG")
    exit(1)
}

try data.write(to: outputURL)
print("Saved elegant DMG background to", outputURL.path)
