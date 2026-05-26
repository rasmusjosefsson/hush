import SwiftUI

/// Placeholder for the dual audio orb visualization during meeting recording.
public struct DualAudioOrbView: View {
    let micLevel: Float
    let systemLevel: Float

    public init(micLevel: Float = 0, systemLevel: Float = 0) {
        self.micLevel = micLevel
        self.systemLevel = systemLevel
    }

    public var body: some View {
        HStack(spacing: 12) {
            Circle()
                .fill(.blue.opacity(0.3 + Double(micLevel) * 0.7))
                .frame(width: 32, height: 32)
                .overlay(
                    Image(systemName: "mic.fill")
                        .foregroundStyle(.white)
                        .font(.system(size: 14))
                )
            Circle()
                .fill(.green.opacity(0.3 + Double(systemLevel) * 0.7))
                .frame(width: 32, height: 32)
                .overlay(
                    Image(systemName: "speaker.wave.2.fill")
                        .foregroundStyle(.white)
                        .font(.system(size: 14))
                )
        }
    }
}

/// Placeholder for the completion flower animation.
public struct FlowerCompletionView: View {
    @Binding var stemCollapsed: Bool
    var onCollapseFinished: (() -> Void)?

    public init(stemCollapsed: Binding<Bool>, onCollapseFinished: (() -> Void)? = nil) {
        self._stemCollapsed = stemCollapsed
        self.onCollapseFinished = onCollapseFinished
    }

    public var body: some View {
        Image(systemName: "checkmark.circle.fill")
            .font(.system(size: 40))
            .foregroundStyle(.green)
            .onAppear {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    stemCollapsed = true
                    onCollapseFinished?()
                }
            }
    }
}

/// Placeholder for the sacred geometry pill icon.
public struct MerkabaPillIcon: View {
    let isAnimating: Bool
    let audioLevel: Float

    public init(isAnimating: Bool = false, audioLevel: Float = 0) {
        self.isAnimating = isAnimating
        self.audioLevel = audioLevel
    }

    public var body: some View {
        Image(systemName: "waveform")
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(.red)
            .opacity(isAnimating ? (0.5 + Double(audioLevel) * 0.5) : 0.5)
    }
}
