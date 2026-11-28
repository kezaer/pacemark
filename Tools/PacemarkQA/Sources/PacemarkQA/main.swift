import AppKit
import ApplicationServices
import Display
import ScreenCaptureKit

struct Failure: LocalizedError {
    var errorDescription: String? { message }
    let message: String
    init(_ message: String) { self.message = message }
}

func permission(_ name: String) -> Failure {
    let pid = qaResponsiblePID()
    let owner = NSRunningApplication(processIdentifier: pid)
    if let url = owner?.bundleURL ?? owner?.executableURL {
        return Failure("\(name) permission required for \(owner?.localizedName ?? url.lastPathComponent) (\(url.path))")
    }
    var path = [CChar](repeating: 0, count: 4096)
    let length = proc_pidpath(pid, &path, UInt32(path.count))
    guard length > 0 else { return Failure("\(name) permission required for responsible process PID \(pid); executable path unavailable") }
    let url = URL(fileURLWithPath: String(decoding: path.prefix { $0 != 0 }.map(UInt8.init(bitPattern:)), as: UTF8.self))
    return Failure("\(name) permission required for \(url.lastPathComponent) (\(url.path))")
}

func value(_ node: AXUIElement, _ key: String) -> CFTypeRef? {
    var result: CFTypeRef?
    AXUIElementCopyAttributeValue(node, key as CFString, &result)
    return result
}

func string(_ node: AXUIElement, _ key: String) -> String {
    value(node, key).map { String(describing: $0) } ?? ""
}

func walk(_ node: AXUIElement, depth: Int = 0, visit: (AXUIElement, Int) -> Void) {
    guard depth < 80 else { return }
    visit(node, depth)
    for child in value(node, kAXChildrenAttribute) as? [AXUIElement] ?? [] {
        walk(child, depth: depth + 1, visit: visit)
    }
}

func drive(_ pid: pid_t, _ args: [String], _ window: String?) throws {
    guard AXIsProcessTrusted() else { throw permission("Accessibility") }
    let app = AXUIElementCreateApplication(pid)
    let windows = value(app, kAXWindowsAttribute) as? [AXUIElement] ?? []
    guard let root = windows.first(where: {
        let title = string($0, kAXTitleAttribute)
        return title == "QA \(window?.capitalized ?? "Settings")" || (window == nil && title == "QA Popover")
    }) else { throw Failure("QA window unavailable") }
    if args == ["check"] { try checkLayout(root, statusItem: window == "status"); return }
    let target = args.first == "select-pane" ? "pane." + (args.dropFirst().first ?? "") : args.dropFirst().first
    var match: AXUIElement?
    walk(root) { node, depth in
        let id = string(node, kAXIdentifierAttribute), title = string(node, kAXTitleAttribute)
        let description = string(node, kAXDescriptionAttribute)
        if args.first == "tree" {
            print(String(repeating: " ", count: depth), string(node, kAXRoleAttribute), id, title, description, string(node, kAXValueAttribute))
        } else if match == nil && (id == target || title == target || description == target) { match = node }
    }
    if args == ["tree"] { return }
    guard let match else { throw Failure("Missing QA control: \(target ?? "")") }
    let result: AXError
    switch (args.first, args.count) {
    case ("press", 2): result = AXUIElementPerformAction(match, kAXPressAction as CFString)
    case ("select-pane", 2):
        var row = match
        while string(row, kAXRoleAttribute) != kAXRowRole {
            guard let parent = value(row, kAXParentAttribute), CFGetTypeID(parent) == AXUIElementGetTypeID() else { break }
            row = parent as! AXUIElement
        }
        result = AXUIElementSetAttributeValue(row, kAXSelectedAttribute as CFString, kCFBooleanTrue)
    case ("set", 3):
        let newValue: CFTypeRef = value(match, kAXValueAttribute) is NSNumber
            ? NSNumber(value: try Double(args[2]).unwrap("Expected numeric AX value")) : args[2] as NSString
        result = AXUIElementSetAttributeValue(match, kAXValueAttribute as CFString, newValue)
    case ("scroll", 3) where ["top", "bottom"].contains(args[2]):
        if target == "popover.cards" {
            var actions: CFArray?
            AXUIElementCopyActionNames(match, &actions)
            let names = actions as? [String] ?? []
            let label = "QA scroll " + args[2]
            guard let action = names.first(where: { name in
                var description: CFString?
                AXUIElementCopyActionDescription(match, name as CFString, &description)
                return name.contains(label) || (description as String?) == label
            }) else { throw Failure("Missing scroll action among \(names)") }
            result = AXUIElementPerformAction(match, action as CFString)
        } else if let bar = value(match, kAXVerticalScrollBarAttribute) {
            result = AXUIElementSetAttributeValue(bar as! AXUIElement, kAXValueAttribute as CFString,
                NSNumber(value: args[2] == "top" ? 0.0 : 1.0))
        } else {
            if string(match, kAXRoleAttribute) == kAXScrollAreaRole,
               (value(match, kAXChildrenAttribute) as? [AXUIElement]) != nil { return }
            throw Failure("No vertical scroll bar")
        }
    default: throw Failure("Invalid AX command")
    }
    guard result == .success else { throw Failure("AX action failed (\(result.rawValue))") }
}

