import AppKit
import SpriteKit
import AshenCore

/// Per-theme procedural tiles: floors, walls, trees, rocks, water, paths. Cached on first use.
enum ThemeTextures {
    struct Palette {
        var floor: (CGFloat, CGFloat, CGFloat)
        var wallLeft: (CGFloat, CGFloat, CGFloat)
        var wallRight: (CGFloat, CGFloat, CGFloat)
        var wallTop: (CGFloat, CGFloat, CGFloat)
        var water: (CGFloat, CGFloat, CGFloat)
        var foliage: (CGFloat, CGFloat, CGFloat)
        var brick: Bool
    }

    static func palette(_ t: TileTheme) -> Palette {
        switch t {
        case .village: Palette(floor: (0.22, 0.19, 0.13), wallLeft: (0.30, 0.20, 0.12), wallRight: (0.22, 0.14, 0.08),
                               wallTop: (0.36, 0.25, 0.15), water: (0.10, 0.18, 0.25), foliage: (0.12, 0.22, 0.10), brick: false)
        case .swamp: Palette(floor: (0.15, 0.17, 0.11), wallLeft: (0.2, 0.2, 0.17), wallRight: (0.14, 0.14, 0.12),
                             wallTop: (0.26, 0.26, 0.22), water: (0.08, 0.14, 0.12), foliage: (0.14, 0.2, 0.09), brick: false)
        case .forest: Palette(floor: (0.12, 0.16, 0.09), wallLeft: (0.2, 0.19, 0.16), wallRight: (0.14, 0.13, 0.11),
                              wallTop: (0.26, 0.25, 0.21), water: (0.07, 0.12, 0.18), foliage: (0.08, 0.2, 0.08), brick: false)
        case .cave: Palette(floor: (0.19, 0.15, 0.11), wallLeft: (0.27, 0.2, 0.14), wallRight: (0.19, 0.14, 0.1),
                            wallTop: (0.32, 0.25, 0.18), water: (0.08, 0.13, 0.18), foliage: (0.15, 0.18, 0.1), brick: false)
        case .abbey: Palette(floor: (0.19, 0.2, 0.22), wallLeft: (0.26, 0.27, 0.29), wallRight: (0.18, 0.19, 0.21),
                             wallTop: (0.33, 0.34, 0.36), water: (0.08, 0.15, 0.2), foliage: (0.1, 0.17, 0.1), brick: true)
        case .crypt: Palette(floor: (0.14, 0.13, 0.14), wallLeft: (0.22, 0.2, 0.19), wallRight: (0.15, 0.135, 0.13),
                             wallTop: (0.30, 0.28, 0.26), water: (0.06, 0.1, 0.14), foliage: (0.1, 0.12, 0.08), brick: true)
        }
    }

    private static var floorCache: [String: [SKTexture]] = [:]
    private static var wallCache: [TileTheme: SKTexture] = [:]
    private static var waterCache: [TileTheme: SKTexture] = [:]
    private static var treeCache: [TileTheme: [SKTexture]] = [:]
    private static var rockCache: [TileTheme: SKTexture] = [:]

    static let tw = Textures.tw, th = Textures.th
    static let treeHeight: CGFloat = 78
    static let rockHeight: CGFloat = 26

    static func c(_ t: (CGFloat, CGFloat, CGFloat), _ k: CGFloat = 1, _ a: CGFloat = 1) -> CGColor {
        CGColor(red: t.0 * k, green: t.1 * k, blue: t.2 * k, alpha: a)
    }

    private static func speckledDiamond(_ base: (CGFloat, CGFloat, CGFloat), seed: UInt64, specks: Int, stroke: Bool = true) -> SKTexture {
        var rng = SeededRNG(seed: seed)
        return Textures.image(width: tw, height: th) { ctx in
            let path = Textures.diamond(ctx, cx: tw / 2, cy: th / 2)
            ctx.addPath(path); ctx.setFillColor(c(base)); ctx.fillPath()
            ctx.saveGState(); ctx.addPath(path); ctx.clip()
            for _ in 0..<specks {
                let x = CGFloat(rng.unit()) * tw, y = CGFloat(rng.unit()) * th
                let k = 0.75 + CGFloat(rng.unit()) * 0.55
                ctx.setFillColor(c(base, k))
                ctx.fill(CGRect(x: x, y: y, width: 2 + CGFloat(rng.unit()) * 2, height: 1.5))
            }
            ctx.restoreGState()
            if stroke { ctx.addPath(path); ctx.setStrokeColor(Textures.color(0, 0, 0, 0.25)); ctx.setLineWidth(1); ctx.strokePath() }
        }
    }

