import AppKit

let size = NSSize(width: 1024, height: 1024)
let image = NSImage(size: size)
image.lockFocus()

let backgroundPath = NSBezierPath(rect: NSRect(origin: .zero, size: size))
let background = NSGradient(colors: [
    NSColor(red: 0.03, green: 0.08, blue: 0.16, alpha: 1),
    NSColor(red: 0.04, green: 0.35, blue: 0.39, alpha: 1)
])!
background.draw(in: backgroundPath, angle: -45)

func drawGlow(center: NSPoint, radius: CGFloat, color: NSColor) {
    color.withAlphaComponent(0.08).setFill()
    NSBezierPath(ovalIn: NSRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)).fill()
}

drawGlow(center: NSPoint(x: 170, y: 834), radius: 240, color: .cyan)
drawGlow(center: NSPoint(x: 850, y: 174), radius: 310, color: .cyan)

let points = [
    NSPoint(x: 278, y: 401), NSPoint(x: 445, y: 618),
    NSPoint(x: 638, y: 488), NSPoint(x: 763, y: 696),
    NSPoint(x: 548, y: 290)
]
let edges = [(0, 1), (1, 2), (2, 3), (0, 4), (4, 2)]
let bonds = NSBezierPath()
for edge in edges {
    bonds.move(to: points[edge.0])
    bonds.line(to: points[edge.1])
}
bonds.lineWidth = 42
bonds.lineCapStyle = .round
NSColor(red: 0.61, green: 0.96, blue: 0.97, alpha: 1).setStroke()
bonds.stroke()

let radii: [CGFloat] = [105, 118, 132, 91, 84]
for index in points.indices {
    let radius = radii[index]
    let rect = NSRect(
        x: points[index].x - radius,
        y: points[index].y - radius,
        width: radius * 2,
        height: radius * 2
    )
    let path = NSBezierPath(ovalIn: rect)
    let colors: [NSColor]
    if index == 1 || index == 3 || index == 4 {
        colors = [
            NSColor(red: 1, green: 0.94, blue: 0.72, alpha: 1),
            NSColor(red: 0.94, green: 0.38, blue: 0.08, alpha: 1)
        ]
    } else {
        colors = [
            NSColor(red: 0.78, green: 0.99, blue: 1, alpha: 1),
            NSColor(red: 0.02, green: 0.49, blue: 0.59, alpha: 1)
        ]
    }
    NSGradient(colors: colors)!.draw(in: path, angle: -55)
}

for radius in [176.0, 197.0] {
    let ring = NSBezierPath(ovalIn: NSRect(x: 638 - radius, y: 488 - radius, width: radius * 2, height: radius * 2))
    ring.lineWidth = 10
    NSColor(red: 0.83, green: 1, blue: 1, alpha: 0.28).setStroke()
    ring.stroke()
}

image.unlockFocus()
guard
    let tiff = image.tiffRepresentation,
    let bitmap = NSBitmapImageRep(data: tiff),
    let png = bitmap.representation(using: .png, properties: [:])
else { fatalError("Could not create app icon") }

let output = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "AppIcon.png"
try png.write(to: URL(fileURLWithPath: output))
