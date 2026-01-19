//
//  GlassEffect.swift
//  KYC
//
//  Implementación de efectos glass para iOS 17+
//  Simula el estilo "Liquid Glass" con materiales nativos
//

import SwiftUI

// MARK: - Glass Effect Style

struct GlassEffectStyle {
    var material: Material
    var tintColor: Color?
    var isInteractive: Bool

    static let regular = GlassEffectStyle(material: .ultraThinMaterial, tintColor: nil, isInteractive: false)
    static let clear = GlassEffectStyle(material: .ultraThinMaterial, tintColor: .clear, isInteractive: false)

    func tint(_ color: Color) -> GlassEffectStyle {
        var copy = self
        copy.tintColor = color
        return copy
    }

    func interactive() -> GlassEffectStyle {
        var copy = self
        copy.isInteractive = true
        return copy
    }
}

// MARK: - Glass Effect Modifiers

private struct GlassEffectCircleModifier: ViewModifier {
    let style: GlassEffectStyle

    func body(content: Content) -> some View {
        content
            .background {
                ZStack {
                    Circle()
                        .fill(style.material)
                    if let tintColor = style.tintColor {
                        Circle()
                            .fill(tintColor)
                    }
                    Circle()
                        .strokeBorder(
                            LinearGradient(
                                colors: [.white.opacity(0.3), .white.opacity(0.1)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 0.5
                        )
                }
            }
            .contentShape(Circle())
    }
}

private struct GlassEffectCapsuleModifier: ViewModifier {
    let style: GlassEffectStyle

    func body(content: Content) -> some View {
        content
            .background {
                ZStack {
                    Capsule()
                        .fill(style.material)
                    if let tintColor = style.tintColor {
                        Capsule()
                            .fill(tintColor)
                    }
                    Capsule()
                        .strokeBorder(
                            LinearGradient(
                                colors: [.white.opacity(0.3), .white.opacity(0.1)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 0.5
                        )
                }
            }
            .contentShape(Capsule())
    }
}

private struct GlassEffectRoundedRectModifier: ViewModifier {
    let style: GlassEffectStyle
    let cornerRadius: CGFloat

    func body(content: Content) -> some View {
        content
            .background {
                ZStack {
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .fill(style.material)
                    if let tintColor = style.tintColor {
                        RoundedRectangle(cornerRadius: cornerRadius)
                            .fill(tintColor)
                    }
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .strokeBorder(
                            LinearGradient(
                                colors: [.white.opacity(0.3), .white.opacity(0.1)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 0.5
                        )
                }
            }
            .contentShape(RoundedRectangle(cornerRadius: cornerRadius))
    }
}

// MARK: - Shape Type Enum

enum GlassShape {
    case circle
    case capsule
}

// MARK: - View Extension for Glass Effect

extension View {
    /// Glass effect with circle or capsule shape
    func glassEffect(_ style: GlassEffectStyle, in shape: GlassShape) -> some View {
        Group {
            switch shape {
            case .circle:
                self.modifier(GlassEffectCircleModifier(style: style))
            case .capsule:
                self.modifier(GlassEffectCapsuleModifier(style: style))
            }
        }
    }

    /// Glass effect with SwiftUI RoundedRectangle
    /// Note: Uses default corner radius of 16 since RoundedRectangle doesn't expose its cornerRadius
    func glassEffect(_ style: GlassEffectStyle, in shape: RoundedRectangle) -> some View {
        self.modifier(GlassEffectRoundedRectModifier(style: style, cornerRadius: 16))
    }

    /// Glass effect with explicit corner radius - PREFERRED for RoundedRectangle
    func glassEffect(_ style: GlassEffectStyle, in cornerRadius: CGFloat) -> some View {
        self.modifier(GlassEffectRoundedRectModifier(style: style, cornerRadius: cornerRadius))
    }
}

// MARK: - Glass Effect Container

struct GlassEffectContainer<Content: View>: View {
    let spacing: CGFloat
    let content: Content

    init(spacing: CGFloat = 16, @ViewBuilder content: () -> Content) {
        self.spacing = spacing
        self.content = content()
    }

    var body: some View {
        content
            .padding(spacing)
            .background {
                ZStack {
                    RoundedRectangle(cornerRadius: 20)
                        .fill(.ultraThinMaterial)
                    RoundedRectangle(cornerRadius: 20)
                        .strokeBorder(
                            LinearGradient(
                                colors: [.white.opacity(0.4), .white.opacity(0.1)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 0.5
                        )
                }
            }
    }
}

// MARK: - Preview

#Preview {
    ZStack {
        LinearGradient(
            colors: [.blue, .purple],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .ignoresSafeArea()

        VStack(spacing: 20) {
            Text("Capsule Glass")
                .foregroundStyle(.white)
                .padding(.horizontal, 24)
                .padding(.vertical, 12)
                .glassEffect(.regular, in: .capsule)

            Text("Rounded Rect Glass")
                .foregroundStyle(.white)
                .padding(.horizontal, 24)
                .padding(.vertical, 12)
                .glassEffect(.regular.tint(.blue.opacity(0.3)), in: RoundedRectangle(cornerRadius: 12))

            GlassEffectContainer(spacing: 16) {
                VStack {
                    Text("Container")
                        .font(.headline)
                    Text("With content inside")
                        .font(.caption)
                }
                .foregroundStyle(.white)
            }

            Circle()
                .fill(.clear)
                .frame(width: 60, height: 60)
                .glassEffect(.regular, in: .circle)
                .overlay {
                    Image(systemName: "camera.fill")
                        .foregroundStyle(.white)
                }
        }
    }
}