    static func floors(_ t: TileTheme) -> [SKTexture] {
        let key = "f\(t.rawValue)"
        if let f = floorCache[key] { return f }
        let p = palette(t)
        let out = (0..<4).map { v in
            speckledDiamond((p.floor.0 * (1 + CGFloat(v) * 0.05), p.floor.1 * (1 + CGFloat(v) * 0.04), p.floor.2),
                            seed: UInt64(2000 + v), specks: 50, stroke: p.brick)
        }
        floorCache[key] = out
        return out
    }

    static func path(_ t: TileTheme) -> [SKTexture] {
        let key = "p\(t.rawValue)"
        if let f = floorCache[key] { return f }
        let out = (0..<2).map { speckledDiamond((0.27, 0.22, 0.15), seed: UInt64(3000 + $0), specks: 60, stroke: false) }
        floorCache[key] = out
        return out
    }

    static func water(_ t: TileTheme) -> SKTexture {
        if let w = waterCache[t] { return w }
        let p = palette(t)
        let tex = Textures.image(width: tw, height: th) { ctx in
            let path = Textures.diamond(ctx, cx: tw / 2, cy: th / 2)
            ctx.addPath(path); ctx.setFillColor(c(p.water)); ctx.fillPath()
            ctx.saveGState(); ctx.addPath(path); ctx.clip()
            ctx.setStrokeColor(c(p.water, 1.8, 0.6)); ctx.setLineWidth(1)
            for i in 0..<3 {
                let y = th * (0.3 + 0.2 * CGFloat(i))
                ctx.move(to: CGPoint(x: tw * 0.25, y: y)); ctx.addLine(to: CGPoint(x: tw * 0.45, y: y + 1)); ctx.strokePath()
            }
            ctx.restoreGState()
        }
        waterCache[t] = tex
        return tex
    }

    /// Block wall in theme colors (same footprint/anchor as `Textures.wall`).
    static func wall(_ t: TileTheme) -> SKTexture {
        if let w = wallCache[t] { return w }
        let p = palette(t)
        let h = Textures.wallHeight
        let tex = Textures.image(width: tw, height: th + h) { ctx in
            let bottom = th / 2, top = bottom + h
            let left = CGMutablePath()
            left.move(to: CGPoint(x: 0, y: bottom)); left.addLine(to: CGPoint(x: tw / 2, y: bottom - th / 2))
            left.addLine(to: CGPoint(x: tw / 2, y: top - th / 2)); left.addLine(to: CGPoint(x: 0, y: top)); left.closeSubpath()
            ctx.addPath(left); ctx.setFillColor(c(p.wallLeft)); ctx.fillPath()
            let right = CGMutablePath()
            right.move(to: CGPoint(x: tw, y: bottom)); right.addLine(to: CGPoint(x: tw / 2, y: bottom - th / 2))
            right.addLine(to: CGPoint(x: tw / 2, y: top - th / 2)); right.addLine(to: CGPoint(x: tw, y: top)); right.closeSubpath()
            ctx.addPath(right); ctx.setFillColor(c(p.wallRight)); ctx.fillPath()
            ctx.setStrokeColor(Textures.color(0, 0, 0, 0.3)); ctx.setLineWidth(1)
            if p.brick {
                var y: CGFloat = 12
                while y < h {
                    ctx.move(to: CGPoint(x: 0, y: bottom + y)); ctx.addLine(to: CGPoint(x: tw / 2, y: bottom - th / 2 + y))
                    ctx.addLine(to: CGPoint(x: tw, y: bottom + y)); ctx.strokePath()
                    y += 12
                }
            } else if t == .village {
                // Vertical planks.
                for i in 1..<4 {
                    let x = tw / 2 * CGFloat(i) / 4
                    ctx.move(to: CGPoint(x: x, y: bottom - th / 2 * CGFloat(i) / 4)); ctx.addLine(to: CGPoint(x: x, y: top - th / 2 * CGFloat(i) / 4)); ctx.strokePath()
                    let xr = tw - x
                    ctx.move(to: CGPoint(x: xr, y: bottom - th / 2 * CGFloat(i) / 4)); ctx.addLine(to: CGPoint(x: xr, y: top - th / 2 * CGFloat(i) / 4)); ctx.strokePath()
                }
            } else {
                // Rough rock cracks.
                var rng = SeededRNG(seed: 99)
                for _ in 0..<6 {
                    let x = CGFloat(rng.unit()) * tw, y = bottom + CGFloat(rng.unit()) * h * 0.8
                    ctx.move(to: CGPoint(x: x, y: y)); ctx.addLine(to: CGPoint(x: x + 6, y: y - 5)); ctx.strokePath()
                }
            }
            ctx.addPath(Textures.diamond(ctx, cx: tw / 2, cy: top)); ctx.setFillColor(c(p.wallTop)); ctx.fillPath()
            ctx.addPath(Textures.diamond(ctx, cx: tw / 2, cy: top)); ctx.setStrokeColor(Textures.color(0, 0, 0, 0.4)); ctx.strokePath()
        }
        wallCache[t] = tex
        return tex
    }

