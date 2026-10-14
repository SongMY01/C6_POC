import SwiftUI

/// 연습 중 위쪽에 붙는 띠: 템포 사다리 진행, (밸런스면) 지금 ↔ 목표 믹스, 그만하기.
/// 사다리가 끝나면 "해봤어요" + 녹음해서 올리기로 바뀐다.
struct PracticeBar: View {
    @ObservedObject var session: PracticeSession
    let kind: FeedbackKind?
    /// 밸런스 피드백이면 목표 믹스 듣기 토글 (아니면 nil)
    let hearingTargetMix: Binding<Bool>?
    /// 끝난 뒤 "녹음해서 올리기"를 보여줄지
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
        .background(Color(red: 0.16, green: 0.24, blue: 0.2))
        // 내용이 화면보다 넓어져도 부모 레이아웃을 밀어내지 않게 한다.
        .clipped()
    }

    private var title: some View {
        HStack(spacing: 6) {
            if let kind { Image(systemName: kind.icon) }
            Text(L("\(kind?.label ?? L("구간")) 연습"))
            if let region = session.region {
                Text("\(formatTime(region.lowerBound))~\(formatTime(region.upperBound))")
                    .font(.system(size: 13, weight: .medium, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.7))
            }
        }
        .font(.system(size: 15, weight: .bold))
        .foregroundStyle(.white)
    }

    private var runningContent: some View {
        HStack(spacing: 12) {
            title
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
                Text(L("반복 중")).font(.system(size: 13)).foregroundStyle(.white.opacity(0.7))
            }
            if let hearingTargetMix {
                Picker(L("믹스"), selection: hearingTargetMix) {
                    Text(L("지금 믹스")).tag(false)
                    Text(L("목표 믹스")).tag(true)
                }
                .pickerStyle(.segmented)
                .frame(width: 210)
            }
            Spacer(minLength: 8)
            if canRecord {
                Button {
                    onRecord()
                } label: { Label(L("녹음"), systemImage: "record.circle") }
                    .buttonStyle(GBToolButtonStyle())
            }
            Button(L("그만")) { session.stop() }
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
        return L("\(min(session.loopsDone + 1, session.loopsNeeded))/\(session.loopsNeeded)바퀴")
    }

    private var finishedContent: some View {
        HStack(spacing: 14) {
            Text(L("👏 100%까지 해봤어요"))
                .font(.system(size: 17, weight: .bold))
                .foregroundStyle(.white)
            Spacer(minLength: 8)
            Button(L("한 번 더")) { session.restart() }
                .buttonStyle(GBToolButtonStyle())
            if canRecord {
                Button {
                    onRecord()
                } label: { Label(L("녹음해서 올리기"), systemImage: "record.circle") }
                    .buttonStyle(GBToolButtonStyle())
            }
            Button(L("닫기")) { session.stop() }
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
                        Text(L("\(Int((session.currentRate * 100).rounded()))% 속도로 시작해요"))
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
