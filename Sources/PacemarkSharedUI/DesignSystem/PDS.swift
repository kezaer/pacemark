import SwiftUI

/// Visual roles shared by the Mac settings window and the menu bar panel.
public enum PDS {
  public enum Space {
    public static let xs: CGFloat = 4, s: CGFloat = 8, m: CGFloat = 12, l: CGFloat = 16,
      xl: CGFloat = 24
  }
  public enum Radius {
    public static let card: CGFloat = 12, chip: CGFloat = 8, control: CGFloat = 6
  }
  public enum Typography {
    public static let paneTitle = Font.system(size: 20, weight: .semibold)
    public static let paneSubtitle = Font.system(size: 12)
    public static let caps = Font.system(size: 10, weight: .semibold)
    public static let tracking: CGFloat = 0.6
    public static let rowTitle = Font.system(size: 13, weight: .semibold)
    public static let body = Font.system(size: 13)
    public static let secondary = Font.system(size: 11)
    public static let number = rowTitle.monospacedDigit()
    public static let numberLarge = Font.system(size: 18, weight: .semibold).monospacedDigit()
    public static let numberSmall = secondary.monospacedDigit()
  }
  public enum Ink {
    public static let ink = Color.primary, inkSecondary = Color.primary.opacity(0.89),
      inkTertiary = Color.primary.opacity(0.85)
    public static func link(_ scheme: ColorScheme) -> Color {
      scheme == .dark ? Color(red: 180/255, green: 236/255, blue: 1) : Color(red: 0.02, green: 0.28, blue: 0.55)
    }
    public static func paceWarning(_ scheme: ColorScheme) -> Color {
      scheme == .dark ? Color(red: 1, green: 0.77, blue: 0.43) : Color(red: 0.48, green: 0.25, blue: 0)
    }
    public static func paceCritical(_ scheme: ColorScheme) -> Color {
      ProviderStyle.severityColor(for: .critical, scheme: scheme)
    }
    public static let disabledText = Color.primary.opacity(0.68)
    public static let separator = Color.primary.opacity(0.20),
      cardFill = Color.primary.opacity(0.045)
    public static let cardStroke = Color.primary.opacity(0.12), accent = Color.accentColor
  }
  public enum Metrics {
    public static let row: CGFloat = 28, rowCompact: CGFloat = 24, control: CGFloat = 24
    public static let sidebarRow: CGFloat = 28, sidebarIcon: CGFloat = 16
    public static let dividerSlot: CGFloat = 1
    public static let sectionHeader: CGFloat = 26
    public static let cardHeader = sectionHeader + Space.xs
    public static let rowMark: CGFloat = 12, providerMark: CGFloat = 14, headerMark: CGFloat = 20
  }
}

/// A single-line section title with optional account count.
public struct PDSCapsHeader: View {
  let title: String
  let count: Int?
  public init(_ title: String, count: Int? = nil) {
    self.title = title
    self.count = count
  }
  public var body: some View {
    HStack(spacing: PDS.Space.xs) {
      Text(title.uppercased()).font(PDS.Typography.caps).tracking(PDS.Typography.tracking)
        .foregroundStyle(PDS.Ink.inkSecondary).lineLimit(1)
      if let count { PDSChip(text: count.formatted()) }
    }.accessibilityAddTraits(.isHeader)
  }
}

private extension ContainerValues {
  @Entry var ownsFormPadding = false
  @Entry var startsTable = false
}

public extension EnvironmentValues {
  /// Card geometry reserves space for each control, including its interaction area.
  @Entry var insidePDSCard = false
}