    /// Conifer-ish tree: trunk + stacked canopy. Anchor at trunk base.
    static func trees(_ t: TileTheme) -> [SKTexture] {
        if let tr = treeCache[t] { return tr }
        let p = palette(t)
        let out: [SKTexture] = (0..<3).map { v in
            Textures.image(width: tw, height: treeHeight) { ctx in
                let cx = tw / 2
                ctx.setFillColor(Textures.color(0.18, 0.12, 0.07))
                ctx.fill(CGRect(x: cx - 3, y: 6, width: 6, height: 20))
                for i in 0..<3 {
                    let w = 44 - CGFloat(i) * 10 + CGFloat(v) * 3
                    let y0 = 18 + CGFloat(i) * 16
                    let tri = CGMutablePath()
                    tri.move(to: CGPoint(x: cx - w / 2, y: y0)); tri.addLine(to: CGPoint(x: cx + w / 2, y: y0))
                    tri.addLine(to: CGPoint(x: cx, y: y0 + 30)); tri.closeSubpath()
                    ctx.addPath(tri); ctx.setFillColor(c(p.foliage, 1 + CGFloat(i) * 0.15)); ctx.fillPath()
                    ctx.addPath(tri); ctx.setStrokeColor(Textures.color(0, 0, 0, 0.35)); ctx.strokePath()
                }
            }
        }
        treeCache[t] = out
        return out
    }

    static var treeAnchor: CGPoint { CGPoint(x: 0.5, y: 8 / treeHeight) }

    static func rock(_ t: TileTheme) -> SKTexture {
        if let r = rockCache[t] { return r }
        let p = palette(t)
        let tex = Textures.image(width: tw, height: th + rockHeight) { ctx in
            let base = CGRect(x: tw * 0.18, y: th * 0.2, width: tw * 0.64, height: th * 0.5 + rockHeight)
            ctx.addEllipse(in: base); ctx.setFillColor(c(p.wallLeft, 1.1)); ctx.fillPath()
            ctx.addEllipse(in: base.insetBy(dx: 8, dy: 8).offsetBy(dx: 4, dy: 4)); ctx.setFillColor(c(p.wallTop, 1.1)); ctx.fillPath()
            ctx.addEllipse(in: base); ctx.setStrokeColor(Textures.color(0, 0, 0, 0.45)); ctx.strokePath()
        }
        rockCache[t] = tex
        return tex
    }

    static var rockAnchor: CGPoint { CGPoint(x: 0.5, y: (th / 2) / (th + rockHeight)) }
}
