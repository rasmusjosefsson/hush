import SwiftUI

/// 14-bar waveform visualization driven by audio level.
/// Thin, airy bars with subtle opacity — premium feel without visual weight.
public struct WaveformView: View {
    let audioLevel: Float
    var barCount: Int = 14

    public init(audioLevel: Float, barCount: Int = 14) {
        self.audioLevel = audioLevel
        self.barCount = barCount
    }

    public var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { timeline in
            let time = timeline.date.timeIntervalSinceReferenceDate
            HStack(spacing: 2.5) {
                ForEach(0..<barCount, id: \.self) { index in
                    RoundedRectangle(cornerRadius: 1)
                        .fill(Color.white.opacity(0.8))
                        .frame(width: 2, height: barHeight(for: index, time: time))
                }
            }
            .frame(height: 20)
        }
    }

    /// Calculate bar height using layered sine waves for smooth, organic motion.
    /// Each bar has a unique phase offset so they move independently.
    private func barHeight(for index: Int, time: Double) -> CGFloat {
        let baseHeight: Float = 3.0
        let maxHeight: Float = 20.0

        // Amplify audio level — raw mic levels are typically 0.0-0.3 for speech,
        // so we boost by 3x and clamp to make the waveform visually responsive.
        let boosted = min(audioLevel * 3.0, 1.0)

        // Each bar gets a unique phase offset for independent motion
        let phase = Double(index) * 0.55

        // Layer sine waves at different frequencies for organic, flowing motion
        let wave1 = sin(time * 2.5 + phase)
        let wave2 = sin(time * 4.3 + phase * 1.4) * 0.6
        let wave3 = sin(time * 7.1 + phase * 0.8) * 0.3

        // Normalize combined waves to 0...1
        let combined = (wave1 + wave2 + wave3) / 1.9
        let normalized = Float((combined + 1.0) / 2.0)

        // Audio level controls overall amplitude
        let height = baseHeight + (maxHeight - baseHeight) * boosted * normalized
        return CGFloat(max(baseHeight, min(height, maxHeight)))
    }
}

struct WaveformView_Previews: PreviewProvider {
    static var previews: some View {
        VStack(spacing: 20) {
            WaveformView(audioLevel: 0.0)
            WaveformView(audioLevel: 0.3)
            WaveformView(audioLevel: 0.6)
            WaveformView(audioLevel: 1.0)
        }
        .padding()
        .background(Color.black)
    }
}
