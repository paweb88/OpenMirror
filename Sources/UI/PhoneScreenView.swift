import AppKit
import SwiftUI

/// Shows the mirrored frame and turns mouse, trackpad and keyboard input into phone gestures.
struct PhoneScreenView: NSViewRepresentable {
    let image: NSImage?
    var takesKeyFocus = true
    let onGesture: (InputEvent) -> Void

    enum InputEvent {
        case pointer(start: CGPoint, end: CGPoint, heldSeconds: Double, delayBeforeMove: Double?)
        case scroll(origin: CGPoint, delta: CGVector)
        case text(String)
        case paste
    }

    func makeNSView(context: Context) -> InputView {
        let view = InputView()
        view.onEvent = onGesture
        return view
    }

    func updateNSView(_ view: InputView, context: Context) {
        view.onEvent = onGesture
        view.layer?.contents = image
        if takesKeyFocus, let window = view.window, window.firstResponder !== view {
            DispatchQueue.main.async { window.makeFirstResponder(view) }
        }
    }

    final class InputView: NSView {
        var onEvent: ((InputEvent) -> Void)?
        private var downPoint: CGPoint?
        private var downTime: Date?
        private var firstMoveTime: Date?
        private var scrollOrigin: CGPoint?
        private var scrollDelta = CGVector.zero

        override init(frame: NSRect) {
            super.init(frame: frame)
            wantsLayer = true
            layer?.contentsGravity = .resize
            layer?.backgroundColor = NSColor.black.cgColor
        }

        required init?(coder: NSCoder) { nil }

        override var acceptsFirstResponder: Bool { true }
        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

        /// Normalized 0…1 position, origin at top-left like the phone.
        private func normalized(_ event: NSEvent) -> CGPoint {
            let point = convert(event.locationInWindow, from: nil)
            guard bounds.width > 0, bounds.height > 0 else { return .zero }
            return CGPoint(x: point.x / bounds.width, y: 1 - point.y / bounds.height)
        }

        override func mouseDown(with event: NSEvent) {
            window?.makeFirstResponder(self)
            downPoint = normalized(event)
            downTime = Date()
            firstMoveTime = nil
        }

        override func mouseDragged(with event: NSEvent) {
            guard let start = downPoint, firstMoveTime == nil else { return }
            let now = normalized(event)
            if hypot(now.x - start.x, now.y - start.y) >= GestureMapper.tapSlop { firstMoveTime = Date() }
        }

        override func mouseUp(with event: NSEvent) {
            guard let start = downPoint, let downTime else { return }
            let delay = firstMoveTime.map { $0.timeIntervalSince(downTime) }
            onEvent?(.pointer(start: start, end: normalized(event),
                              heldSeconds: Date().timeIntervalSince(downTime), delayBeforeMove: delay))
            downPoint = nil
        }

        override func scrollWheel(with event: NSEvent) {
            guard event.hasPreciseScrollingDeltas else { return }
            if event.phase == .began || scrollOrigin == nil {
                scrollOrigin = normalized(event)
                scrollDelta = .zero
            }
            if event.phase == .changed || event.phase == .began {
                scrollDelta.dx += event.scrollingDeltaX / max(bounds.width, 1)
                // natural scrolling: deltas follow the fingers; phone Y grows downwards like ours
                scrollDelta.dy += event.scrollingDeltaY / max(bounds.height, 1)
            }
            if event.phase == .ended || event.phase == .cancelled {
                if let origin = scrollOrigin { onEvent?(.scroll(origin: origin, delta: scrollDelta)) }
                scrollOrigin = nil
            }
        }

        override func keyDown(with event: NSEvent) {
            if event.modifierFlags.contains(.command) {
                if event.charactersIgnoringModifiers == "v" { onEvent?(.paste) } else { super.keyDown(with: event) }
                return
            }
            if let text = GestureMapper.text(forKeyCode: event.keyCode, characters: event.characters) {
                onEvent?(.text(text))
            }
        }
    }
}
