import Cocoa

/// Floating status pill.
///
/// Non-activating and never key: if this window takes focus, the paste lands
/// here instead of in the app the user was typing in.
final class HUD {
    enum State {
        case listening, locked, transcribing, message(String)
    }

    private let panel: NSPanel
    private let label = NSTextField(labelWithString: "")
    private let dot = NSView()
    private let meter = NSView()
    private var meterWidth: NSLayoutConstraint!
    private var pulse: Timer?
    /// A delayed hide belongs to the flash that scheduled it. Once the next
    /// utterance shows the pill again, that older hide must not fire — it would
    /// order out the panel a session that is still running just put on screen.
    private var pendingHide: DispatchWorkItem?

    init() {
        panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 210, height: 44),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        // Above the shield a fullscreen Space puts over the status-bar level.
        // At .statusBar the pill renders behind it and the user sees nothing.
        panel.level = .popUpMenu
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.ignoresMouseEvents = true
        // No .stationary: it pins the panel to the Space it was born on, which
        // is the opposite of .canJoinAllSpaces. With it set, dictating into a
        // fullscreen app left the pill behind on the desktop Space — ordered
        // front, on screen, and occluded by the whole fullscreen window.
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.hidesOnDeactivate = false

        let blur = NSVisualEffectView()
        blur.material = .hudWindow
        blur.blendingMode = .behindWindow
        blur.state = .active
        blur.wantsLayer = true
        blur.layer?.cornerRadius = 22
        blur.layer?.masksToBounds = true
        blur.translatesAutoresizingMaskIntoConstraints = false

        dot.wantsLayer = true
        dot.layer?.cornerRadius = 5
        dot.layer?.backgroundColor = NSColor.systemRed.cgColor
        dot.translatesAutoresizingMaskIntoConstraints = false

