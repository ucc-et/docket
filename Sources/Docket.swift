import AppKit
import SwiftUI

// MARK: - Model (persisted as JSON in ~/Library/Application Support/Docket)

struct CheckItem: Codable, Identifiable, Equatable {
    var id = UUID()
    var text: String
    var done: Bool = false
}

enum NoteMode: String, Codable { case text, checklist }

struct NoteData: Codable {
    var mode: NoteMode = .text
    var text: String = ""
    var items: [CheckItem] = []
}

final class NoteStore: ObservableObject {
    @Published var data: NoteData { didSet { save() } }
    private let url: URL

    init() {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let dir = support.appendingPathComponent("Docket", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        url = dir.appendingPathComponent("note.json")
        // carry over notes from the old "DockNote" name
        let legacy = support.appendingPathComponent("DockNote/note.json")
        if !FileManager.default.fileExists(atPath: url.path) {
            try? FileManager.default.copyItem(at: legacy, to: url)
        }
        if let raw = try? Data(contentsOf: url),
           let decoded = try? JSONDecoder().decode(NoteData.self, from: raw) {
            data = decoded
        } else {
            data = NoteData()
        }
    }

    func save() {
        if let raw = try? JSONEncoder().encode(data) { try? raw.write(to: url, options: .atomic) }
    }
}

// MARK: - Views

struct SizePreset {
    let label: String, name: String, size: NSSize
    static let all = [
        SizePreset(label: "S", name: "Small", size: NSSize(width: 260, height: 280)),
        SizePreset(label: "M", name: "Medium", size: NSSize(width: 340, height: 400)),
        SizePreset(label: "L", name: "Large", size: NSSize(width: 500, height: 580)),
    ]
}

/// Small grip: drag to move the window, double-click to snap it back to the Dock.
struct DragHandle: NSViewRepresentable {
    var onMoved: () -> Void
    var onReset: () -> Void

    final class HandleView: NSView {
        var onMoved: () -> Void = {}
        var onReset: () -> Void = {}
        override func mouseDown(with event: NSEvent) {
            if event.clickCount == 2 { onReset(); return }
            onMoved()   // arms move tracking; the actual move is detected in windowDidMove
            window?.performDrag(with: event)
        }
        override func resetCursorRects() { addCursorRect(bounds, cursor: .openHand) }
        override func draw(_ dirtyRect: NSRect) {
            let img = NSImage(systemSymbolName: "line.3.horizontal", accessibilityDescription: "Move")!
                .withSymbolConfiguration(.init(pointSize: 13, weight: .medium))!
            let tinted = NSImage(size: img.size, flipped: false) { r in
                img.draw(in: r); NSColor.secondaryLabelColor.set(); r.fill(using: .sourceAtop); return true
            }
            tinted.draw(at: NSPoint(x: (bounds.width - img.size.width) / 2,
                                    y: (bounds.height - img.size.height) / 2),
                        from: .zero, operation: .sourceOver, fraction: 1)
        }
    }

    func makeNSView(context: Context) -> HandleView {
        let v = HandleView(); v.toolTip = "Drag to move · double-click to snap back to the Dock"
        return v
    }
    func updateNSView(_ v: HandleView, context: Context) { v.onMoved = onMoved; v.onReset = onReset }
}

/// Bottom-right corner grip for resizing.
struct ResizeGrip: NSViewRepresentable {
    var onResized: () -> Void

    final class GripView: NSView {
        var onResized: () -> Void = {}
        private var startMouse = NSPoint.zero
        private var startFrame = NSRect.zero
        override func mouseDown(with e: NSEvent) {
            (NSApp.delegate as? AppDelegate)?.dragArmed = false
            startMouse = NSEvent.mouseLocation; startFrame = window?.frame ?? .zero
        }
        override func mouseDragged(with e: NSEvent) {
            guard let w = window else { return }
            let m = NSEvent.mouseLocation
            let width = max(w.minSize.width, startFrame.width + (m.x - startMouse.x))
            let height = max(w.minSize.height, startFrame.height - (m.y - startMouse.y))
            // keep the top-left corner fixed
            w.setFrame(NSRect(x: startFrame.minX, y: startFrame.maxY - height,
                              width: width, height: height), display: true)
        }
        override func mouseUp(with e: NSEvent) { onResized() }
        override func resetCursorRects() { addCursorRect(bounds, cursor: .crosshair) }
        override func draw(_ r: NSRect) {
            NSColor.tertiaryLabelColor.setStroke()
            for i in 1...3 {
                let d = CGFloat(i) * 4
                let p = NSBezierPath()
                p.move(to: NSPoint(x: bounds.maxX - d - 2, y: 2))
                p.line(to: NSPoint(x: bounds.maxX - 2, y: d + 2))
                p.lineWidth = 1.2; p.stroke()
            }
        }
    }
    func makeNSView(context: Context) -> GripView { let v = GripView(); v.toolTip = "Drag to resize"; return v }
    func updateNSView(_ v: GripView, context: Context) { v.onResized = onResized }
}

/// NSTextView wrapper whose scrollbar only appears when the text overflows.
struct PlainTextEditor: NSViewRepresentable {
    @Binding var text: String

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSTextView.scrollableTextView()
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.scrollerStyle = .overlay
        let tv = scroll.documentView as! NSTextView
        tv.drawsBackground = false
        tv.font = .systemFont(ofSize: 14)
        tv.isRichText = false
        tv.allowsUndo = true
        tv.textContainerInset = NSSize(width: 0, height: 4)
        tv.string = text
        tv.delegate = context.coordinator
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        let tv = scroll.documentView as! NSTextView
        if tv.string != text { tv.string = text }
        context.coordinator.parent = self
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: PlainTextEditor
        init(_ p: PlainTextEditor) { parent = p }
        func textDidChange(_ n: Notification) {
            parent.text = (n.object as! NSTextView).string
        }
    }
}