/// The section surface, including the header gutter and border.
public struct PDSCard<Mark: View, Accessory: View, Content: View>: View {
  private static var isQAFixture: Bool { ProcessInfo.processInfo.arguments.contains("--qa-display") }
  let title: String?
  let count: Int?
  let mark: Mark
  let accessory: Accessory
  let content: Content
  public init(
    _ title: String? = nil, count: Int? = nil, @ViewBuilder mark: () -> Mark = { EmptyView() }, @ViewBuilder accessory: () -> Accessory,
    @ViewBuilder content: () -> Content
  ) {
    self.title = title
    self.count = count
    self.mark = mark()
    self.accessory = accessory()
    self.content = content()
  }
  public var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      if let title {
        HStack(spacing: PDS.Space.xs) {
          mark
          PDSCapsHeader(title, count: count)
          Spacer(minLength: 0)
          accessory
        }
        .controlSize(.small)
        .padding(.vertical, PDS.Space.s)
        .frame(minHeight: PDS.Metrics.cardHeader)

      }
      Group(subviews: content) { rows in
        ForEach(rows) { row in
          if row.id != rows.first?.id && !row.containerValues.startsTable {
            PDSDivider().frame(height: PDS.Metrics.dividerSlot)
          }
          row.padding(.vertical, row.containerValues.ownsFormPadding ? 0 : PDS.Space.s)
            .background {
              if Self.isQAFixture {
                Color.clear.accessibilityElement(children: .ignore)
                  .accessibilityLabel("Card item").accessibilityIdentifier("pds.item")
              }
            }
        }
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(.horizontal, PDS.Space.m)
    .padding(.top, title == nil ? PDS.Space.xs : .zero)
    .padding(.bottom, PDS.Space.xs)
    .modifier(PDSCardSurface())
    .environment(\.insidePDSCard, true)
    .accessibilityElement(children: .contain)
    .accessibilityIdentifier("pds.card")
  }
}

/// Section fill and physical-pixel border for fixed-height summary cards.
public struct PDSCardSurface: ViewModifier {
  @Environment(\.colorScheme) private var scheme
  @Environment(\.displayScale) private var displayScale
  public init() {}
  public func body(content: Content) -> some View {
    content
      .background(PDS.Ink.cardFill, in: RoundedRectangle(cornerRadius: PDS.Radius.card))
      .background {
        if scheme == .dark {
          RoundedRectangle(cornerRadius: PDS.Radius.card).fill(.background.opacity(0.35))
        }
      }
      .overlay {
        RoundedRectangle(cornerRadius: PDS.Radius.card).strokeBorder(
          PDS.Ink.cardStroke, lineWidth: 1 / displayScale
        ).allowsHitTesting(false)
      }
  }
}

/// Keep each table row a single layout subview so reordering layouts can still position it.
public struct PDSTableRows<Content: View>: View {
  let content: Content
  let followsHeadings: Bool
  public init(followsHeadings: Bool = false, @ViewBuilder content: () -> Content) {
    self.followsHeadings = followsHeadings
    self.content = content()
  }
  public var body: some View {
    Group(subviews: content) { rows in
      ForEach(rows) { row in
        row.overlay(alignment: .top) {
          if followsHeadings || row.id != rows.first?.id { PDSDivider() }
        }
      }
    }
  }
}

/// Adaptive window material shared by the Settings and menu bar hosts.
public struct PDSSurface: ViewModifier {
  let radius: CGFloat
  let tint: Color
  let opacity: Double
  let clear: Bool
  public init(radius: CGFloat, tint: Color, opacity: Double, clear: Bool = false) {
    self.radius = radius
    self.tint = tint
    self.opacity = opacity
    self.clear = clear
  }
  public func body(content: Content) -> some View {
    let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
    if #available(macOS 26, *) {
      let glass: Glass = clear ? .clear : .regular
      content.background {
        // Apply the configured wash above the material. Glass.tint alone can leave
        // small ledger labels directly over saturated desktop colours.
        Color.clear.glassEffect(glass, in: shape)
          .overlay { shape.fill(tint.opacity(opacity)) }
      }
    } else {
      content.background(.regularMaterial, in: shape)
        .overlay { if radius > 0 { shape.strokeBorder(PDS.Ink.separator, lineWidth: 0.5) } }
    }
  }
}

/// One physical-pixel rule used by both ledger tables and control rows.
public struct PDSDivider: View {
  @Environment(\.displayScale) private var displayScale
  public init() {}
  public var body: some View {
    Rectangle().fill(PDS.Ink.separator).frame(height: 1 / displayScale)
      .allowsHitTesting(false)
      .accessibilityElement(children: .ignore)
      .accessibilityLabel("Separator")
      .accessibilityIdentifier("pds.divider")
      .accessibilityHidden(!ProcessInfo.processInfo.arguments.contains("--qa-display"))
  }
}

