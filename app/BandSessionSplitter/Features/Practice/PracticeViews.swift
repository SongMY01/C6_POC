import SwiftUI

/// 연습 중 위쪽에 붙는 띠: 템포 사다리 진행, 그만하기. 끝나면 "해봤어요" 카드로 바뀐다.
struct PracticeBar: View {
    @ObservedObject var session: PracticeSession
    /// 끝난 뒤 "녹음해서 올리기"를 보여줄지 (녹음 기회가 남은 피드백일 때만)
    let canRecord: Bool
    let onRecord: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            if session.phase == .finished {
                finishedContent
            } else {
                runningContent
            }
        }
        .lineLimit(1)
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity)
        .background(Color(red: 0.2, green: 0.17, blue: 0.3))
        // 내용이 화면보다 넓어져도 부모 레이아웃을 밀어내지 않게 한다.
        .clipped()
    }

    private var runningContent: some View {
        HStack(spacing: 12) {
            if let region = session.region {
                Text("🎲 \(formatTime(region.lowerBound))~\(formatTime(region.upperBound))")
                    .font(.system(size: 14, weight: .bold, design: .monospaced))
                    .foregroundStyle(.white)
            }
            if session.hasLadder {
                HStack(spacing: 8) {
                    ForEach(Array(session.rungs.enumerated()), id: \.offset) { index, rate in
                        rungChip(index: index, rate: rate)
                    }
                }
                Text(loopText)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.white.opacity(0.7))
            } else {
                Text("구간 반복 중").font(.system(size: 13)).foregroundStyle(.white.opacity(0.7))
            }
            Spacer(minLength: 8)
            Button("그만") { session.stop() }
                .buttonStyle(GBToolButtonStyle())
        }
    }

    private func rungChip(index: Int, rate: Float) -> some View {
        let isCurrent = index == session.rungIndex
        let isDone = index < session.rungIndex
        return Button {
            session.jump(to: index)
        } label: {
            HStack(spacing: 4) {
                if isDone { Image(systemName: "checkmark") }
                Text("\(Int((rate * 100).rounded()))%")
            }
            .font(.system(size: 14, weight: .bold, design: .rounded))
            .padding(.horizontal, 12).padding(.vertical, 6)
            .foregroundStyle(isCurrent ? Color.black : Color.white.opacity(isDone ? 0.55 : 0.85))
            .background(Capsule().fill(isCurrent ? GB.cycle : Color.white.opacity(0.14)))
        }
        .buttonStyle(.plain)
    }

    private var loopText: String {
        guard session.phase == .running else { return "" }
        return "\(min(session.loopsDone + 1, session.loopsNeeded))/\(session.loopsNeeded)바퀴"
    }

    private var finishedContent: some View {
        HStack(spacing: 14) {
            Text("👏 해봤어요!")
                .font(.system(size: 17, weight: .bold))
                .foregroundStyle(.white)
            Spacer(minLength: 8)
            Button("한 번 더") { session.restart() }
                .buttonStyle(GBToolButtonStyle())
            if canRecord {
                Button {
                    onRecord()
                } label: { Label("녹음해서 올리기", systemImage: "record.circle") }
                    .buttonStyle(GBToolButtonStyle())
            }
            Button("닫기") { session.stop() }
                .buttonStyle(GBToolButtonStyle())
        }
    }
}

/// 카운트인 중 화면 가운데 크게 뜨는 숫자.
struct CountInOverlay: View {
    @ObservedObject var session: PracticeSession

    var body: some View {
        if case .countIn(let beat) = session.phase {
            ZStack {
                Color.black.opacity(0.35).ignoresSafeArea()
                VStack(spacing: 10) {
                    Text("\(beat)")
                        .font(.system(size: 140, weight: .heavy, design: .rounded))
                        .foregroundStyle(.white)
                        .id(beat)
                        .transition(.scale.combined(with: .opacity))
                    if session.hasLadder {
                        Text("\(Int((session.currentRate * 100).rounded()))% 속도로 시작해요")
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(.white.opacity(0.85))
                    }
                }
            }
            .animation(.easeOut(duration: 0.18), value: beat)
            .allowsHitTesting(false)
        }
    }
}
