import SwiftUI

/// Popover-like shape: rounded rectangle with a triangular arrow on one edge.
struct PopoverBubbleShape: Shape {
    var arrowEdge: Edge
    var cornerRadius: CGFloat = 16
    var arrowWidth: CGFloat = 16
    var arrowHeight: CGFloat = 9

    func path(in rect: CGRect) -> Path {
        let body = bodyRect(in: rect)
        let radius = min(cornerRadius, min(body.width, body.height) / 2)
        let arrow = arrowPoints(in: rect, body: body)

        var path = Path()
        // Start at top-left corner, after the leading arc, walking clockwise.
        path.move(to: CGPoint(x: body.minX + radius, y: body.minY))

        // Top edge (+ optional top arrow)
        if arrowEdge == .top {
            path.addLine(to: CGPoint(x: arrow[0].x, y: body.minY))
            path.addLine(to: arrow[1])
            path.addLine(to: CGPoint(x: arrow[2].x, y: body.minY))
        }
        path.addLine(to: CGPoint(x: body.maxX - radius, y: body.minY))
        path.addArc(
            center: CGPoint(x: body.maxX - radius, y: body.minY + radius),
            radius: radius,
            startAngle: .degrees(-90),
            endAngle: .degrees(0),
            clockwise: false
        )

        // Trailing edge (+ optional trailing arrow)
        if arrowEdge == .trailing {
            path.addLine(to: CGPoint(x: body.maxX, y: arrow[0].y))
            path.addLine(to: arrow[1])
            path.addLine(to: CGPoint(x: body.maxX, y: arrow[2].y))
        }
        path.addLine(to: CGPoint(x: body.maxX, y: body.maxY - radius))
        path.addArc(
            center: CGPoint(x: body.maxX - radius, y: body.maxY - radius),
            radius: radius,
            startAngle: .degrees(0),
            endAngle: .degrees(90),
            clockwise: false
        )

        // Bottom edge (+ optional bottom arrow)
        if arrowEdge == .bottom {
            path.addLine(to: CGPoint(x: arrow[2].x, y: body.maxY))
            path.addLine(to: arrow[1])
            path.addLine(to: CGPoint(x: arrow[0].x, y: body.maxY))
        }
        path.addLine(to: CGPoint(x: body.minX + radius, y: body.maxY))
        path.addArc(
            center: CGPoint(x: body.minX + radius, y: body.maxY - radius),
            radius: radius,
            startAngle: .degrees(90),
            endAngle: .degrees(180),
            clockwise: false
        )

        // Leading edge (+ optional leading arrow)
        if arrowEdge == .leading {
            path.addLine(to: CGPoint(x: body.minX, y: arrow[2].y))
            path.addLine(to: arrow[1])
            path.addLine(to: CGPoint(x: body.minX, y: arrow[0].y))
        }
        path.addLine(to: CGPoint(x: body.minX, y: body.minY + radius))
        path.addArc(
            center: CGPoint(x: body.minX + radius, y: body.minY + radius),
            radius: radius,
            startAngle: .degrees(180),
            endAngle: .degrees(270),
            clockwise: false
        )

        path.closeSubpath()
        return path
    }

    private func bodyRect(in rect: CGRect) -> CGRect {
        switch arrowEdge {
        case .top:
            CGRect(
                x: rect.minX,
                y: rect.minY + arrowHeight,
                width: rect.width,
                height: max(0, rect.height - arrowHeight)
            )
        case .bottom:
            CGRect(
                x: rect.minX,
                y: rect.minY,
                width: rect.width,
                height: max(0, rect.height - arrowHeight)
            )
        case .leading:
            CGRect(
                x: rect.minX + arrowHeight,
                y: rect.minY,
                width: max(0, rect.width - arrowHeight),
                height: rect.height
            )
        case .trailing:
            CGRect(
                x: rect.minX,
                y: rect.minY,
                width: max(0, rect.width - arrowHeight),
                height: rect.height
            )
        }
    }

    /// Three points: baseStart, tip, baseEnd along the walk direction of the edge.
    private func arrowPoints(in rect: CGRect, body: CGRect) -> [CGPoint] {
        let half = arrowWidth / 2
        switch arrowEdge {
        case .top:
            let midX = body.midX
            return [
                CGPoint(x: midX - half, y: body.minY),
                CGPoint(x: midX, y: rect.minY),
                CGPoint(x: midX + half, y: body.minY),
            ]
        case .bottom:
            let midX = body.midX
            return [
                CGPoint(x: midX - half, y: body.maxY),
                CGPoint(x: midX, y: rect.maxY),
                CGPoint(x: midX + half, y: body.maxY),
            ]
        case .leading:
            let midY = body.midY
            return [
                CGPoint(x: body.minX, y: midY - half),
                CGPoint(x: rect.minX, y: midY),
                CGPoint(x: body.minX, y: midY + half),
            ]
        case .trailing:
            let midY = body.midY
            return [
                CGPoint(x: body.maxX, y: midY - half),
                CGPoint(x: rect.maxX, y: midY),
                CGPoint(x: body.maxX, y: midY + half),
            ]
        }
    }
}