struct NoteView: View {
    @ObservedObject var store: NoteStore
    var onCollapse: () -> Void = {}
    var onMoved: () -> Void = {}
    var onReset: () -> Void = {}
    var onResized: () -> Void = {}
    var onPreset: (NSSize) -> Void = { _ in }
    @State private var newItem = ""

    var body: some View {
        VStack(spacing: 8) {
            HStack {
                DragHandle(onMoved: onMoved, onReset: onReset)
                    .frame(width: 20, height: 20)
                Picker("", selection: $store.data.mode) {
                    Label("Note", systemImage: "note.text").tag(NoteMode.text)
                    Label("Checklist", systemImage: "checklist").tag(NoteMode.checklist)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                if store.data.mode == .checklist && store.data.items.contains(where: \.done) {
                    Button("Clear done") { store.data.items.removeAll(where: \.done) }
                        .buttonStyle(.borderless).font(.caption)
                }
                HStack(spacing: 2) {
                    ForEach(SizePreset.all, id: \.label) { p in
                        Button(p.label) { onPreset(p.size) }
                            .buttonStyle(.plain)
                            .font(.system(size: 10, weight: .semibold))
                            .frame(width: 18, height: 18)
                            .background(RoundedRectangle(cornerRadius: 4).fill(Color.primary.opacity(0.08)))
                            .help(p.name)
                    }
                }
                Button(action: onCollapse) {
                    Image(systemName: "chevron.down.circle.fill")
                        .font(.system(size: 16))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Collapse")
            }
            if store.data.mode == .text {
                PlainTextEditor(text: $store.data.text)
            } else {
                checklist
            }
        }
        .padding(12)
        .frame(minWidth: 240, maxWidth: .infinity, minHeight: 200, maxHeight: .infinity)
        .overlay(alignment: .bottomTrailing) {
            ResizeGrip(onResized: onResized).frame(width: 16, height: 16)
        }
        .background(.regularMaterial)
    }

    private var checklist: some View {
        VStack(spacing: 6) {
            List {
                ForEach($store.data.items) { $item in
                    HStack {
                        Button { item.done.toggle() } label: {
                            Image(systemName: item.done ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(item.done ? Color.accentColor : .secondary)
                        }.buttonStyle(.plain)
                        TextField("", text: $item.text)
                            .textFieldStyle(.plain)
                            .strikethrough(item.done)
                            .foregroundStyle(item.done ? .secondary : .primary)
                        Button { store.data.items.removeAll { $0.id == item.id } } label: {
                            Image(systemName: "xmark").font(.caption)
                        }.buttonStyle(.plain).foregroundStyle(.tertiary)
                    }
                }
                .onMove { store.data.items.move(fromOffsets: $0, toOffset: $1) }
            }
            .scrollContentBackground(.hidden)
            HStack {
                Image(systemName: "plus").foregroundStyle(.secondary)
                TextField("Add item…", text: $newItem)
                    .textFieldStyle(.plain)
                    .onSubmit {
                        let t = newItem.trimmingCharacters(in: .whitespaces)
                        guard !t.isEmpty else { return }
                        store.data.items.append(CheckItem(text: t))
                        newItem = ""
                    }
            }
            .padding(8)
            .background(RoundedRectangle(cornerRadius: 6).fill(Color.primary.opacity(0.06)))
        }
    }
}

// MARK: - Popup panel shown above the Dock

final class PopupPanel: NSPanel {
    override var canBecomeKey: Bool { true }
}

final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    let store = NoteStore()
    var panel: PopupPanel!
    /// Set once the user drags the window somewhere; it then stays put and stays open.
    var customOrigin: NSPoint? {
        get { UserDefaults.standard.string(forKey: "origin").map { NSPointFromString($0) } }
        set { UserDefaults.standard.set(newValue.map { NSStringFromPoint($0) }, forKey: "origin") }
    }

    func applicationDidFinishLaunching(_ note: Notification) {
        panel = PopupPanel(contentRect: .zero,
                           styleMask: [.borderless, .resizable, .fullSizeContentView],
                           backing: .buffered, defer: false)
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.level = .popUpMenu
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.delegate = self
        let host = NSHostingView(rootView: NoteView(store: store,
                                                     onCollapse: { [weak self] in self?.hidePanel() },
                                                     onMoved: { [weak self] in self?.dragArmed = true },
                                                     onReset: { [weak self] in self?.resetPosition() },
                                                     onResized: { [weak self] in self?.didResize() },
                                                     onPreset: { [weak self] in self?.applyPreset($0) }))
        host.wantsLayer = true
        host.layer?.cornerRadius = 12
        host.layer?.masksToBounds = true
        host.sizingOptions = []
        panel.contentView = host
        panel.minSize = NSSize(width: 240, height: 200)
        let saved = UserDefaults.standard.string(forKey: "size").map { NSSizeFromString($0) }
        panel.setContentSize(saved ?? NSSize(width: 320, height: 380))

        // Edit menu so ⌘C / ⌘V / ⌘Z work
        let main = NSMenu()
        let appItem = NSMenuItem(); main.addItem(appItem)
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "Quit Docket", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu
        let editItem = NSMenuItem(); main.addItem(editItem)
        let edit = NSMenu(title: "Edit")
        edit.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        edit.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "Z")
        edit.addItem(.separator())
        edit.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editItem.submenu = edit
        NSApp.mainMenu = main

        showPanel()
    }

    // Clicking the Dock icon while running
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
        panel.isVisible ? hidePanel() : showPanel()
        return false
    }

