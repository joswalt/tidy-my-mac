import AppKit

/// The menu bar's template sweep glyph (style guide §6): the icon's sweep, dot and sparkles,
/// drawn in one colour at 18 × 18 pt so macOS tints it. A small dot is added while an alert
/// condition is active (spec 011 §1).
enum MenuBarGlyph {
    static func image(badge: Bool) -> NSImage {
        let size = NSSize(width: 18, height: 18)
        let img = NSImage(size: size, flipped: true) { _ in
            // Glyph space is the icon's 1024 canvas, cropped to the artwork (x 180…820, y 200…840).
            let scale = 18.0 / 640.0
            let t = NSAffineTransform()
            t.scale(by: scale)
            t.translateX(by: -180, yBy: -200)
            t.concat()
            NSColor.black.setFill()

            // Sweep: outer and inner edges of the stroke.
            let sweep = NSBezierPath()
            sweep.move(to: NSPoint(x: 240, y: 758))
            sweep.curve(to: NSPoint(x: 786, y: 306), controlPoint1: NSPoint(x: 422, y: 790), controlPoint2: NSPoint(x: 666, y: 690))
            sweep.line(to: NSPoint(x: 754, y: 294))
            sweep.curve(to: NSPoint(x: 260, y: 642), controlPoint1: NSPoint(x: 640, y: 560), controlPoint2: NSPoint(x: 440, y: 700))
            sweep.close()
            sweep.fill()
            NSBezierPath(ovalIn: NSRect(x: 250 - 59, y: 700 - 59, width: 118, height: 118)).fill()
            NSBezierPath(ovalIn: NSRect(x: 770 - 17, y: 300 - 17, width: 34, height: 34)).fill()

            // Sparkles: four-point stars.
            func sparkle(_ cx: CGFloat, _ cy: CGFloat, _ r: CGFloat) {
                let k = r * 0.14
                let p = NSBezierPath()
                p.move(to: NSPoint(x: cx, y: cy - r))
                p.curve(to: NSPoint(x: cx + r, y: cy), controlPoint1: NSPoint(x: cx + k, y: cy - k), controlPoint2: NSPoint(x: cx + k, y: cy - k))
                p.curve(to: NSPoint(x: cx, y: cy + r), controlPoint1: NSPoint(x: cx + k, y: cy + k), controlPoint2: NSPoint(x: cx + k, y: cy + k))
                p.curve(to: NSPoint(x: cx - r, y: cy), controlPoint1: NSPoint(x: cx - k, y: cy + k), controlPoint2: NSPoint(x: cx - k, y: cy + k))
                p.curve(to: NSPoint(x: cx, y: cy - r), controlPoint1: NSPoint(x: cx - k, y: cy - k), controlPoint2: NSPoint(x: cx - k, y: cy - k))
                p.fill()
            }
            sparkle(392, 388, 124)
            sparkle(706, 640, 64)
            sparkle(560, 262, 40)

            if badge {
                NSBezierPath(ovalIn: NSRect(x: 650, y: 610, width: 170, height: 170)).fill()
            }
            return true
        }
        img.isTemplate = true
        img.accessibilityDescription = badge ? "TidyMyMac, alert" : "TidyMyMac"
        return img
    }
}
