import AppKit
import CoreText
import PacemarkCore

@MainActor
struct MenuBarGaugeRenderer {
    // MenuBarExtra draws through the native status window's full height at 1:1.
    // The visible-frame inset includes the 39pt bar on the built-in notched display.
    static var statusItemHeight: CGFloat {
        let thickness = NSStatusBar.system.thickness
        let visibleInsets = NSScreen.screens.map { screen in
            min(39, max(thickness, screen.frame.maxY - screen.visibleFrame.maxY))
        }
        return visibleInsets.min() ?? thickness
    }

    let palette: MenuBarPalette
    let tuning: MenuBarMeterTuning
    var heightLimit = Self.statusItemHeight

    // Optical centers within the existing 18pt image, in bottom-up coordinates.
    static let meterGap: CGFloat = 6
    private var ink: NSColor { palette.ink.menuBarColor }
    private var track: NSColor { ink.withAlphaComponent(ink.alphaComponent * 0.15) }

    /// The same measured width advances the cursor and sizes the image.
    private struct Piece {
        let width: CGFloat
        let draw: @MainActor (CGFloat) -> Void

        static let empty = Piece(width: 0) { _ in }
    }

    func image(meters: [MenuBarMeter], highlighting key: AccountKey? = nil) -> NSImage {
        let layout = uniformRingLayout(meters: meters)
        let height = layout.geometry.height
        let content: Piece
        if meters.isEmpty {
            let mark = AppIconGlyph.image ?? VesselGlyph.image(palette: palette)
            let size = min(layout.geometry.diameter, 20)
            content = Piece(width: size) { x in
                let rect = NSRect(x: x, y: (height - size) / 2, width: size, height: size)
                mark.draw(in: rect)
                ink.setFill()
                rect.fill(using: .sourceAtop)
            }
        } else {
            content = row(meters.map { meter in
                let cell = gauge(meter, layout: layout)
                guard let key, key == meter.sourceAccountKey else { return cell }
                return Piece(width: cell.width) { x in
                    cell.draw(x)
                    // Outline only. An underlay lightens the dark plate beneath the red arc.
                    ink.withAlphaComponent(0.30).setStroke()
                    let outline = NSBezierPath(roundedRect: NSRect(x: x - 2, y: 0.5, width: cell.width + 4, height: height - 1),
                                               xRadius: 5, yRadius: 5)
                    outline.lineWidth = 1
                    outline.stroke()
                }
            }, gap: Self.meterGap)
        }
        let sideInset = meters.isEmpty ? 0 : Self.meterGap / 2
        let image = NSImage(size: NSSize(width: ceil(content.width + 2 * sideInset), height: height), flipped: false) { bounds in
            content.draw(bounds.minX + sideInset)
            return true
        }
        image.isTemplate = false
        return image
    }

    private func gauge(_ meter: MenuBarMeter, layout: UniformRingLayout) -> Piece {
        let severity = meter.pace?.tier?.severity ?? meter.summary.severity
        let color = meter.isLiveReading ? palette.liquid(for: severity).menuBarColor
            : PacemarkColorValues.staleNeutralFill(dark: palette.isDarkMenuBar).menuBarColor
        let kind = meter.summary.providerID.map(MenuBarGlyphKind.providerMark) ?? meter.glyph
        let fill = min(1, max(0, meter.fill ?? 0))
        let number = tuning.showNumber && !meter.summary.isNeutral ? meter.summary.text : nil
        let dotted = meter.awaitingFirstReading || meter.summary.needsAttention
        let isCritical = meter.isLiveReading && !dotted && severity == .critical
        let numeralInk = isCritical ? palette.severityInk(for: severity).menuBarColor : ink
        return gaugeArtwork(meter, layout: layout, kind: kind, fill: fill, color: color,
                            number: number, numeralInk: numeralInk, dotted: dotted)
    }

    private func gaugeArtwork(
        _ meter: MenuBarMeter, layout: UniformRingLayout, kind: MenuBarGlyphKind,
        fill: Double, color: NSColor, number: String?, numeralInk: NSColor, dotted: Bool
    ) -> Piece {
        let geometry = layout.geometry
        let innerDiameter = 2 * geometry.innerRadius
        let logo = MenuBarGlyph.ringLogoSize(
            of: kind, preferredSize: geometry.logoBox, innerRadius: geometry.innerRadius,
            minimumSize: 0.60 * innerDiameter, usesRadialInkBounds: true)
        let tickAngle = tuning.showPaceTick ? meter.expectedFill.map { geometry.angle(at: $0) } : nil
        let label: Piece
        if layout.fontSize > 0, let badge = meter.badge, !badge.isEmpty {
            label = text(badge, size: layout.fontSize, weight: tuning.labelWeight.fontWeight,
                               color: ink, y: geometry.labelCenter, useInkWidth: true)
        } else {
            label = .empty
        }
        let gauge = withKnockouts(overlay([
            Piece(width: max(geometry.artworkWidth, ceil(label.width) + 1)) { _ in },
            ring(fill: fill, color: color, layout: geometry, dotted: dotted),
            tuning.showPaceTick ? paceTick(angle: tickAngle, layout: geometry) : .empty,
            label
        ]))
        let artwork = overlay([gauge, drawMark(kind, size: logo, color: ink.withAlphaComponent(meter.isLiveReading && !dotted ? 1 : 0.55), y: geometry.center)])
        let numeral = text(number, size: geometry.besideFontSize, color: numeralInk, y: geometry.center, leading: true)
        guard numeral.width > 0 else { return artwork }
        let numberX = (artwork.width + geometry.artworkWidth) / 2 + 3
        return Piece(width: max(artwork.width, numberX + numeral.width)) { x in
            artwork.draw(x)
            numeral.draw(x + numberX)
        }
    }