        meter.wantsLayer = true
        meter.layer?.cornerRadius = 2
        meter.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.85).cgColor
        meter.translatesAutoresizingMaskIntoConstraints = false

        label.font = .systemFont(ofSize: 13, weight: .medium)
        label.textColor = .white
        label.translatesAutoresizingMaskIntoConstraints = false
        label.lineBreakMode = .byTruncatingTail

        let content = NSView()
        content.addSubview(blur)
        blur.addSubview(dot)
        blur.addSubview(label)
        blur.addSubview(meter)
        panel.contentView = content
        blur.frame = content.bounds

        meterWidth = meter.widthAnchor.constraint(equalToConstant: 2)
        NSLayoutConstraint.activate([
            blur.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            blur.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            blur.topAnchor.constraint(equalTo: content.topAnchor),
            blur.bottomAnchor.constraint(equalTo: content.bottomAnchor),

            dot.leadingAnchor.constraint(equalTo: blur.leadingAnchor, constant: 16),
            dot.centerYAnchor.constraint(equalTo: blur.centerYAnchor),
            dot.widthAnchor.constraint(equalToConstant: 10),
            dot.heightAnchor.constraint(equalToConstant: 10),

            label.leadingAnchor.constraint(equalTo: dot.trailingAnchor, constant: 10),
            label.centerYAnchor.constraint(equalTo: blur.centerYAnchor),
            label.trailingAnchor.constraint(lessThanOrEqualTo: blur.trailingAnchor, constant: -16),

            meter.leadingAnchor.constraint(equalTo: dot.trailingAnchor, constant: 10),
            meter.bottomAnchor.constraint(equalTo: blur.bottomAnchor, constant: -8),
            meter.heightAnchor.constraint(equalToConstant: 3),
            meterWidth,
        ])
    }

    /// `canBecomeKey` is false by default for a borderless panel, but a
    /// nonactivating panel will still take key if asked. Never order front
    /// with makeKey.
    func show(_ state: State, at position: HUDPosition = .bottom) {
        guard position != .hidden else { return }
        cancelPendingHide()
        switch state {
        case .listening:
            label.stringValue = "Listening…"
            dot.layer?.backgroundColor = NSColor.systemRed.cgColor
            startPulse()
        case .locked:
            label.stringValue = "Listening — locked"
            dot.layer?.backgroundColor = NSColor.systemRed.cgColor
            startPulse()
        case .transcribing:
            label.stringValue = "Transcribing…"
            dot.layer?.backgroundColor = NSColor.systemYellow.cgColor
            stopPulse()
        case .message(let m):
            label.stringValue = m
            dot.layer?.backgroundColor = NSColor.systemGray.cgColor
            stopPulse()
        }
        place(position)
        panel.orderFrontRegardless()
        // Occlusion is reported asynchronously, so a read taken here is the
        // previous state — always "hidden" for a window just ordered front.
        // The settled sample a moment later is the one worth believing.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            self?.logState("show")
        }
    }

    /// The pill is the one part of this app with no trace in the log: when it
    /// fails to appear, nothing distinguishes "never asked to show" from
    /// "shown somewhere off screen" from "shown and drawn empty". These three
    /// fields separate them — a caller bug logs nothing at all, a placement bug
    /// logs an off-screen frame, and an occlusion bug logs visible=true with
    /// occluded=true.
    private func logState(_ what: String) {
        let f = panel.frame
        let screen = NSScreen.main.map { "\(Int($0.frame.width))x\(Int($0.frame.height))" } ?? "nil"
        Log.write(String(format: "hud     %@ visible=%@ occluded=%@ frame=%.0f,%.0f %.0fx%.0f screen=%@ above=[%@]",
                         what,
                         panel.isVisible ? "true" : "false",
                         panel.occlusionState.contains(.visible) ? "false" : "true",
                         f.origin.x, f.origin.y, f.size.width, f.size.height,
                         screen, windowsAbove()))
    }

    /// Names whatever the window server has stacked on top of the pill.
    /// "Occluded" alone says the pill lost; this says to whom.
    private func windowsAbove() -> String {
        let info = CGWindowListCopyWindowInfo(
            [.optionOnScreenAboveWindow, .excludeDesktopElements],
            CGWindowID(panel.windowNumber)) as? [[String: Any]] ?? []
        let names = info.prefix(6).map { w -> String in
            let owner = w[kCGWindowOwnerName as String] as? String ?? "?"
            let layer = w[kCGWindowLayer as String] as? Int ?? 0
            return "\(owner):\(layer)"
        }
        return names.joined(separator: " ")
    }

    /// Live partial transcript, so you can see it keeping up with you.
    func setPartial(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        // Tail of the text: the newest words are the interesting ones.
        let tail = trimmed.count > 46 ? "…" + String(trimmed.suffix(46)) : trimmed
        label.stringValue = tail
    }

    func setLevel(_ rms: Float) {
        // rms is tiny for speech; scale so normal talking fills the bar.
        let norm = min(1.0, Double(rms) * 22.0)
        meterWidth.constant = 2 + norm * 150
    }

    func hide(after delay: TimeInterval = 0) {
        stopPulse()
        // A newer hide supersedes an older one too: a 1.6s flash followed by a
        // 1.0s one must not be torn down on the first timer's schedule.
        cancelPendingHide()
        guard delay > 0 else { return panel.orderOut(nil) }
        let work = DispatchWorkItem { [weak self] in
            self?.pendingHide = nil
            self?.panel.orderOut(nil)
            self?.logState("hide fired")
        }
        pendingHide = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    private func cancelPendingHide() {
        guard let p = pendingHide else { return }
        p.cancel()
        pendingHide = nil
        Log.write("hud     hide cancelled")
    }

    private func startPulse() {
        stopPulse()
        var up = false
        pulse = Timer.scheduledTimer(withTimeInterval: 0.45, repeats: true) { [weak self] _ in
            guard let self else { return }
            up.toggle()
            NSAnimationContext.runAnimationGroup { c in
                c.duration = 0.4
                self.dot.animator().alphaValue = up ? 0.35 : 1.0
            }
        }
    }

    private func stopPulse() {
        pulse?.invalidate(); pulse = nil
        dot.alphaValue = 1.0
        meterWidth.constant = 2
    }

    private func place(_ position: HUDPosition) {
        guard let screen = NSScreen.main else { return }
        let f = screen.visibleFrame
        let size = panel.frame.size
        let x = f.midX - size.width / 2
        let y: CGFloat
        switch position {
        case .bottom, .hidden: y = f.minY + 90
        case .top:             y = f.maxY - size.height - 40
        case .center:          y = f.midY - size.height / 2
        }
        panel.setFrameOrigin(NSPoint(x: x, y: y))
    }
}
