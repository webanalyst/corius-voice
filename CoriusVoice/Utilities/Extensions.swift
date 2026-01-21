import Foundation
import SwiftUI
import AppKit

// MARK: - Date Extensions

extension Date {
    var relativeString: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: self, relativeTo: Date())
    }

    var formattedFull: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .full
        formatter.timeStyle = .medium
        return formatter.string(from: self)
    }

    var formattedShort: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter.string(from: self)
    }
}

// MARK: - String Extensions

extension String {
    var trimmed: String {
        trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var isBlank: Bool {
        trimmed.isEmpty
    }

    func truncated(to length: Int, trailing: String = "...") -> String {
        if count <= length {
            return self
        }
        return String(prefix(length)) + trailing
    }

    var wordCount: Int {
        let words = components(separatedBy: .whitespacesAndNewlines)
        return words.filter { !$0.isEmpty }.count
    }

    var characterCount: Int {
        count
    }
}

// MARK: - View Extensions

extension View {
    func cornerRadius(_ radius: CGFloat, corners: RectCorner) -> some View {
        clipShape(RoundedCorner(radius: radius, corners: corners))
    }

    @ViewBuilder
    func `if`<Transform: View>(_ condition: Bool, transform: (Self) -> Transform) -> some View {
        if condition {
            transform(self)
        } else {
            self
        }
    }
}

struct RoundedCorner: Shape {
    var radius: CGFloat = .infinity
    var corners: RectCorner = .allCorners

    func path(in rect: CGRect) -> Path {
        let path = NSBezierPath(
            roundedRect: rect,
            byRoundingCorners: corners,
            cornerRadii: CGSize(width: radius, height: radius)
        )
        return Path(path.cgPath)
    }
}

struct RectCorner: OptionSet {
    let rawValue: Int

    static let topLeft = RectCorner(rawValue: 1 << 0)
    static let topRight = RectCorner(rawValue: 1 << 1)
    static let bottomLeft = RectCorner(rawValue: 1 << 2)
    static let bottomRight = RectCorner(rawValue: 1 << 3)

    static let allCorners: RectCorner = [.topLeft, .topRight, .bottomLeft, .bottomRight]
}

extension NSBezierPath {
    convenience init(roundedRect rect: CGRect, byRoundingCorners corners: RectCorner, cornerRadii: CGSize) {
        self.init()

        let topLeft = corners.contains(.topLeft)
        let topRight = corners.contains(.topRight)
        let bottomLeft = corners.contains(.bottomLeft)
        let bottomRight = corners.contains(.bottomRight)

        let radius = cornerRadii.width

        // Start at top-left
        if topLeft {
            move(to: CGPoint(x: rect.minX + radius, y: rect.minY))
        } else {
            move(to: CGPoint(x: rect.minX, y: rect.minY))
        }

        // Top edge and top-right corner
        if topRight {
            line(to: CGPoint(x: rect.maxX - radius, y: rect.minY))
            appendArc(withCenter: CGPoint(x: rect.maxX - radius, y: rect.minY + radius),
                     radius: radius,
                     startAngle: -90,
                     endAngle: 0,
                     clockwise: false)
        } else {
            line(to: CGPoint(x: rect.maxX, y: rect.minY))
        }

        // Right edge and bottom-right corner
        if bottomRight {
            line(to: CGPoint(x: rect.maxX, y: rect.maxY - radius))
            appendArc(withCenter: CGPoint(x: rect.maxX - radius, y: rect.maxY - radius),
                     radius: radius,
                     startAngle: 0,
                     endAngle: 90,
                     clockwise: false)
        } else {
            line(to: CGPoint(x: rect.maxX, y: rect.maxY))
        }

        // Bottom edge and bottom-left corner
        if bottomLeft {
            line(to: CGPoint(x: rect.minX + radius, y: rect.maxY))
            appendArc(withCenter: CGPoint(x: rect.minX + radius, y: rect.maxY - radius),
                     radius: radius,
                     startAngle: 90,
                     endAngle: 180,
                     clockwise: false)
        } else {
            line(to: CGPoint(x: rect.minX, y: rect.maxY))
        }

        // Left edge and top-left corner
        if topLeft {
            line(to: CGPoint(x: rect.minX, y: rect.minY + radius))
            appendArc(withCenter: CGPoint(x: rect.minX + radius, y: rect.minY + radius),
                     radius: radius,
                     startAngle: 180,
                     endAngle: 270,
                     clockwise: false)
        } else {
            line(to: CGPoint(x: rect.minX, y: rect.minY))
        }

        close()
    }

    var cgPath: CGPath {
        let path = CGMutablePath()
        var points = [CGPoint](repeating: .zero, count: 3)

        for i in 0..<elementCount {
            let type = element(at: i, associatedPoints: &points)

            switch type {
            case .moveTo:
                path.move(to: points[0])
            case .lineTo:
                path.addLine(to: points[0])
            case .curveTo, .cubicCurveTo:
                path.addCurve(to: points[2], control1: points[0], control2: points[1])
            case .closePath:
                path.closeSubpath()
            case .quadraticCurveTo:
                path.addQuadCurve(to: points[1], control: points[0])
            @unknown default:
                break
            }
        }

        return path
    }
}

// MARK: - TimeInterval Extensions

extension TimeInterval {
    var formattedDuration: String {
        let minutes = Int(self) / 60
        let seconds = Int(self) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }

    var formattedDurationLong: String {
        let hours = Int(self) / 3600
        let minutes = (Int(self) % 3600) / 60
        let seconds = Int(self) % 60

        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        }
        return String(format: "%d:%02d", minutes, seconds)
    }
}

// MARK: - Array Extensions

extension Array where Element: Identifiable {
    mutating func update(_ element: Element) {
        if let index = firstIndex(where: { $0.id == element.id }) {
            self[index] = element
        }
    }

    mutating func remove(_ element: Element) {
        removeAll { $0.id == element.id }
    }
}
