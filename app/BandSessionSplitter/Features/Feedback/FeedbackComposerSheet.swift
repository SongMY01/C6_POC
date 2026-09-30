import SwiftUI

/// 지금 지정된 구간반복 구간(loopRegion)에 텍스트 피드백을 남기는 화면.
/// 받는 세션을 고를 수 있다 — "전체" 또는 특정 세션(여러 개 가능).
struct FeedbackComposerSheet: View {
    let timeRange: ClosedRange<TimeInterval>
    let tracks: [StemTrack]
    let onSave: (_ text: String, _ targetSessionIds: [String]) -> Void
    let onCancel: () -> Void

    @State private var text = ""
    /// 비어 있으면 "전체".
    @State private var targets: Set<String> = []
    @FocusState private var textFocused: Bool

    private var trimmedText: String { text.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        NavigationStack {
            Form {
                Section("구간") {
                    Text("\(formatTime(timeRange.lowerBound)) ~ \(formatTime(timeRange.upperBound))")
                        .font(.body.monospacedDigit())
                }

                Section {
                    FlowChips {
                        chip(title: "전체", emoji: "👥", isOn: targets.isEmpty) { targets.removeAll() }
                        ForEach(tracks) { track in
                            chip(title: track.displayName, emoji: track.instrumentEmoji, isOn: targets.contains(track.id)) {
                                toggle(track.id)
                            }
                        }
                    }
                    .padding(.vertical, 4)
                } header: {
                    Text("받는 세션")
                } footer: {
                    Text(targetSummary)
                }

                Section("내용") {
                    TextField("예: 후렴 들어가기 전에 템포가 빨라져요", text: $text, axis: .vertical)
                        .lineLimit(4...10)
                        .focused($textFocused)
                }
            }
            .navigationTitle("피드백 남기기")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("취소", action: onCancel)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("보내기") { onSave(trimmedText, orderedTargets) }
                        .disabled(trimmedText.isEmpty)
                }
            }
        }
        .onAppear { textFocused = true }
    }

    /// 트랙 순서대로 정렬한 받는 세션 id 목록 (비어 있으면 전체).
    private var orderedTargets: [String] {
        tracks.map(\.id).filter { targets.contains($0) }
    }

    private var targetSummary: String {
        if targets.isEmpty { return "모든 세션에게 보냅니다." }
        let names = tracks.filter { targets.contains($0.id) }.map(\.displayName)
        return "\(names.joined(separator: ", "))에게만 보냅니다."
    }

    private func toggle(_ id: String) {
        if targets.contains(id) {
            targets.remove(id)
        } else {
            targets.insert(id)
        }
    }

    private func chip(title: String, emoji: String, isOn: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Text(emoji)
                Text(title).font(.subheadline.weight(.semibold))
                if isOn { Image(systemName: "checkmark").font(.caption.weight(.bold)) }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Capsule().fill(isOn ? Color.accentColor.opacity(0.25) : Color.secondary.opacity(0.15)))
            .overlay(Capsule().stroke(isOn ? Color.accentColor : Color.clear, lineWidth: 1.5))
        }
        .buttonStyle(.plain)
    }
}

/// 칩들을 가로로 채우다 넘치면 다음 줄로 넘기는 레이아웃.
private struct FlowChips: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = arrange(width: proposal.width ?? .infinity, subviews: subviews)
        let height = rows.map(\.height).reduce(0, +) + spacing * CGFloat(max(0, rows.count - 1))
        let width = rows.map(\.width).max() ?? 0
        return CGSize(width: proposal.width ?? width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for row in arrange(width: bounds.width, subviews: subviews) {
            var x = bounds.minX
            for index in row.indices {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
            y += row.height + spacing
        }
    }

    private struct Row { var indices: [Int] = []; var width: CGFloat = 0; var height: CGFloat = 0 }

    private func arrange(width: CGFloat, subviews: Subviews) -> [Row] {
        var rows: [Row] = [Row()]
        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            let needed = rows[rows.count - 1].indices.isEmpty ? size.width : rows[rows.count - 1].width + spacing + size.width
            if needed > width, !rows[rows.count - 1].indices.isEmpty {
                rows.append(Row())
            }
            var row = rows[rows.count - 1]
            row.width = row.indices.isEmpty ? size.width : row.width + spacing + size.width
            row.height = max(row.height, size.height)
            row.indices.append(index)
            rows[rows.count - 1] = row
        }
        return rows
    }
}