/// A vertically centered control row. The enclosing card owns its separators.
public struct PDSRow<Leading: View, Trailing: View>: View {
  let leading: Leading
  let trailing: Trailing
  public init(@ViewBuilder leading: () -> Leading, @ViewBuilder trailing: () -> Trailing) {
    self.leading = leading()
    self.trailing = trailing()
  }
  public var body: some View {
    HStack(spacing: PDS.Space.s) {
      leading
      Spacer(minLength: PDS.Space.s)
      trailing
    }
    .padding(.vertical, PDS.Space.s)
    .accessibilityElement(children: .contain)
    .accessibilityIdentifier("pds.row")
    .pdsColumnGuide("pds.form.bounds")
    .containerValue(\.ownsFormPadding, true)
  }
}

/// Geometry shared by column labels and their values.
public enum PDSColumns {
  case text, number
  case menu(width: CGFloat)
  public func cell<V: View>(_ value: V) -> some View {
    Group {
      switch self {
      case .text: value.frame(maxWidth: .infinity, alignment: .leading)
      case .number: value.monospacedDigit().frame(maxWidth: .infinity, alignment: .trailing)
      case .menu(let width):
        value.lineLimit(1).truncationMode(.tail).frame(width: width, alignment: .leading)
      }
    }
  }
}

/// Menu value and fixed trailing indicator in one picker column.
public struct PDSMenuValue<Label: View>: View {
  let width: CGFloat
  let label: Label
  public init(width: CGFloat, @ViewBuilder label: () -> Label) {
    self.width = width
    self.label = label()
  }
  public var body: some View {
    PDSColumns.menu(width: width).cell(
      HStack(spacing: PDS.Space.xs) {
        label.lineLimit(1).truncationMode(.tail)
        Spacer(minLength: 0)
        Image(systemName: "chevron.down").accessibilityHidden(true)
      }
    )
  }
}

/// A setting with one trailing switch.
public struct PDSToggleRow: View {
  let title: String
  let help: String?
  @Binding var isOn: Bool
  public init(title: String, help: String? = nil, isOn: Binding<Bool>) {
    self.title = title
    self.help = help
    _isOn = isOn
  }
  public var body: some View {
    PDSRow {
      VStack(alignment: .leading, spacing: PDS.Space.xs) {
        Text(title).font(PDS.Typography.body)
        if let help { PDSHelpText(help) }
      }
    } trailing: {
      Toggle(title, isOn: $isOn).toggleStyle(.switch).labelsHidden().frame(minHeight: PDS.Metrics.control)
    }
  }
}

/// A labelled setting with a bounded picker.
public struct PDSPickerRow<Control: View>: View {
  let title: String
  let help: String?
  let control: Control
  public init(_ title: String, help: String? = nil, @ViewBuilder control: () -> Control) {
    self.title = title
    self.help = help
    self.control = control()
  }
  public var body: some View {
    PDSRow {
      VStack(alignment: .leading, spacing: PDS.Space.xs) {
        Text(title).font(PDS.Typography.body)
        if let help { PDSHelpText(help) }
      }
    } trailing: {
      control.frame(minHeight: PDS.Metrics.control)
    }
  }
}

/// The selected swatch and its group title always share this vertical gutter.
public struct PDSSwatchGroup<Content: View>: View {
  let title: String
  let content: Content
  public init(_ title: String, @ViewBuilder content: () -> Content) {
    self.title = title
    self.content = content()
  }
  public var body: some View {
    VStack(alignment: .leading, spacing: PDS.Space.s) {
      Text(title).font(PDS.Typography.body)
      content
    }
  }
}

/// A metadata chip that disappears when its entire label cannot fit.
public struct PDSChip: View {
  let text: String
  let icon: String?
  let outlined: Bool
  let compact: Bool
  public init(text: String, icon: String? = nil, outlined: Bool = false, compact: Bool = false) {
    self.text = text
    self.icon = icon
    self.outlined = outlined
    self.compact = compact
  }
  public var body: some View {
    ViewThatFits(in: .horizontal) {
      HStack(spacing: PDS.Space.xs) {
        if let icon { Image(systemName: icon) }
        Text(text)
      }.font(PDS.Typography.caps).foregroundStyle(PDS.Ink.inkSecondary).lineLimit(1)
        .padding(.horizontal, PDS.Space.xs).frame(height: compact ? 13 : 16)
        .background(PDS.Ink.cardFill, in: Capsule())
        .overlay { if outlined { Capsule().strokeBorder(PDS.Ink.cardStroke) } }
        .fixedSize()
      Color.clear.frame(width: 0, height: 0)
    }
  }
}