extension Optional {
    func unwrap(_ message: String) throws -> Wrapped {
        guard let value = self else { throw Failure(message) }
        return value
    }
}

func run() async throws {
    var args = Array(CommandLine.arguments.dropFirst())
    if args.count == 2, ["words", "words-fast"].contains(args[0]) {
        try captureWords(at: args[1], fastOnly: args[0] == "words-fast")
        return
    }
    let session = CGSessionCopyCurrentDictionary() as? [String: Any]
    guard session?["CGSSessionScreenIsLocked"] as? Bool != true else {
        throw Failure("macOS session locked. Live window QA requires an unlocked desktop.")
    }
    if args == ["display"] {
        let main = CGMainDisplayID()
        var screens = [CGDirectDisplayID](repeating: 0, count: 64), count: UInt32 = 0
        guard CGGetActiveDisplayList(64, &screens, &count) == .success else { throw Failure("No display list") }
        guard count > 0, count < screens.count else { throw Failure("Active desktop unavailable") }
        let right = screens.prefix(Int(count)).map { CGDisplayBounds($0).maxX }.max() ?? 0
        let id = createQADisplay()
        guard id != 0, id != main, CGMainDisplayID() == main, CGDisplayIsInMirrorSet(id) == 0 else {
            throw Failure("Separate virtual display unavailable")
        }
        var config: CGDisplayConfigRef?
        guard CGBeginDisplayConfiguration(&config) == .success else { throw Failure("No display configuration") }
        guard CGConfigureDisplayOrigin(config, id, Int32(right), 0) == .success else {
            CGCancelDisplayConfiguration(config)
            throw Failure("Cannot place virtual display")
        }
        guard CGCompleteDisplayConfiguration(config, .forSession) == .success,
              CGDisplayBounds(id).minX == right,
              CGDisplayBounds(id).size == CGSize(width: 1512, height: 982),
              CGDisplayCopyDisplayMode(id)?.pixelWidth == 3024 else { throw Failure("Virtual display placement failed") }
        print(id)
        fflush(nil)
        while true { try await Task.sleep(for: .seconds(60)) }
    }
    guard args.count >= 3, let pid = Int32(args.removeFirst()), let id = UInt32(args.removeFirst()),
          id != CGMainDisplayID(), CGDisplayModelNumber(id) == 0x5141, CGDisplayIsInMirrorSet(id) == 0
    else { throw Failure("Expected the active QA display and PID") }
    guard let owner = NSRunningApplication(processIdentifier: pid),
          owner.bundleIdentifier == "org.pacemark.qa.fixture",
          owner.bundleURL?.lastPathComponent == "QA Fixture.app" else { throw Failure("PID is not a QA fixture") }
    var window: String?
    if let i = args.firstIndex(of: "--window") {
        guard i + 1 < args.count, ["settings","popover","gallery","status"].contains(args[i+1]) else { throw Failure("Invalid window") }
        window = args[i+1]
        args.removeSubrange(i...i+1)
    }
    if args == ["check"] { try drive(pid, args, window); return }
    if args.first == "ax" { try drive(pid, Array(args.dropFirst()), window); return }
    guard args.count == 2, args[0] == "shot" else { throw Failure("Expected shot or ax") }
    guard CGPreflightScreenCaptureAccess() else { throw permission("Screen Recording") }
    let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
    let display = try content.displays.first { $0.displayID == id }.unwrap("QA display unavailable")
    let filter = SCContentFilter(display: display, excludingWindows: [])
    let config = SCStreamConfiguration()
    let size: CGSize
    if let window {
        let target = try content.windows.first {
            $0.owningApplication?.processID == pid && $0.title == "QA \(window.capitalized)" && display.frame.contains($0.frame)
        }.unwrap("QA window missing or outside display")
        // A desktop-independent capture loses the backdrop sampled by Liquid Glass
        // and includes the shadow child outside the panel. Capture the composited panel.
        config.sourceRect = target.frame.offsetBy(dx: -display.frame.minX, dy: -display.frame.minY)
        size = target.frame.size
    } else {
        size = filter.contentRect.size
    }
    config.showsCursor = false
    config.width = Int(size.width * CGFloat(filter.pointPixelScale))
    config.height = Int(size.height * CGFloat(filter.pointPixelScale))
    let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
    let data = try NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]).unwrap("PNG encoding failed")
    try data.write(to: URL(fileURLWithPath: args[1]), options: .atomic)
}

do { try await run() }
catch {
    FileHandle.standardError.write(Data((error.localizedDescription + "\n").utf8))
    exit(1)
}
