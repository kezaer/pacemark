import AppKit
import ApplicationServices

private struct Element {
    let role: String
    let id: String
    let title: String
    let frame: CGRect
    var isCard: Bool { id == "pds.card" || id.hasPrefix("popover.card.") }
    var description: String { "\(role) \(title) \(frame)" }
    let truncated: Bool
}

private func element(_ node: AXUIElement) -> Element? {
    var point = CGPoint.zero, size = CGSize.zero
    guard let position = value(node, kAXPositionAttribute), CFGetTypeID(position) == AXValueGetTypeID(),
          let dimensions = value(node, kAXSizeAttribute), CFGetTypeID(dimensions) == AXValueGetTypeID(),
          AXValueGetValue(position as! AXValue, .cgPoint, &point),
          AXValueGetValue(dimensions as! AXValue, .cgSize, &size), size.width > 0, size.height > 0 else { return nil }
    let role = string(node, kAXRoleAttribute)
    let text = role == "AXStaticText" ? string(node, kAXValueAttribute) : string(node, kAXTitleAttribute)
    let title = text.isEmpty ? string(node, kAXDescriptionAttribute) : text
    var visible = CFRange()
    let range = value(node, kAXVisibleCharacterRangeAttribute)
    let truncated = !title.isEmpty && title == (value(node, kAXValueAttribute) as? String) && range.map { CFGetTypeID($0) == AXValueGetTypeID() &&
        AXValueGetValue($0 as! AXValue, .cfRange, &visible) && visible.length < title.utf16.count } ?? false
    return Element(role: role, id: string(node, kAXIdentifierAttribute), title: title,
                   frame: CGRect(origin: point, size: size), truncated: truncated)
}

private func fixturePID(_ root: AXUIElement) throws -> pid_t {
    var pid: pid_t = 0
    guard AXUIElementGetPid(root, &pid) == .success else { throw Failure("Cannot identify fixture window") }
    return pid
}

