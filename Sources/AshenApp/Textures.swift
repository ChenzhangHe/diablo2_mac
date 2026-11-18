import AppKit
import SpriteKit
import AshenCore

/// Procedurally drawn placeholder art. Everything is generated at launch — no asset files.
enum Textures {
    static let tw = CGFloat(Iso.tileWidth), th = CGFloat(Iso.tileHeight)
    static let wallHeight: CGFloat = 56

    static func image(width: CGFloat, height: CGFloat, scale: CGFloat = 2, _ draw: (CGContext) -> Void) -> SKTexture {
        let w = Int(width * scale), h = Int(height * scale)
        let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpaceCreateDeviceRGB(),
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.scaleBy(x: scale, y: scale)
        draw(ctx)
        let tex = SKTexture(cgImage: ctx.makeImage()!)
        tex.filteringMode = .linear
        return tex
    }

    static func diamond(_ ctx: CGContext, cx: CGFloat, cy: CGFloat) -> CGPath {
        let p = CGMutablePath()
        p.move(to: CGPoint(x: cx, y: cy + th / 2))
        p.addLine(to: CGPoint(x: cx + tw / 2, y: cy))
        p.addLine(to: CGPoint(x: cx, y: cy - th / 2))
        p.addLine(to: CGPoint(x: cx - tw / 2, y: cy))
        p.closeSubpath()
        return p
    }

    static func color(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> CGColor {
        CGColor(red: r, green: g, blue: b, alpha: a)
    }

    /// Stone floor variants with speckle noise.
    static let floors: [SKTexture] = (0..<4).map { v in
        var rng = SeededRNG(seed: UInt64(1000 + v))
        return image(width: tw, height: th) { ctx in
            let path = diamond(ctx, cx: tw / 2, cy: th / 2)
            let base = 0.16 + CGFloat(v) * 0.012
            ctx.addPath(path); ctx.setFillColor(color(base, base * 0.92, base * 0.82)); ctx.fillPath()
            ctx.saveGState(); ctx.addPath(path); ctx.clip()
            for _ in 0..<40 {
                let x = CGFloat(rng.unit()) * tw, y = CGFloat(rng.unit()) * th
                let l = CGFloat(rng.unit()) * 0.08
                ctx.setFillColor(color(base + l - 0.04, base * 0.9 + l - 0.04, base * 0.8 + l - 0.04))
                ctx.fill(CGRect(x: x, y: y, width: 2, height: 1.5))
            }
            ctx.restoreGState()
            ctx.addPath(path); ctx.setStrokeColor(color(0, 0, 0, 0.35)); ctx.setLineWidth(1); ctx.strokePath()
        }
    }

    /// Isometric wall block: footprint diamond at the bottom, raised by `wallHeight`.
    static let wall: SKTexture = image(width: tw, height: th + wallHeight) { ctx in
        let h = wallHeight
        let bottom = th / 2           // footprint center y (CG is y-up here)
        let top = bottom + h
        // Left face
        let left = CGMutablePath()
        left.move(to: CGPoint(x: 0, y: bottom)); left.addLine(to: CGPoint(x: tw / 2, y: bottom - th / 2))
        left.addLine(to: CGPoint(x: tw / 2, y: top - th / 2)); left.addLine(to: CGPoint(x: 0, y: top)); left.closeSubpath()
        ctx.addPath(left); ctx.setFillColor(color(0.22, 0.20, 0.19)); ctx.fillPath()
        // Right face
        let right = CGMutablePath()
        right.move(to: CGPoint(x: tw, y: bottom)); right.addLine(to: CGPoint(x: tw / 2, y: bottom - th / 2))
        right.addLine(to: CGPoint(x: tw / 2, y: top - th / 2)); right.addLine(to: CGPoint(x: tw, y: top)); right.closeSubpath()
        ctx.addPath(right); ctx.setFillColor(color(0.15, 0.135, 0.13)); ctx.fillPath()
        // Brick lines
        ctx.setStrokeColor(color(0, 0, 0, 0.3)); ctx.setLineWidth(1)
        var y: CGFloat = 12
        while y < h {
            ctx.move(to: CGPoint(x: 0, y: bottom + y)); ctx.addLine(to: CGPoint(x: tw / 2, y: bottom - th / 2 + y))
            ctx.addLine(to: CGPoint(x: tw, y: bottom + y)); ctx.strokePath()
            y += 12
        }
        // Top
        ctx.addPath(diamond(ctx, cx: tw / 2, cy: top)); ctx.setFillColor(color(0.30, 0.28, 0.26)); ctx.fillPath()
        ctx.addPath(diamond(ctx, cx: tw / 2, cy: top)); ctx.setStrokeColor(color(0, 0, 0, 0.4)); ctx.strokePath()
    }

    /// Anchor so that the wall footprint center sits at the node position.
    static var wallAnchor: CGPoint { CGPoint(x: 0.5, y: (th / 2) / (th + wallHeight)) }

    /// Glowing exit portal marker.
    static let portal: SKTexture = image(width: tw, height: th) { ctx in
        let colors = [color(0.4, 0.6, 1.0, 0.9), color(0.2, 0.3, 0.9, 0.0)] as CFArray
        let g = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 1])!
        ctx.addPath(diamond(ctx, cx: tw / 2, cy: th / 2)); ctx.clip()
        ctx.drawRadialGradient(g, startCenter: CGPoint(x: tw / 2, y: th / 2), startRadius: 0,
                               endCenter: CGPoint(x: tw / 2, y: th / 2), endRadius: tw / 2, options: [])
    }

    /// Screen-space darkness with a lit circle around the player.
    static func vignette(size: CGSize, radius: CGFloat) -> SKTexture {
        image(width: size.width, height: size.height, scale: 1) { ctx in
            let colors = [color(0, 0, 0, 0), color(0, 0, 0, 0.55), color(0, 0, 0, 0.96)] as CFArray
            let g = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 0.55, 1])!
            let c = CGPoint(x: size.width / 2, y: size.height / 2)
            ctx.drawRadialGradient(g, startCenter: c, startRadius: radius * 0.25, endCenter: c,
                                   endRadius: radius, options: [.drawsAfterEndLocation])
        }
    }
}