    /// Draw at the diagram's native point size, using the status item's paths and mark.
    func drawExample(meter: MenuBarMeter, geometry: MenuBarRingLayout, context: CGContext) {
        let layout = UniformRingLayout(geometry: geometry, fontSize: 0)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
        defer { NSGraphicsContext.restoreGraphicsState() }
        gauge(meter, layout: layout).draw(0)
    }

    private func withKnockouts(_ piece: Piece) -> Piece {
        Piece(width: piece.width) { x in
            guard let context = NSGraphicsContext.current?.cgContext else { return }
            // Clear only this meter's artwork so the actual menu bar or review plate shows through.
            context.saveGState()
            context.beginTransparencyLayer(auxiliaryInfo: nil)
            piece.draw(x)
            context.endTransparencyLayer()
            context.restoreGState()
        }
    }

    private func row(_ items: [Piece], gap: CGFloat) -> Piece {
        let items = items.filter { $0.width > 0 }
        let width = items.reduce(0) { $0 + $1.width } + CGFloat(max(0, items.count - 1)) * gap
        return Piece(width: width) { x in
            var x = x
            for item in items {
                item.draw(x)
                x += item.width + gap
            }
        }
    }

    private func overlay(_ items: [Piece], centered: Bool = true) -> Piece {
        let width = items.map(\.width).max() ?? 0
        return Piece(width: width) { x in
            for item in items {
                item.draw(centered ? x + (width - item.width) / 2 : x)
            }
        }
    }

    private func text(_ value: String?, size: CGFloat, weight: NSFont.Weight = .semibold,
                      color: NSColor, y: CGFloat, leading: Bool = false,
                      useInkWidth: Bool = false) -> Piece {
        guard let value, !value.isEmpty else { return .empty }
        let line = textLine(value, size: size, weight: weight, color: color)
        // Measure actual ink so both lines fit even when their font line boxes overlap.
        let bounds = CTLineGetBoundsWithOptions(line, .useGlyphPathBounds)
        let width = ceil(useInkWidth ? bounds.width : max(CGFloat(CTLineGetTypographicBounds(line, nil, nil, nil)), bounds.width))
        return Piece(width: width) { x in
            guard let context = NSGraphicsContext.current?.cgContext else { return }
            context.saveGState()
            context.textMatrix = .identity
            context.translateBy(x: x + (leading ? 0 : width / 2), y: 0)
            let origin = CGPoint(x: -(leading ? bounds.minX : bounds.midX), y: y - bounds.midY)
            context.textPosition = origin
            CTLineDraw(line, context)
            context.restoreGState()
        }
    }

    private func textLine(_ value: String, size: CGFloat, weight: NSFont.Weight, color: NSColor) -> CTLine {
        let string = NSAttributedString(string: value, attributes: [
            .font: badgeFont(size: size, weight: weight), .foregroundColor: color
        ])
        return CTLineCreateWithAttributedString(string)
    }

    func badgeFont(size: CGFloat, weight: NSFont.Weight) -> NSFont {
        NSFont.monospacedDigitSystemFont(ofSize: size, weight: weight)
    }

    struct UniformRingLayout {
        let geometry: MenuBarRingLayout
        let fontSize: CGFloat
    }

    func supports(_ size: MenuBarMeterTuning.IconSize) -> Bool {
        let diameter = MenuBarRingLayout.baseDiameter * size.factor
        return size == .base || MenuBarRingLayout.minimumHeight(
            diameter: diameter, labelHeight: diameter * tuning.textSize.capHeightRatio * 1.06,
            ringWidth: tuning.ringLineWidth, showsTick: tuning.showPaceTick, logoScale: tuning.markScale
        ) <= heightLimit
    }

    var effectiveIconSize: MenuBarMeterTuning.IconSize {
        MenuBarMeterTuning.IconSize.allCases.last { $0.rawValue <= tuning.iconSize.rawValue && supports($0) } ?? .base
    }

