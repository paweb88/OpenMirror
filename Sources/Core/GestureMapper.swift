import CoreGraphics
import Foundation

/// A gesture expressed in device points, ready to send to WebDriverAgent.
enum PhoneGesture: Equatable {
    case tap(x: Double, y: Double)
    case hold(x: Double, y: Double, seconds: Double)
    case drag(fromX: Double, fromY: Double, toX: Double, toY: Double, pressSeconds: Double)
}

/// Converts mouse input on the mirrored view (normalized 0…1 coordinates) into phone gestures.
enum GestureMapper {
    static let tapSlop: Double = 0.012      // max movement (fraction of view width) still counted as a tap
    static let holdThreshold: Double = 0.45 // seconds
    static let slowDragDelay: Double = 0.5  // pause before moving → long press first (moves icons)

    static func toPoints(_ normalized: CGPoint, in size: ScreenSize) -> (x: Double, y: Double) {
        let x = min(max(Double(normalized.x), 0), 1) * size.width
        let y = min(max(Double(normalized.y), 0), 1) * size.height
        return (x.rounded(), y.rounded())
    }

    /// - Parameters:
    ///   - start/end: normalized positions of mouse down / up.
    ///   - heldSeconds: time between mouse down and mouse up.
    ///   - delayBeforeMove: time between mouse down and the first real movement (nil if it never moved).
    static func gesture(start: CGPoint, end: CGPoint, heldSeconds: Double,
                        delayBeforeMove: Double?, size: ScreenSize) -> PhoneGesture {
        let a = toPoints(start, in: size)
        let b = toPoints(end, in: size)
        let moved = hypot(Double(end.x - start.x), Double(end.y - start.y))
        if moved < tapSlop {
            return heldSeconds < holdThreshold ? .tap(x: a.x, y: a.y)
                                               : .hold(x: a.x, y: a.y, seconds: heldSeconds)
        }
        let press = (delayBeforeMove ?? 0) >= slowDragDelay ? 0.6 : 0.05
        return .drag(fromX: a.x, fromY: a.y, toX: b.x, toY: b.y, pressSeconds: press)
    }

    /// Trackpad scroll → swipe starting at the scroll position, following the fingers (natural scrolling).
    static func scrollSwipe(at origin: CGPoint, normalizedDelta: CGVector, size: ScreenSize) -> PhoneGesture? {
        guard hypot(Double(normalizedDelta.dx), Double(normalizedDelta.dy)) > tapSlop else { return nil }
        let a = toPoints(origin, in: size)
        let b = toPoints(CGPoint(x: origin.x + normalizedDelta.dx, y: origin.y + normalizedDelta.dy), in: size)
        return .drag(fromX: a.x, fromY: a.y, toX: b.x, toY: b.y, pressSeconds: 0.05)
    }

    /// Swipe up from the bottom edge and pause – opens the app switcher.
    static func appSwitcher(in size: ScreenSize) -> PhoneGesture {
        let x = (size.width / 2).rounded()
        return .drag(fromX: x, fromY: size.height - 2, toX: x, toY: (size.height * 0.6).rounded(), pressSeconds: 0.6)
    }

    /// Maps a key press to text WDA understands (\u{8} = backspace).
    static func text(forKeyCode keyCode: UInt16, characters: String?) -> String? {
        switch keyCode {
        case 51: return "\u{8}"
        case 36, 76: return "\n"
        case 48: return "\t"
        default:
            guard let characters, !characters.isEmpty,
                  characters.unicodeScalars.allSatisfy({ !CharacterSet.controlCharacters.contains($0) && $0.value < 0xF700 })
            else { return nil }
            return characters
        }
    }
}