    func applicationWillTerminate(_ notification: Notification) { store.save() }

    // Hide when clicking elsewhere, like a popover
    // Hide when the user switches to another app (clicks outside), like a popover.
    // Using app deactivation rather than key-window changes keeps it open while resizing/dragging.
    func applicationDidResignActive(_ notification: Notification) {
        if customOrigin == nil { hidePanel() }
    }

    /// True while the user is dragging via the grip; programmatic moves never set it.
    var dragArmed = false

    func windowDidMove(_ notification: Notification) {
        if dragArmed && panel.isVisible { didMove() }
    }

    func didMove() {
        customOrigin = panel.frame.origin
        panel.level = .floating
    }

    func didResize() {
        UserDefaults.standard.set(NSStringFromSize(panel.frame.size), forKey: "size")
        if customOrigin != nil { customOrigin = panel.frame.origin }
    }

    func applyPreset(_ size: NSSize) {
        dragArmed = false
        let old = panel.frame
        var frame: NSRect
        if customOrigin != nil {
            // moved window: keep the top-left corner fixed
            frame = NSRect(x: old.minX, y: old.maxY - size.height, width: size.width, height: size.height)
        } else {
            // popup above the Dock: keep the bottom edge, stay centred
            frame = NSRect(x: old.midX - size.width / 2, y: old.minY, width: size.width, height: size.height)
        }
        if let vf = (panel.screen ?? NSScreen.main)?.visibleFrame {
            frame.origin.x = min(max(frame.minX, vf.minX + 8), vf.maxX - frame.width - 8)
            frame.origin.y = min(max(frame.minY, vf.minY + 8), vf.maxY - frame.height - 8)
        }
        panel.setFrame(frame, display: true, animate: true)
        UserDefaults.standard.set(NSStringFromSize(size), forKey: "size")
        if customOrigin != nil { customOrigin = frame.origin }
    }

    func resetPosition() {
        dragArmed = false
        customOrigin = nil
        panel.level = .popUpMenu
        showPanel()
    }

    func showPanel() {
        dragArmed = false
        if let o = customOrigin,
           NSScreen.screens.contains(where: { $0.visibleFrame.intersects(NSRect(origin: o, size: panel.frame.size)) }) {
            panel.level = .floating
            panel.setFrameOrigin(o)
            NSApp.activate(ignoringOtherApps: true)
            panel.makeKeyAndOrderFront(nil)
            return
        }
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main!
        let vf = screen.visibleFrame, f = screen.frame
        let size = panel.frame.size
        var origin: NSPoint
        if vf.minX > f.minX {            // Dock on the left
            origin = NSPoint(x: vf.minX + 8, y: mouse.y - size.height / 2)
        } else if vf.maxX < f.maxX {     // Dock on the right
            origin = NSPoint(x: vf.maxX - size.width - 8, y: mouse.y - size.height / 2)
        } else {                         // Dock at the bottom (or hidden)
            origin = NSPoint(x: mouse.x - size.width / 2, y: vf.minY + 8)
        }
        origin.x = min(max(origin.x, vf.minX + 8), vf.maxX - size.width - 8)
        origin.y = min(max(origin.y, vf.minY + 8), vf.maxY - size.height - 8)
        panel.setFrameOrigin(origin)
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
    }

    func hidePanel() {
        store.save()
        panel.orderOut(nil)
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.regular)
app.run()