    func uniformRingLayout(meters: [MenuBarMeter]) -> UniformRingLayout {
        let diameter = MenuBarRingLayout.baseDiameter * effectiveIconSize.factor
        let capHeight = diameter * tuning.textSize.capHeightRatio
        let weight = tuning.labelWeight.fontWeight
        let fontSize = 10 * capHeight / badgeFont(size: 10, weight: weight).capHeight
        let badges = meters.compactMap(\.badge).filter { !$0.isEmpty }
        let bounds = badges.map { badge in
            CTLineGetBoundsWithOptions(textLine(badge, size: fontSize, weight: weight, color: ink),
                                       .useGlyphPathBounds)
        }
        let labelHeight = max(capHeight, bounds.map(\.height).max() ?? 0)
        // Horizontal padding belongs to each meter.
        let geometry = MenuBarRingLayout(
            requestedDiameter: diameter, heightLimit: heightLimit, ringWidth: tuning.ringLineWidth,
            showsTick: tuning.showPaceTick, labelWidth: 0,
            labelHeight: labelHeight, logoScale: tuning.markScale, hasVisibleLabels: !badges.isEmpty)
        return UniformRingLayout(geometry: geometry, fontSize: fontSize * geometry.labelScale)
    }

    private func drawMark(_ kind: MenuBarGlyphKind, size: MenuBarGlyphSize, color: NSColor, y: CGFloat) -> Piece {
        let width = size.width
        let height = size.height
        guard width > 0, height > 0 else { return .empty }
        let image: NSImage?
        if case .providerMark(let provider) = kind {
            image = BrandIconImage.image(for: provider, scheme: .light)
        } else {
            image = nil
        }
        return Piece(width: width) { x in
            let rect = NSRect(x: x, y: y - height / 2, width: width, height: height)
            guard let image, let context = NSGraphicsContext.current?.cgContext else {
                color.setFill()
                NSBezierPath(roundedRect: rect, xRadius: width / 2, yRadius: width / 2).fill()
                return
            }
            context.saveGState()
            if let mask = image.cgImage(forProposedRect: nil, context: nil, hints: nil) {
                context.clip(to: rect, mask: mask)
                context.setFillColor(color.cgColor)
                context.fill(rect)
            }
            context.restoreGState()
        }
    }

    private func ring(
        fill: Double, color: NSColor, layout: MenuBarRingLayout, dotted: Bool
    ) -> Piece {
        let diameter = layout.diameter
        let radius = (diameter - layout.stroke) / 2
        return Piece(width: diameter) { x in
            let center = NSPoint(x: x + diameter / 2, y: layout.center)
            func arc(to fraction: Double) -> NSBezierPath {
                let path = NSBezierPath()
                path.appendArc(withCenter: center, radius: radius,
                               startAngle: 90 - layout.startAngle * 180 / .pi,
                               endAngle: 90 - layout.angle(at: fraction) * 180 / .pi, clockwise: true)
                path.lineCapStyle = .round
                path.lineWidth = layout.stroke
                return path
            }

            let outline = arc(to: 1)
            if dotted {
                // A small dash and a round cap produce dots at the size of the gauge stroke.
                let dash: [CGFloat] = [0.01, 2.6 * layout.stroke]
                outline.setLineDash(dash, count: dash.count, phase: 0)
                ink.withAlphaComponent(0.40).setStroke()
            } else {
                track.setStroke()
            }
            outline.stroke()
            if fill > 0 && !dotted {
                color.setStroke()
                arc(to: fill).stroke()
            }
        }
    }

    private func paceTick(angle: Double?, layout: MenuBarRingLayout) -> Piece {
        let width = layout.diameter + 2 * layout.tickOverhang
        let y = layout.center
        return Piece(width: width) { x in
            guard let angle, let context = NSGraphicsContext.current?.cgContext else { return }
            let tickWidth = min(1.25 * layout.scale, layout.stroke + 2 * layout.tickOverhang)
            let strokeCenter = (layout.diameter - layout.stroke) / 2
            // The round caps add one tick width to the path's visible length.
            let halfSpan = (layout.stroke + 2 * layout.tickOverhang - tickWidth) / 2
            let dx = sin(angle)
            let dy = cos(angle)
            let path = CGMutablePath()
            path.move(to: CGPoint(x: x + width / 2 + dx * (strokeCenter - halfSpan),
                                  y: y + dy * (strokeCenter - halfSpan)))
            path.addLine(to: CGPoint(x: x + width / 2 + dx * (strokeCenter + halfSpan),
                                     y: y + dy * (strokeCenter + halfSpan)))
            context.saveGState()
            context.setLineCap(.round)
            context.setBlendMode(.destinationOut)
            context.setStrokeColor(NSColor.black.cgColor)
            context.setLineWidth(tickWidth + 1.5 * layout.scale)
            context.addPath(path)
            context.strokePath()
            context.setBlendMode(.normal)
            context.setStrokeColor(ink.cgColor)
            context.setLineWidth(tickWidth)
            context.addPath(path)
            context.strokePath()
            context.restoreGState()
        }
    }

}

extension PacemarkRGBColor {
    var menuBarColor: NSColor {
        NSColor(srgbRed: red, green: green, blue: blue, alpha: 1)
    }
}

extension PacemarkTint {
    var menuBarColor: NSColor {
        NSColor(srgbRed: color.red, green: color.green, blue: color.blue, alpha: opacity)
    }
}