/// Secondary explanatory text that wraps to its available width.
public struct PDSHelpText: View {
  @Environment(\.isEnabled) private var enabled
  let text: String
  public init(_ text: String) { self.text = text }
  public var body: some View {
    Text(text).font(PDS.Typography.secondary).foregroundStyle(enabled ? PDS.Ink.inkSecondary : PDS.Ink.disabledText).fixedSize(
      horizontal: false, vertical: true)
  }
}

/// Sidebar destination with one icon column and selection foreground.
public struct PDSSidebarRow: View {
  let title: String, symbol: String
  public init(_ title: String, symbol: String) {
    self.title = title
    self.symbol = symbol
  }
  public var body: some View {
    HStack(spacing: PDS.Space.s) {
      Image(systemName: symbol).frame(width: PDS.Metrics.sidebarIcon)
      Text(title).lineLimit(1)
    }.font(PDS.Typography.body)
      .frame(height: PDS.Metrics.sidebarRow)
  }
}

#if os(macOS)
/// Anchors are inert tracking views. A window shares one delayed presentation.
private struct PDSTipAnchor: NSViewRepresentable {
  let text: String
  var pinned: Bool
  private static let fixturePrefix: String? = {
    guard Bundle.main.bundleIdentifier == "org.pacemark.qa.fixture",
          let index = CommandLine.arguments.firstIndex(of: "--qa-tip-prefix") else { return nil }
    return CommandLine.arguments.dropFirst(index + 1).first
  }()
  func makeNSView(context: Context) -> Anchor { Anchor() }
  func updateNSView(_ view: Anchor, context: Context) {
    view.text = text
    view.pinned = pinned || Self.fixturePrefix.map(text.hasPrefix) == true
    view.schedulePinnedTip()
  }
  final class Anchor: NSView {
    var text = ""
    var pinned = false
    override func viewDidMoveToWindow() {
      super.viewDidMoveToWindow()
      schedulePinnedTip()
    }
    func schedulePinnedTip() {
      guard pinned, let window else { return }
      let host = TipHost.host(for: window)
      if host.anchor == nil { host.schedule(self) }
    }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    override func updateTrackingAreas() {
      super.updateTrackingAreas()
      for area in trackingAreas { removeTrackingArea(area) }
      addTrackingArea(NSTrackingArea(rect: .zero, options: [.activeAlways, .inVisibleRect, .mouseEnteredAndExited], owner: self))
    }
    override func mouseEntered(with event: NSEvent) {
      guard let window, !text.isEmpty else { return }
      TipHost.host(for: window).schedule(self)
    }
    override func mouseExited(with event: NSEvent) { dismiss() }
    override func viewWillMove(toWindow newWindow: NSWindow?) { dismiss(); super.viewWillMove(toWindow: newWindow) }
    private func dismiss() {
      if let window, let host = TipHost.hosts.object(forKey: window), host.anchor === self { host.hide() }
    }
  }

  final class TipPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
  }

  @MainActor final class TipHost {
    static let hosts = NSMapTable<NSWindow, TipHost>.weakToStrongObjects()
    weak var anchor: Anchor?
    var pending: Task<Void, Never>?
    var monitor: Any?
    let panel = TipPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
    static func host(for window: NSWindow) -> TipHost {
      if let host = hosts.object(forKey: window) { return host }
      let host = TipHost()
      hosts.setObject(host, forKey: window)
      return host
    }
    func schedule(_ source: Anchor) {
      hide()
      anchor = source
      monitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]) { [weak self] event in
        self?.hide()
        return event
      }
      pending = Task { [weak self, weak source] in
        try? await Task.sleep(for: .milliseconds(400))
        guard !Task.isCancelled, let self, let source, let owner = source.window, owner.isVisible, let container = owner.contentView else { return }
        let bounds = owner.convertToScreen(container.convert(container.bounds, to: nil))
        let label = NSHostingView(rootView: PDSTipLabel(source.text, maximumWidth: bounds.width))
        let size = label.fittingSize
        // Keep SwiftUI size negotiation from resizing the panel after placement.
        label.sizingOptions = []
        label.frame = NSRect(origin: .zero, size: size)
        let surface = NSView(frame: label.frame)
        surface.addSubview(label)
        panel.contentView = surface
        panel.appearance = owner.effectiveAppearance
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.ignoresMouseEvents = true
        panel.hasShadow = true
        let rect = owner.convertToScreen(source.convert(source.bounds, to: nil))
        // Leave enough air to keep the badge and its outline visible.
        let gap: CGFloat = 6
        let below = rect.minY - gap - size.height
        let y = below >= bounds.minY ? below : rect.maxY + gap
        panel.setFrame(NSRect(
          x: max(bounds.minX, min(rect.minX, bounds.maxX - size.width)),
          y: max(bounds.minY, min(y, bounds.maxY - size.height)),
          width: size.width, height: size.height), display: true)
        owner.addChildWindow(panel, ordered: .above)
        panel.orderFrontRegardless()
      }
    }
    func hide() {
      pending?.cancel()
      pending = nil
      if let monitor { NSEvent.removeMonitor(monitor) }
      monitor = nil
      panel.parent?.removeChildWindow(panel)
      panel.orderOut(nil)
      anchor = nil
    }
  }
}
#endif