func checkLayout(_ root: AXUIElement, statusItem: Bool) throws {
    var violations: [String] = []
    let windowActive = NSRunningApplication(processIdentifier: try fixturePID(root))?.isActive == true
    if windowActive {
        violations.append("Fixture is active; QA captures require an inactive window")
    }
    var contrastText: [[Double]] = []
    var guidePairs = 0
    var cards = 0
    let controls = ["AXLink", "AXHeading", "AXStaticText", "AXButton", "AXPopUpButton", "AXCheckBox", "AXSwitch", "AXRadioButton", "AXTextField", "AXDateTimeArea"]
    func inspect(_ node: AXUIElement, _ card: Element) {
        cards += 1
        var guides: [Element] = [], items: [Element] = [], leaves: [Element] = [], dividers: [Element] = [], rows: [(Element, [Element])] = []
        var disabledText: [Element] = []
        var formFrames: [CGRect] = []
        func collect(_ parent: AXUIElement, row: Int?, disabled: Bool) {
            for child in value(parent, kAXChildrenAttribute) as? [AXUIElement] ?? [] {
                let isDisabled = disabled || (value(child, kAXEnabledAttribute) as? NSNumber)?.boolValue == false
                let item = element(child)
                var owner = row
                if let item {
                    if item.id == "pds.form.bounds" { formFrames.append(item.frame) }
                    if item.id.hasPrefix("pds.heading.") || item.id.hasPrefix("pds.cell.") { guides.append(item); continue }
                    if item.id == "pds.item" { items.append(item); continue }
                    if item.isCard { continue }
                    if item.id == "pds.divider" { dividers.append(item); continue }
                    if item.id == "pds.row" { owner = rows.count; rows.append((item, [])) }
                    // Measure the native segmented control’s outer frame for row padding.
                    // Its individual buttons have asymmetric bezel insets.
                    if item.role == "AXRadioGroup", let owner { rows[owner].1.append(item) }
                    if controls.contains(item.role) {
                        leaves.append(item)
                        if isDisabled && item.role == "AXStaticText" && !item.title.isEmpty { disabledText.append(item) }
                        if let owner { rows[owner].1.append(item) }
                        continue
                    }
                }
                collect(child, row: owner, disabled: isDisabled)
            }
        }
        collect(node, row: nil, disabled: false)
        // Offscreen AX descendants can be available before SwiftUI lays them out.
        // Only the content currently painted inside the captured scroll viewport is evidence.
        var viewport = element(root)?.frame ?? card.frame
        var ancestor = node
        while let parent = value(ancestor, kAXParentAttribute), CFGetTypeID(parent) == AXUIElementGetTypeID() {
            ancestor = parent as! AXUIElement
            if string(ancestor, kAXRoleAttribute) == "AXScrollArea", let scroll = element(ancestor) {
                viewport = viewport.intersection(scroll.frame)
            }
            if CFEqual(ancestor, root) { break }
        }
        let layoutItems = (dividers + leaves + items).sorted { $0.frame.midY < $1.frame.midY }
        leaves = leaves.filter { viewport.intersects($0.frame) }
        dividers = dividers.filter { viewport.intersects($0.frame) }
        if let window = element(root)?.frame {
            for item in disabledText where viewport.contains(item.frame) {
                let f = item.frame
                contrastText.append([(f.minX - window.minX) / window.width, (f.minY - window.minY) / window.height,
                                     f.width / window.width, f.height / window.height])
            }
        }
        for (i, item) in leaves.enumerated() {
            let f = item.frame
            if min(f.minX - card.frame.minX, card.frame.maxX - f.maxX) < 12 {
                violations.append("Card inset below 12pt: \(item.description) in \(card.frame)")
            }
            if item.truncated { violations.append("Truncated: \(item.title)") }
            for divider in dividers where divider.frame.maxX > f.minX && divider.frame.minX < f.maxX {
                let gap = max(divider.frame.minY - f.maxY, f.minY - divider.frame.maxY)
                if (gap * 2).rounded() / 2 < 8 { violations.append("Divider clearance \(gap)pt: \(item.title)") }
            }
            for other in leaves.dropFirst(i + 1) {
                let overlap = f.intersection(other.frame)
                if overlap.width > 0 && overlap.height > 0 {
                    violations.append("Overlap: \(item.description) / \(other.description)")
                }
            }
        }
        for (row, contents) in rows where !contents.isEmpty && viewport.contains(row.frame) {
            let bounds = contents.reduce(CGRect.null) { $0.union($1.frame) }
            // AXGroup hugs its descendants and can omit outer padding entirely. The
            // PDS marker covers the rendered row, including the top and bottom gutters.
            let frame = formFrames.filter { $0.contains(row.frame) }.min { $0.height < $1.height } ?? row.frame
            let above = bounds.minY - frame.minY
            let below = frame.maxY - bounds.maxY
            if abs(above - below) > 1 {
                violations.append("Unequal row padding: \(contents.first?.title ?? "") (\(above)/\(below) pt)")
            }
        }
        for (index, item) in layoutItems.enumerated() where item.id == "pds.divider" && viewport.contains(item.frame) {
            if index == 0 || index == layoutItems.count - 1 || layoutItems[index - 1].id == item.id {
                violations.append("Leading, trailing or consecutive divider at y=\(item.frame.midY)")
            }
        }
        for header in guides where header.id.hasPrefix("pds.heading.") {
            let column = String(header.id.dropFirst("pds.heading.".count))
            for cell in guides where cell.id == "pds.cell." + column {
                guidePairs += 1
                let trailing = column.hasPrefix("number.")
                let delta = trailing ? header.frame.maxX - cell.frame.maxX : header.frame.minX - cell.frame.minX
                if abs(delta) > 1 { violations.append("Column \(column) misaligned by \(delta)pt: \(header.description) / \(cell.description)") }
            }
        }
    }
    if statusItem {
        var images: [Element] = []
        walk(root) { node, _ in
            if let image = element(node), image.role == kAXImageRole { images.append(image) }
        }
        if images.count != 1 { violations.append("Expected one accessible status item image") }
        for image in images {
            if image.title.isEmpty { violations.append("Status item has no accessible reading") }
            if element(root)?.frame.contains(image.frame) != true {
                violations.append("Status item artwork extends outside its panel")
            }
        }
    } else {
        walk(root) { node, _ in
            let id = string(node, kAXIdentifierAttribute)
            if (id == "pds.card" || id.hasPrefix("popover.card.")), let card = element(node) { inspect(node, card) }
        }
        if cards == 0 { violations.append("No measurable cards") }
    }
    var geometry: [[String: Any]] = []
    if let window = element(root)?.frame {
        func record(_ node: AXUIElement, parent: Int, enabled: Bool) {
            var owner = parent
            let active = enabled && (value(node, kAXEnabledAttribute) as? NSNumber)?.boolValue != false
            if let e = element(node) {
                owner = geometry.count
                geometry.append(["role": e.role, "id": e.id, "title": e.title, "parent": parent, "enabled": active,
                                 "value": (value(node, kAXValueAttribute) as? String) ?? "",
                                 "placeholder": string(node, kAXPlaceholderValueAttribute), "subrole": string(node, kAXSubroleAttribute),
                                 "x": e.frame.minX - window.minX, "y": e.frame.minY - window.minY,
                                 "w": e.frame.width, "h": e.frame.height])
            }
            for child in value(node, kAXChildrenAttribute) as? [AXUIElement] ?? [] {
                record(child, parent: owner, enabled: active)
            }
        }
        record(root, parent: -1, enabled: true)
    }
    let report: [String: Any] = ["windowActive": windowActive, "geometry": geometry, "cards": cards, "columnPairs": guidePairs, "disabledTextFrames": contrastText, "violations": violations]
    let data = try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys])
    print(String(decoding: data, as: UTF8.self))
}
