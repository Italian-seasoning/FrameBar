import AppKit
import CoreText

/// Native status-button content with an explicit text position. NSButtonCell
/// recenters multiline attributed titles, which can cancel baseline offsets.
@MainActor final class MenuBarReadoutView: NSView {
    private let icon = NSImageView()
    private struct Slot {
        var label: String
        var value: String
        var width: CGFloat
        var reference: String
    }
    private var rows: [[Slot]] = []
    private var rowInkBounds: [CGRect] = []
    private(set) var columnWidths: [CGFloat] = []
    private let columnGap: CGFloat = 5
    private var showIcon = true
    private var font = NSFont.monospacedDigitSystemFont(ofSize: 10, weight: .medium)
    private var textWidth: CGFloat = 0
    private(set) var requiredWidth: CGFloat = 24
    override var isFlipped: Bool { true }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        let image = NSImage(systemSymbolName: "waveform.path.ecg", accessibilityDescription: nil)
        image?.isTemplate = true
        icon.image = image
        icon.contentTintColor = .labelColor
        icon.imageScaling = .scaleProportionallyDown
        addSubview(icon)
        setAccessibilityElement(false)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    func configure(metrics: Metrics, selected: [MenuBarMetric], layout: MenuBarLayout, labels: Bool, showIcon: Bool) {
        self.showIcon = showIcon
        let stacked = layout == .stacked && selected.count > 1
        font = NSFont.monospacedDigitSystemFont(ofSize: stacked ? 8 : 10, weight: .medium)
        let slots = selected.map { metric -> Slot in
            let label = labels && metric != .gameFPS ? (metric == .refresh ? "Hz " : metric.rawValue + " ") : ""
            let value = labels && metric == .refresh ? (metrics.refreshAdaptive ? "—" : Format.number(metrics.refreshHz)) : metric.reading(metrics, labels: false)
            let reserved = labels && metric == .refresh ? "9999" : metric.reservedReading
            let width = ceil(((label + reserved) as NSString).size(withAttributes: [.font: font]).width)
            return Slot(label: label, value: value, width: width, reference: label + reserved)
        }
        if slots.isEmpty { rows = [] }
        else if stacked {
            let split = (slots.count + 1) / 2
            rows = [Array(slots.prefix(split)), Array(slots.dropFirst(split))]
        } else { rows = [slots] }
        let columns = rows.map(\.count).max() ?? 0
        columnWidths = (0..<columns).map { column in
            rows.compactMap { $0.indices.contains(column) ? $0[column].width : nil }.max() ?? 0
        }
        for row in rows.indices {
            for column in rows[row].indices { rows[row][column].width = columnWidths[column] }
        }
        // Use stable representative glyphs, so changing digits cannot move the readout.
        rowInkBounds = rows.map { row in
            row.reduce(CGRect.null) { bounds, slot in
                let line = CTLineCreateWithAttributedString(NSAttributedString(string: slot.reference, attributes: [.font: font]))
                return bounds.union(CTLineGetBoundsWithOptions(line, .useGlyphPathBounds))
            }
        }
        textWidth = columnWidths.reduce(0, +) + CGFloat(max(0, columns - 1)) * columnGap
        requiredWidth = 8 + (showIcon ? 16 : 0) + (showIcon && !rows.isEmpty ? 5 : 0) + textWidth
        icon.isHidden = !showIcon
        needsLayout = true
        needsDisplay = true
    }

    override func layout() {
        super.layout()
        icon.frame = NSRect(x: 4, y: (bounds.height - 16) / 2, width: 16, height: 16)
    }

    override func draw(_ dirtyRect: NSRect) {
        guard !rows.isEmpty, let context = NSGraphicsContext.current?.cgContext else { return }
        let stacked = rows.count > 1
        let lineHeight: CGFloat = stacked ? 9 : ceil(font.ascender - font.descender)
        let x: CGFloat = 4 + (showIcon ? 21 : 0)
        let inkBottom = rowInkBounds.enumerated().map { $0.element.minY - CGFloat($0.offset) * lineHeight }.min() ?? 0
        let inkTop = rowInkBounds.enumerated().map { $0.element.maxY - CGFloat($0.offset) * lineHeight }.max() ?? 0
        let scale = window?.backingScaleFactor ?? 2
        // The waveform symbol's visible strokes sit below the center of its image box.
        let firstBaseline = ((bounds.midY - 0.5 - (inkBottom + inkTop) / 2) * scale).rounded() / scale
        let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: NSColor.labelColor]
        context.saveGState()
        defer { context.restoreGState() }
        context.translateBy(x: 0, y: bounds.height)
        context.scaleBy(x: 1, y: -1)
        context.textMatrix = .identity
        for (index, row) in rows.enumerated() {
            var slotX = x
            let y = firstBaseline - CGFloat(index) * lineHeight
            for slot in row {
                context.textPosition = CGPoint(x: slotX, y: y)
                CTLineDraw(CTLineCreateWithAttributedString(NSAttributedString(string: slot.label, attributes: attributes)), context)
                let width = (slot.value as NSString).size(withAttributes: attributes).width
                context.textPosition = CGPoint(x: slotX + slot.width - width, y: y)
                CTLineDraw(CTLineCreateWithAttributedString(NSAttributedString(string: slot.value, attributes: attributes)), context)
                slotX += slot.width + columnGap
            }
        }
    }
}
