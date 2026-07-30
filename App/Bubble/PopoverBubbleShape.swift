import SwiftUI

/// Popover-like shape: rounded rectangle with a small arrow that blends into a flat edge.
struct PopoverBubbleShape: Shape {
    var arrowEdge: Edge
    var cornerRadius: CGFloat = 12
    var arrowWidth: CGFloat = 10
    var arrowHeight: CGFloat = 6

    func path(in rect: CGRect) -> Path {
        let body = bodyRect(in: rect)
        let radius = resolvedCornerRadius(for: body)
        let arrow = arrowGeometry(in: rect, body: body)

        var path = Path()
        path.move(to: CGPoint(x: body.minX + radius, y: body.minY))

        let drawsArrow = arrowWidth > 0 && arrowHeight > 0

        // Top edge
        if drawsArrow, arrowEdge == .top {
            path.addLine(to: arrow.baseStart)
            addCurvedArrow(to: &path, from: arrow.baseStart, tip: arrow.tip, to: arrow.baseEnd)
        }
        path.addLine(to: CGPoint(x: body.maxX - radius, y: body.minY))
        path.addArc(
            center: CGPoint(x: body.maxX - radius, y: body.minY + radius),
            radius: radius,
            startAngle: .degrees(-90),
            endAngle: .degrees(0),
            clockwise: false
        )

        // Trailing edge
        if drawsArrow, arrowEdge == .trailing {
            path.addLine(to: arrow.baseStart)
            addCurvedArrow(to: &path, from: arrow.baseStart, tip: arrow.tip, to: arrow.baseEnd)
        }
        path.addLine(to: CGPoint(x: body.maxX, y: body.maxY - radius))
        path.addArc(
            center: CGPoint(x: body.maxX - radius, y: body.maxY - radius),
            radius: radius,
            startAngle: .degrees(0),
            endAngle: .degrees(90),
            clockwise: false
        )

        // Bottom edge (walk right → left)
        if drawsArrow, arrowEdge == .bottom {
            path.addLine(to: arrow.baseEnd)
            addCurvedArrow(to: &path, from: arrow.baseEnd, tip: arrow.tip, to: arrow.baseStart)
        }
        path.addLine(to: CGPoint(x: body.minX + radius, y: body.maxY))
        path.addArc(
            center: CGPoint(x: body.minX + radius, y: body.maxY - radius),
            radius: radius,
            startAngle: .degrees(90),
            endAngle: .degrees(180),
            clockwise: false
        )

        // Leading edge (walk bottom → top)
        if drawsArrow, arrowEdge == .leading {
            path.addLine(to: arrow.baseEnd)
            addCurvedArrow(to: &path, from: arrow.baseEnd, tip: arrow.tip, to: arrow.baseStart)
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

    /// Keep a flat segment long enough for the arrow so it doesn't sit on a corner arc.
    private func resolvedCornerRadius(for body: CGRect) -> CGFloat {
        let edgeLength: CGFloat = switch arrowEdge {
        case .top, .bottom: body.width
        case .leading, .trailing: body.height
        }
        guard arrowWidth > 0, arrowHeight > 0 else {
            return min(cornerRadius, min(body.width, body.height) / 2)
        }
        let reservedFlat = arrowWidth + 8
        let maxRadius = max(0, (edgeLength - reservedFlat) / 2)
        return min(cornerRadius, maxRadius)
    }

    private struct ArrowGeometry {
        var baseStart: CGPoint
        var tip: CGPoint
        var baseEnd: CGPoint
    }

    private func arrowGeometry(in rect: CGRect, body: CGRect) -> ArrowGeometry {
        let half = arrowWidth / 2
        switch arrowEdge {
        case .top:
            let midX = body.midX
            return ArrowGeometry(
                baseStart: CGPoint(x: midX - half, y: body.minY),
                tip: CGPoint(x: midX, y: rect.minY),
                baseEnd: CGPoint(x: midX + half, y: body.minY)
            )
        case .bottom:
            let midX = body.midX
            return ArrowGeometry(
                baseStart: CGPoint(x: midX - half, y: body.maxY),
                tip: CGPoint(x: midX, y: rect.maxY),
                baseEnd: CGPoint(x: midX + half, y: body.maxY)
            )
        case .leading:
            let midY = body.midY
            return ArrowGeometry(
                baseStart: CGPoint(x: body.minX, y: midY - half),
                tip: CGPoint(x: rect.minX, y: midY),
                baseEnd: CGPoint(x: body.minX, y: midY + half)
            )
        case .trailing:
            let midY = body.midY
            return ArrowGeometry(
                baseStart: CGPoint(x: body.maxX, y: midY - half),
                tip: CGPoint(x: rect.maxX, y: midY),
                baseEnd: CGPoint(x: body.maxX, y: midY + half)
            )
        }
    }

    /// Soft arrow sides so Liquid Glass doesn't render a detached hard triangle.
    private func addCurvedArrow(
        to path: inout Path,
        from start: CGPoint,
        tip: CGPoint,
        to end: CGPoint
    ) {
        let controlInset: CGFloat = arrowHeight * 0.35
        switch arrowEdge {
        case .top:
            path.addQuadCurve(
                to: tip,
                control: CGPoint(x: start.x + (tip.x - start.x) * 0.55, y: start.y - controlInset)
            )
            path.addQuadCurve(
                to: end,
                control: CGPoint(x: end.x + (tip.x - end.x) * 0.55, y: end.y - controlInset)
            )
        case .bottom:
            path.addQuadCurve(
                to: tip,
                control: CGPoint(x: start.x + (tip.x - start.x) * 0.55, y: start.y + controlInset)
            )
            path.addQuadCurve(
                to: end,
                control: CGPoint(x: end.x + (tip.x - end.x) * 0.55, y: end.y + controlInset)
            )
        case .leading:
            path.addQuadCurve(
                to: tip,
                control: CGPoint(x: start.x - controlInset, y: start.y + (tip.y - start.y) * 0.55)
            )
            path.addQuadCurve(
                to: end,
                control: CGPoint(x: end.x - controlInset, y: end.y + (tip.y - end.y) * 0.55)
            )
        case .trailing:
            path.addQuadCurve(
                to: tip,
                control: CGPoint(x: start.x + controlInset, y: start.y + (tip.y - start.y) * 0.55)
            )
            path.addQuadCurve(
                to: end,
                control: CGPoint(x: end.x + controlInset, y: end.y + (tip.y - end.y) * 0.55)
            )
        }
    }
}
