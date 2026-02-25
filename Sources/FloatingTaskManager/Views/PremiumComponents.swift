import SwiftUI

struct PremiumTheme {
    static let glassOpacity = 0.5
    static let glassReflection = Color.white.opacity(0.2)
    static let glassBorder = Color.white.opacity(0.15)
    static let shadowSmooth = Color.black.opacity(0.2)
    
    static func spring() -> Animation {
        .spring(response: 0.35, dampingFraction: 0.7, blendDuration: 0)
    }
}

struct GlassBackground: View {
    var cornerRadius: CGFloat = 12
    var showBorder: Bool = true
    
    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius)
            .fill(Color.white.opacity(0.85))
            .background(
                VisualEffectView(material: .popover, blendingMode: .behindWindow)
                    .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
            )
            .overlay(
                showBorder ?
                RoundedRectangle(cornerRadius: cornerRadius)
                    .stroke(PremiumTheme.glassBorder, lineWidth: 0.5)
                : nil
            )
    }
}

struct MeshGradientView: View {
    let baseColor: Color
    
    var body: some View {
        ZStack {
            baseColor
            
            // Subtle animated blobs (simulated mesh)
            TimelineView(.animation) { timeline in
                Canvas { context, size in
                    let t = timeline.date.timeIntervalSinceReferenceDate
                    
                    func drawBlob(at position: CGPoint, color: Color, size blobSize: CGSize, speed: Double) {
                        let offset = CGSize(
                            width: cos(t * speed) * 30,
                            height: sin(t * speed * 1.2) * 20
                        )
                        let rect = CGRect(
                            x: position.x + offset.width - blobSize.width / 2,
                            y: position.y + offset.height - blobSize.height / 2,
                            width: blobSize.width,
                            height: blobSize.height
                        )
                        context.fill(Path(ellipseIn: rect), with: .color(color))
                    }
                    
                    context.addFilter(.blur(radius: 40))
                    
                    drawBlob(at: CGPoint(x: size.width * 0.2, y: size.height * 0.3),
                             color: baseColor.opacity(0.6).mix(with: .white, by: 0.2),
                             size: CGSize(width: size.width * 0.8, height: size.height * 0.8),
                             speed: 0.5)
                    
                    drawBlob(at: CGPoint(x: size.width * 0.8, y: size.height * 0.7),
                             color: baseColor.opacity(0.4).mix(with: .blue, by: 0.2),
                             size: CGSize(width: size.width * 0.7, height: size.height * 0.6),
                             speed: 0.7)
                }
            }
        }
    }
}

extension Color {
    func mix(with other: Color, by amount: CGFloat) -> Color {
        // Simple approximation of color mixing
        let amount = max(0, min(1, amount))
        return Color(NSColor(self).blended(withFraction: amount, of: NSColor(other)) ?? NSColor(self))
    }
}

struct ModernCheckbox: View {
    @Binding var isChecked: Bool
    let color: Color
    
    var body: some View {
        ZStack {
            Circle()
                .stroke(isChecked ? color : Color.secondary.opacity(0.4), lineWidth: 1.5)
                .frame(width: 18, height: 18)
            
            if isChecked {
                Circle()
                    .fill(color)
                    .frame(width: 12, height: 12)
                    .transition(.scale.combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.6), value: isChecked)
        .contentShape(Circle())
        .onTapGesture {
            isChecked.toggle()
        }
    }
}

struct PremiumButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.94 : 1.0)
            .animation(PremiumTheme.spring(), value: configuration.isPressed)
    }
}

// MARK: - Visual Effect

struct VisualEffectView: NSViewRepresentable {
    let material: NSVisualEffectView.Material
    let blendingMode: NSVisualEffectView.BlendingMode

    class DraggableVisualEffectView: NSVisualEffectView {
        override var mouseDownCanMoveWindow: Bool { return true }
    }

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = DraggableVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = .active
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = blendingMode
    }
}
