import SwiftUI

// MARK: - 트랙 헤더

struct TrackHeader: View {
    @ObservedObject var track: StemTrack
    let isSolo: Bool
    let isSelected: Bool
    let isRecording: Bool
    let onSelect: () -> Void
    let onSolo: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 6) {
                    if isRecording {
                        Circle().fill(Color.red).frame(width: 8, height: 8)
                    }
                    Text(track.displayName)
                        .font(.system(size: 18, weight: .medium))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                }
                HStack(spacing: 16) {
                    Button { track.isMuted.toggle() } label: {
                        Image(systemName: track.isMuted ? "speaker.slash.fill" : "speaker.slash")
                            .foregroundStyle(track.isMuted ? GB.muteOn : Color.white.opacity(0.8))
                    }
                    Button(action: onSolo) {
                        Image(systemName: "headphones")
                            .foregroundStyle(isSolo ? GB.cycle : Color.white.opacity(0.8))
                    }
                    Slider(value: $track.volume, in: 0...1)
                        .tint(Color.white.opacity(0.6))
                }
                .font(.system(size: 20))
                .buttonStyle(.plain)

                if !track.activePatches.isEmpty {
                    HStack(spacing: 10) {
                        Text("패치")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(Color.red.opacity(0.9))
                            .frame(width: 60, alignment: .leading)
                        Slider(value: $track.patchVolume, in: 0...1)
                            .tint(Color.red.opacity(0.8))
                    }
                }
            }
            Text(track.instrumentEmoji)
                .font(.system(size: 44))
                .frame(width: 60)
        }
        .padding(.horizontal, 14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .background(isSelected ? GB.headerSelected : Color.clear)
        .overlay(alignment: .bottom) { Rectangle().fill(Color.black.opacity(0.6)).frame(height: 1) }
        .contentShape(Rectangle())
        .onTapGesture(perform: onSelect)
    }
}