public struct PDSTipLabel: View {
  let text: String
  let maximumWidth: CGFloat
  @Environment(\.colorScheme) private var scheme
  public init(_ text: String, maximumWidth: CGFloat = 260) {
    self.text = text
    self.maximumWidth = maximumWidth
  }
  public var body: some View {
    let lines = text.split(separator: "\n", maxSplits: 1)
    let shape = RoundedRectangle(cornerRadius: PDS.Radius.chip)
    VStack(alignment: .leading, spacing: PDS.Space.xs) {
      Text(verbatim: lines.first.map(String.init) ?? "").font(PDS.Typography.body)
      if lines.count == 2 {
        Text(verbatim: String(lines[1])).font(PDS.Typography.secondary)
      }
    }
    .foregroundStyle(PDS.Ink.ink)
    .padding(PDS.Space.s)
    .frame(maxWidth: min(260, maximumWidth), alignment: .leading)
    .fixedSize(horizontal: false, vertical: true)
    .background {
      shape.fill(scheme == .dark ? Color(white: 0.17) : .white)
        .shadow(color: .black.opacity(0.22), radius: 3, y: 1)
    }
    .overlay { shape.strokeBorder(PDS.Ink.separator, lineWidth: 0.5) }
  }
}

public struct PDSHoverTip: ViewModifier {
  let text: String
  let pinned: Bool
  public init(_ text: String, pinned: Bool = false) {
    self.text = text
    self.pinned = pinned
  }
  public func body(content: Content) -> some View {
    #if os(macOS)
      content.background { PDSTipAnchor(text: text, pinned: pinned) }.accessibilityHint(text)
    #else
      content.accessibilityHint(text)
    #endif
  }
}

extension View {
  public func pdsFormPicker() -> some View {
    pickerStyle(.menu).labelsHidden().buttonStyle(.bordered).controlSize(.small).background(.background.opacity(0.75), in: RoundedRectangle(cornerRadius: PDS.Radius.control))
  }
  #if os(macOS)
  public func pdsCellMenu() -> some View {
    menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden).controlSize(.small)
  }
  #endif
  public func pdsSegmented() -> some View {
    pickerStyle(.segmented).labelsHidden().pdsSegmentedSize().background(.background.opacity(0.75), in: RoundedRectangle(cornerRadius: PDS.Radius.control))
  }
  public func pdsSegmentedSize() -> some View {
    controlSize(.small).frame(height: PDS.Metrics.control)
  }
  public func pdsHoverTip(_ text: String, pinned: Bool = false) -> some View { modifier(PDSHoverTip(text, pinned: pinned)) }
}

public extension View {
  /// A table starts with its headings and draws its first divider beneath them.
  func pdsTableStart() -> some View { containerValue(\.startsTable, true) }

  /// Preserve the text's own frame when SwiftUI coalesces the enclosing control for VoiceOver.
  func pdsColumnGuide(_ id: String) -> some View {
    background {
      if ProcessInfo.processInfo.arguments.contains("--qa-display") {
        Color.clear.accessibilityElement(children: .ignore)
          .accessibilityLabel("Column guide").accessibilityIdentifier(id)
      }
    }
  }
}
