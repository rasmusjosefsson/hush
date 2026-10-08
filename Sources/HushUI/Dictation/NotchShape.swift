import SwiftUI

/// Shape that continues the hardware notch: concave "ears" where it meets the
/// screen's top edge and convex rounded corners at the bottom.
public struct NotchShape: Shape {
    public var topRadius: CGFloat
    public var bottomRadius: CGFloat

    public init(topRadius: CGFloat = 6, bottomRadius: CGFloat = 14) {
        self.topRadius = topRadius
        self.bottomRadius = bottomRadius
    }

    public var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { .init(topRadius, bottomRadius) }
        set { topRadius = newValue.first; bottomRadius = newValue.second }
    }

    public func path(in rect: CGRect) -> Path {
        let top = min(topRadius, rect.width / 4)
        let bottom = min(bottomRadius, rect.height - top, (rect.width - 2 * top) / 2)
        var p = Path()
        p.move(to: CGPoint(x: rect.minX, y: rect.minY))
        p.addQuadCurve(to: CGPoint(x: rect.minX + top, y: rect.minY + top),
                       control: CGPoint(x: rect.minX + top, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.minX + top, y: rect.maxY - bottom))
        p.addQuadCurve(to: CGPoint(x: rect.minX + top + bottom, y: rect.maxY),
                       control: CGPoint(x: rect.minX + top, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.maxX - top - bottom, y: rect.maxY))
        p.addQuadCurve(to: CGPoint(x: rect.maxX - top, y: rect.maxY - bottom),
                       control: CGPoint(x: rect.maxX - top, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.maxX - top, y: rect.minY + top))
        p.addQuadCurve(to: CGPoint(x: rect.maxX, y: rect.minY),
                       control: CGPoint(x: rect.maxX - top, y: rect.minY))
        p.closeSubpath()
        return p
    }
}

/// Small keycap used for shortcut hints on the dark overlay ("Click or hold [fn] to dictate").
public struct OverlayKeycap: View {
    let symbol: String

    public init(_ symbol: String) {
        self.symbol = symbol
    }

    public var body: some View {
        Text(symbol)
            .font(.system(size: 11, weight: .semibold, design: .rounded))
            .foregroundStyle(DesignSystem.Colors.overlayPrimary)
            .padding(.horizontal, 6)
            .frame(minWidth: 20, minHeight: 18)
            .background(RoundedRectangle(cornerRadius: 5, style: .continuous).fill(DesignSystem.Colors.overlayFill))
            .overlay(RoundedRectangle(cornerRadius: 5, style: .continuous).strokeBorder(.white.opacity(0.14), lineWidth: 0.5))
    }
}

/// Circular overlay button (cancel / stop) with hover feedback driven by the controller's tooltip.
struct OverlayCircleButton<Label: View>: View {
    let tint: Color
    let isHovered: Bool
    let action: () -> Void
    @ViewBuilder let label: () -> Label

    var body: some View {
        Button(action: action) {
            label()
                .frame(width: 22, height: 22)
                .background(Circle().fill(tint.opacity(isHovered ? 1 : 0.85)))
                .scaleEffect(isHovered ? 1.08 : 1)
                .animation(DesignSystem.Animation.hoverTransition, value: isHovered)
        }
        .buttonStyle(.plain)
    }
}
