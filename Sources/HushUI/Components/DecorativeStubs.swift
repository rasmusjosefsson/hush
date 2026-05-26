import SwiftUI

/// Placeholder for stripped decorative Merkaba animation.
public struct MeditativeMerkabaView: View {
    var size: CGFloat
    var revolutionDuration: Double = 5.0
    var tintColor: Color = .accentColor

    public init(size: CGFloat, revolutionDuration: Double = 5.0, tintColor: Color = .accentColor) {
        self.size = size
        self.revolutionDuration = revolutionDuration
        self.tintColor = tintColor
    }

    public var body: some View {
        Image(systemName: "sparkle")
            .font(.system(size: size * 0.5))
            .foregroundStyle(tintColor)
            .frame(width: size, height: size)
    }
}

/// Placeholder for stripped sacred-geometry divider.
public struct SacredGeometryDivider: View {
    public enum Position { case top, bottom }
    var position: Position = .top

    public init(position: Position = .top) {
        self.position = position
    }

    public var body: some View {
        Divider()
            .padding(.horizontal, 28)
    }
}

/// Placeholder for stripped particle field effect.
public struct ParticleField: View {
    public enum DriftDirection { case orbital, upward, up, radial }

    var particleCount: Int = 8
    var tintColor: Color = .accentColor
    var opacity: Double = 0.3
    var driftDirection: DriftDirection = .orbital

    public init(particleCount: Int = 8, tintColor: Color = .accentColor, opacity: Double = 0.3, driftDirection: DriftDirection = .orbital) {
        self.particleCount = particleCount
        self.tintColor = tintColor
        self.opacity = opacity
        self.driftDirection = driftDirection
    }

    public var body: some View {
        Color.clear
    }
}

/// Placeholder for stripped sonic mandala visualization.
public struct SonicMandalaView: View {
    public struct Data {
        public init() {}
        public static func from(text: String?, durationMs: Int?) -> Data { Data() }
    }
    public enum Style { case monochrome, colorful }

    var data: Data = Data()
    var size: CGFloat = 32
    var style: Style = .monochrome

    public init(data: Data = Data(), size: CGFloat = 32, style: Style = .monochrome) {
        self.data = data
        self.size = size
        self.style = style
    }

    public var body: some View {
        BrandWaveformView(size: size * 0.55, color: .secondary)
            .frame(width: size, height: size)
    }
}

/// Placeholder for stripped spinner ring animation.
public struct SpinnerRingView: View {
    var size: CGFloat = 20
    var revolutionDuration: Double = 2.5
    var tintColor: Color = .accentColor

    public init(size: CGFloat = 20, revolutionDuration: Double = 2.5, tintColor: Color = .accentColor) {
        self.size = size
        self.revolutionDuration = revolutionDuration
        self.tintColor = tintColor
    }

    public var body: some View {
        ProgressView()
            .controlSize(.small)
            .frame(width: size, height: size)
    }
}

// MARK: - Previews

struct DecorativeStubs_Previews: PreviewProvider {
    static var previews: some View {
        VStack(spacing: 24) {
            Group {
                Text("MeditativeMerkabaView").font(.caption).foregroundStyle(.secondary)
                MeditativeMerkabaView(size: 64)
            }

            Divider()

            Group {
                Text("SacredGeometryDivider").font(.caption).foregroundStyle(.secondary)
                SacredGeometryDivider(position: .top)
                SacredGeometryDivider(position: .bottom)
            }

            Divider()

            Group {
                Text("ParticleField").font(.caption).foregroundStyle(.secondary)
                ParticleField()
                    .frame(width: 100, height: 60)
                    .background(Color.gray.opacity(0.1))
            }

            Divider()

            Group {
                Text("SonicMandalaView").font(.caption).foregroundStyle(.secondary)
                SonicMandalaView(size: 48)
            }

            Divider()

            Group {
                Text("SpinnerRingView").font(.caption).foregroundStyle(.secondary)
                SpinnerRingView(size: 28)
            }
        }
        .padding()
    }
}
