import SwiftUI

// MARK: - 피드백 작성: 종류를 먼저 고르면, 그 종류에 맞는 입력창이 열린다
//
// 종류와 입력 방식은 화이트보드 회의(2026-10-14) 기준: 박자 · 볼륨·밸런스 · 하모니 · 표현 · 그 외(타이핑만).
// 보낼 때 입력값으로 받는 사람용 문장을 한국어·영어 둘 다 만들어 저장한다 (앱 표시 언어에 따라 골라 보임).

/// 작성 화면이 만든 피드백. StemPlayerView가 FeedbackStore에 저장·동기화한다.
struct ComposedFeedback {
    let timeRange: ClosedRange<TimeInterval>
    let kind: FeedbackKind
    let targets: Set<String>
    let text: String
    let translations: [String: String]
    /// 볼륨·밸런스: 받는 사람이 연습할 때 듣는 목표 믹스 (트랙 id → 볼륨 0~1)
    let targetMix: [String: Float]?
}

/// 작성 화면에서만 쓰는 종류별 모양·안내.
private extension FeedbackKind {
    var hint: String {
        switch self {
        case .tempo: return L("빨라요 / 느려요")
        case .balance: return L("묻힘 / 적당 / 튐")
        case .harmony: return L("이 코드로 쳐 줘")
        case .expression: return L("느낌 · 레퍼런스")
        default: return L("글로만 쓰기")
        }
    }

    var color: Color {
        switch self {
        case .tempo: return .orange
        case .balance: return .purple
        case .harmony: return .teal
        case .expression: return .indigo
        default: return .gray
        }
    }

    /// 받는 사람이 "연습 시작"을 누르면 실제로 하게 되는 방법 (FeedbackKind.plan과 맞춘다)
    var startingTip: String {
        switch self {
        case .tempo: return L("카운트인 → 80% · 90% · 100% 속도로 구간 반복")
        case .balance: return L("목표 믹스로 구간 반복 · 지금 ↔ 목표 바꿔 듣기")
        case .harmony: return L("카운트인 → 70% · 85% · 100% 속도로 구간 반복")
        case .expression: return L("카운트인 → 고른 느낌을 떠올리며 구간 반복")
        default: return L("구간 반복")
        }
    }
}

struct FeedbackComposerSheet: View {
    let timeRange: ClosedRange<TimeInterval>
    let tracks: [StemTrack]
    /// 구간 듣기 · 볼륨·밸런스의 "고친 믹스" 듣기에 쓴다.
    @ObservedObject var controller: StemPlayerController
    let onSend: (ComposedFeedback) -> Void
    let onCancel: () -> Void

    init(timeRange: ClosedRange<TimeInterval>, initialTargets: Set<String>, tracks: [StemTrack],
         controller: StemPlayerController, onSend: @escaping (ComposedFeedback) -> Void, onCancel: @escaping () -> Void) {
        self.timeRange = timeRange
        self.tracks = tracks
        self.controller = controller
        self.onSend = onSend
        self.onCancel = onCancel
        _targets = State(initialValue: initialTargets)
    }

    // 공통
    @State private var targets: Set<String> = []
    @State private var kind: FeedbackKind?
    @State private var memo = ""

    // 박자
    /// 박마다 표시: 키 = 마디(0~3) × 4 + 박(0~3), 값 = 빨라요/느려요. 누를 때마다 빨라요 → 느려요 → 없음.
    @State private var beatMarks: [Int: BeatMark] = [:]

    // 볼륨·밸런스
    @State private var hearingFixed = false             // false: 지금 믹스, true: 고친 믹스
    @State private var originalVolumes: [String: Float] = [:]
    /// 열기 전 구간반복 상태. 닫을 때 되돌린다 (작성 화면이 곡의 구간 설정을 바꿔 놓지 않게).
    @State private var savedLoop: (region: ClosedRange<TimeInterval>?, enabled: Bool)?
    @State private var fader: [String: Double] = [:]   // 파트별 0(묻힘) ~ 0.5(적당) ~ 1(튐). 건드린 파트만 들어 있다.

    // 하모니: 1마디를 4박으로 나눠 박마다 코드
    @State private var chords: [String?] = Array(repeating: nil, count: 4)

    // 표현: 악보 기호 타일 + 톤 + 레퍼런스 링크
    @State private var exprSymbol: ExprSymbol?
    @State private var tones: Set<ToneStyle> = []
    @State private var referenceLink = ""

    // 그 외: 타이핑만
    @State private var otherText = ""


    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    rangeAndTargets
                    kindPicker
                    if let kind {
                        inputCard(for: kind)
                        if kind != .free { commonInputs }
                        recipientPreview(for: kind)
                    }
                }
                .padding(20)
                .frame(maxWidth: 760)
                .frame(maxWidth: .infinity)
            }
            .background(Color(uiColor: .systemGroupedBackground))
            .navigationTitle(L("피드백 남기기"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(L("취소"), action: onCancel) }
                ToolbarItem(placement: .principal) {
                    Button(action: playRegion) {
                        Label(controller.isPlaying ? L("멈춤") : L("구간 듣기"),
                              systemImage: controller.isPlaying ? "pause.fill" : "play.fill")
                            .labelStyle(.titleAndIcon)
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(L("보내기")) { if let feedback = composed() { onSend(feedback) } }.disabled(!isComplete)
                }
            }
            .onAppear {
                originalVolumes = Dictionary(uniqueKeysWithValues: tracks.map { ($0.id, $0.volume) })
                savedLoop = (controller.loopRegion, controller.isLoopEnabled)
            }
            .onDisappear {
                controller.pause()
                restoreVolumes()
                if let savedLoop {
                    controller.loopRegion = savedLoop.region
                    controller.isLoopEnabled = savedLoop.enabled
                }
            }
            .onChange(of: fader) { _, _ in applyHearing() }
            .onChange(of: hearingFixed) { _, _ in applyHearing() }
        }
    }

    // MARK: 위쪽

    private var rangeAndTargets: some View {
        card {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Label("\(formatTime(timeRange.lowerBound)) ~ \(formatTime(timeRange.upperBound))", systemImage: "scope")
                        .font(.headline.monospacedDigit())
                    Spacer()
                    Text(L("지금 잡힌 구간")).font(.caption).foregroundStyle(.secondary)
                }
                Divider()
                Text(L("받는 세션")).font(.subheadline.weight(.semibold))
                ChipFlow(spacing: 8) {
                    chip(L("👥 전체"), isOn: targets.isEmpty) { targets.removeAll() }
                    ForEach(tracks) { track in
                        chip("\(track.instrumentEmoji) \(track.displayName)", isOn: targets.contains(track.id)) {
                            toggle(&targets, track.id)
                        }
                    }
                }
            }
        }
    }

    private var kindPicker: some View {
        card {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text(L("어떤 피드백이에요?")).font(.headline)
                    Spacer()
                    if kind == nil { Text(L("먼저 종류를 골라 주세요")).font(.caption).foregroundStyle(.secondary) }
                }
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 10)], spacing: 10) {
                    ForEach(FeedbackKind.composable) { item in
                        Button {
                            withAnimation(.easeOut(duration: 0.15)) { kind = item }
                        } label: {
                            VStack(spacing: 6) {
                                Image(systemName: item.icon).font(.title2)
                                Text(item.label).font(.subheadline.weight(.bold))
                                Text(item.hint).font(.caption2).opacity(0.75)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .foregroundStyle(kind == item ? Color.white : item.color)
                            .background(RoundedRectangle(cornerRadius: 12).fill(kind == item ? item.color : item.color.opacity(0.12)))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    // MARK: 종류별 입력창

    @ViewBuilder
    private func inputCard(for kind: FeedbackKind) -> some View {
        card(accent: kind.color) {
            VStack(alignment: .leading, spacing: 14) {
                Label(L("\(kind.label) 입력"), systemImage: kind.icon)
                    .font(.headline)
                    .foregroundStyle(kind.color)
                switch kind {
                case .tempo: tempoInput
                case .balance: mixInput
                case .harmony: harmonyInput
                case .expression: toneInput
                default: otherInput
                }
            }
        }
    }

    // 박자: 선택한 구간의 마디를 4박으로 쪼개서 틀린 박마다 빨라요/느려요를 표시
    private var tempoInput: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(L("선택한 구간의 마디를 4박으로 나눴어요")).font(.caption).foregroundStyle(.secondary)
            Text(L("틀린 박을 눌러 주세요")).font(.subheadline.weight(.semibold))
            VStack(spacing: 6) {
                HStack(spacing: 8) {
                    Text("").frame(width: 64)
                    ForEach(1...4, id: \.self) { beat in
                        Text("\(beat)").font(.caption.weight(.semibold)).foregroundStyle(.secondary).frame(maxWidth: .infinity)
                    }
                }
                ForEach(0..<4, id: \.self) { measure in
                    HStack(spacing: 8) {
                        Text(L("마디 \(measure + 1)")).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                            .frame(width: 64, alignment: .leading)
                        ForEach(0..<4, id: \.self) { beat in
                            beatCell(measure: measure, beat: beat)
                        }
                    }
                }
            }
            HStack(spacing: 14) {
                ForEach(BeatMark.allCases, id: \.self) { mark in
                    Label(mark.label, systemImage: mark.icon).foregroundStyle(mark.color)
                }
                Text(L("누를 때마다 빨라요 → 느려요 → 없음으로 바뀌어요")).foregroundStyle(.secondary)
            }
            .font(.caption.weight(.semibold))
        }
    }

    private func beatCell(measure: Int, beat: Int) -> some View {
        let id = measure * 4 + beat
        let mark = beatMarks[id]
        return Button {
            switch mark {
            case nil: beatMarks[id] = .rushing
            case .rushing: beatMarks[id] = .dragging
            case .dragging: beatMarks[id] = nil
            }
        } label: {
            Image(systemName: mark?.icon ?? "circle")
                .font(.body.weight(.bold))
                .frame(maxWidth: .infinity, minHeight: 44)
                .foregroundStyle(mark == nil ? Color.secondary.opacity(0.5) : Color.white)
                .background(RoundedRectangle(cornerRadius: 8).fill(mark?.color ?? Color.secondary.opacity(0.12)))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(L("마디 \(measure + 1) \(beat + 1)박"))
        .accessibilityValue(mark?.label ?? "")
    }

    // 볼륨·밸런스: 파트별 페이더 한 화면. 왼쪽 묻힘 ↔ 가운데 적당 ↔ 오른쪽 튐. 건드린 파트만 전송된다.
    private var mixInput: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("\(formatTime(timeRange.lowerBound))~\(formatTime(timeRange.upperBound)) · \(recipientsLabel)")
                .font(.caption.weight(.semibold))
                .padding(.horizontal, 10).padding(.vertical, 4)
                .background(Capsule().fill(Color.secondary.opacity(0.14)))
            HStack(spacing: 10) {
                Text("").frame(width: 96)
                HStack {
                    Text(L("묻힘")).frame(maxWidth: .infinity, alignment: .leading)
                    Text(L("적당"))
                    Text(L("튐")).frame(maxWidth: .infinity, alignment: .trailing)
                }
                .font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            }
            ForEach(tracks) { track in
                let touched = fader[track.id] != nil
                HStack(spacing: 10) {
                    Text("\(track.instrumentEmoji) \(track.displayName)")
                        .font(.subheadline.weight(touched ? .bold : .regular)).frame(width: 96, alignment: .leading)
                    ZStack {
                        Rectangle().fill(Color.secondary.opacity(0.5)).frame(width: 2, height: 16)
                        Slider(value: Binding(get: { fader[track.id] ?? 0.5 }, set: { fader[track.id] = $0 }), in: 0...1)
                            .tint(touched ? Color.purple : Color.secondary.opacity(0.35))
                    }
                }
            }
            Divider()
            Text(L("이렇게 고치면 들려요")).font(.subheadline.weight(.semibold))
            HStack(spacing: 10) {
                Picker(L("듣기"), selection: $hearingFixed) {
                    Text(L("지금 믹스")).tag(false)
                    Text(L("고친 믹스")).tag(true)
                }
                .pickerStyle(.segmented)
                Button(action: playRegion) {
                    Label(controller.isPlaying ? L("멈춤") : L("구간 듣기"),
                          systemImage: controller.isPlaying ? "pause.fill" : "play.fill")
                }
                .buttonStyle(.bordered)
            }
            Text(L("묻힌 파트는 키우고 튀는 파트는 줄여서 들려줘요. 곡 볼륨은 바뀌지 않아요."))
                .font(.caption).foregroundStyle(.secondary)
            HStack {
                Text(L("한 화면에서 전 파트를 한 번에 조정해요. 건드린 파트만 피드백으로 전송돼요."))
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button(L("되돌리기")) { fader.removeAll() }.font(.footnote)
            }
        }
    }

    // 하모니: "이 코드로 쳐 주세요" — 1마디를 4박으로 나눠 박마다 코드를 하나씩
    private var harmonyInput: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(L("이 코드로 쳐 주세요")).font(.subheadline.weight(.semibold))
            HStack(spacing: 8) {
                ForEach(0..<4, id: \.self) { index in
                    Menu {
                        ForEach(chordRoots, id: \.self) { root in
                            Menu(root) {
                                ForEach(chordQualities, id: \.self) { quality in
                                    Button(root + quality) { chords[index] = root + quality }
                                }
                            }
                        }
                        if index > 0, let previous = chords[index - 1] {
                            Button(L("앞 박과 같게 (\(previous))")) { chords[index] = previous }
                        }
                        Button(L("지우기"), role: .destructive) { chords[index] = nil }
                    } label: {
                        VStack(spacing: 2) {
                            Text("\(index + 1)").font(.caption2).foregroundStyle(.secondary)
                            Text(chords[index] ?? "–").font(.title2.weight(.bold))
                        }
                        .frame(maxWidth: .infinity, minHeight: 72)
                        .foregroundStyle(chords[index] == nil ? Color.secondary : Color.teal)
                        .background(RoundedRectangle(cornerRadius: 10).fill(chords[index] == nil ? Color.secondary.opacity(0.12) : Color.teal.opacity(0.16)))
                    }
                }
            }
            Label(L("1마디를 4박으로 나눠서, 박마다 코드를 골라요"), systemImage: "info.circle")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private var chordRoots: [String] { ["C", "C♯", "D", "E♭", "E", "F", "F♯", "G", "A♭", "A", "B♭", "B"] }
    private var chordQualities: [String] { ["", "m", "7", "maj7", "m7", "sus4", "dim"] }

    // 표현: 악보 기호를 그림 그대로 쓰고, 이름은 쉬운 말로 붙인 타일 + 레퍼런스 링크
    private var toneInput: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(L("기호 타일 고르기")).font(.subheadline.weight(.semibold))
            Text("\(formatTime(timeRange.lowerBound))~\(formatTime(timeRange.upperBound)) · \(recipientsLabel)")
                .font(.caption.weight(.semibold))
                .padding(.horizontal, 10).padding(.vertical, 4)
                .background(Capsule().fill(Color.secondary.opacity(0.14)))
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                ForEach(ExprSymbol.allCases) { symbol in
                    tile(label: symbol.label, color: .indigo, isOn: exprSymbol == symbol) {
                        ExprSymbolShape(symbol: symbol).frame(height: 32)
                    } action: { exprSymbol = exprSymbol == symbol ? nil : symbol }
                }
            }
            Text(L("악보 기호를 그림 그대로 쓰고 이름은 쉬운 말로 붙였어요. 기호를 몰라도 이해할 수 있어요."))
                .font(.caption).foregroundStyle(.secondary)
            Divider()
            Text(L("톤 (선택)")).font(.subheadline.weight(.semibold))
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 3), spacing: 10) {
                ForEach(ToneStyle.allCases) { style in
                    tile(label: style.label, color: .indigo, isOn: tones.contains(style)) {
                        ToneWave(style: style)
                    } action: { toggle(&tones, style) }
                }
            }
            Text(L("파형 모양으로 소리의 느낌을 보여줘요. 여러 개 골라도 돼요."))
                .font(.caption).foregroundStyle(.secondary)
            HStack(spacing: 8) {
                Image(systemName: "link").foregroundStyle(.secondary)
                TextField(L("참고할 영상·곡 링크 (선택)"), text: $referenceLink)
                    .textInputAutocapitalization(.never).autocorrectionDisabled()
            }
            .padding(10)
            .background(RoundedRectangle(cornerRadius: 10).fill(Color.secondary.opacity(0.1)))
        }
    }

    // 그 외: 타이핑만
    private var otherInput: some View {
        VStack(alignment: .leading, spacing: 10) {
            TextField(L("내용을 입력하세요"), text: $otherText, axis: .vertical)
                .lineLimit(4...8)
                .padding(10)
                .background(RoundedRectangle(cornerRadius: 10).fill(Color.secondary.opacity(0.1)))
            Label(L("종류에 맞지 않는 피드백은 글로만 남겨요"), systemImage: "info.circle")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    // MARK: 공통 입력 (한 줄 메모 · 음성 메모)

    private var commonInputs: some View {
        card {
            VStack(alignment: .leading, spacing: 12) {
                Text(L("덧붙이기 (선택)")).font(.subheadline.weight(.semibold))
                TextField(L("한 줄 메모"), text: $memo)
                    .padding(10)
                    .background(RoundedRectangle(cornerRadius: 10).fill(Color.secondary.opacity(0.1)))
            }
        }
    }

    // MARK: 받는 사람 화면 미리보기

    private func recipientPreview(for kind: FeedbackKind) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(L("받는 사람에게는 이렇게 보여요")).font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    Image(systemName: kind.icon).foregroundStyle(.white)
                        .frame(width: 30, height: 30)
                        .background(Circle().fill(kind.color))
                    Text("\(formatTime(timeRange.lowerBound)) ~ \(formatTime(timeRange.upperBound))")
                        .font(.subheadline.monospacedDigit().weight(.semibold))
                    Text("→ \(recipientsLabel)").font(.subheadline).foregroundStyle(.secondary)
                    Spacer()
                    Text(kind.label).font(.caption2.weight(.bold))
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background(Capsule().fill(kind.color.opacity(0.18))).foregroundStyle(kind.color)
                }
                Text(summary(for: kind)).font(.body.weight(.medium))
                if kind == .expression && (exprSymbol != nil || !tones.isEmpty) {
                    // 기호를 모르는 사람도 보게, 받는 화면에도 그림을 같이 보여 준다
                    HStack(spacing: 16) {
                        if let exprSymbol { ExprSymbolShape(symbol: exprSymbol).frame(height: 32) }
                        ForEach(ToneStyle.allCases.filter(tones.contains)) { ToneWave(style: $0) }
                    }
                    .foregroundStyle(kind.color)
                }
                if !memo.isEmpty { Text("“\(memo)”").font(.callout).foregroundStyle(.secondary) }
                Divider()
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "lightbulb.fill").foregroundStyle(.yellow)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(L("이렇게 시작해 보세요")).font(.caption.weight(.bold))
                        Text(kind.startingTip).font(.footnote)
                    }
                }
                HStack {
                    Spacer()
                    Text(L("▶ 바로 해보기")).font(.footnote.weight(.bold))
                        .padding(.horizontal, 14).padding(.vertical, 7)
                        .background(Capsule().fill(kind.color.opacity(0.18))).foregroundStyle(kind.color)
                }
            }
            .padding(14)
            .background(RoundedRectangle(cornerRadius: 14).fill(Color(uiColor: .systemBackground)))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(kind.color.opacity(0.5), lineWidth: 1.5))
        }
    }

    // MARK: 요약 문장 (입력값으로 만들어짐)

    private var recipientsLabel: String {
        if targets.isEmpty { return L("전체") }
        return tracks.filter { targets.contains($0.id) }.map(\.displayName).joined(separator: ", ")
    }

    private func summary(for kind: FeedbackKind) -> String {
        switch kind {
        case .tempo:
            if beatMarks.isEmpty { return L("틀린 박을 눌러 주세요.") }
            let sentences = BeatMark.allCases.compactMap { mark -> String? in
                let spots = beatMarks.filter { $0.value == mark }.keys.sorted().map { (measure: $0 / 4 + 1, beat: $0 % 4 + 1) }
                if spots.isEmpty { return nil }
                if AppLanguage.isEnglish {
                    return spots.map { "Bar \($0.measure) beat \($0.beat)" }.joined(separator: ", ") + ": \(mark.label.lowercased())."
                }
                return spots.map { "마디 \($0.measure)의 \($0.beat)박" }.joined(separator: ", ") + "이 \(mark.label)."
            }
            return sentences.joined(separator: " ")
        case .balance:
            let parts = tracks.compactMap { track -> String? in
                guard let value = fader[track.id] else { return nil }
                let phrase = mixPhrase(value)
                return AppLanguage.isEnglish ? "\(track.displayName) — \(phrase)" : "\(track.displayName.withJosa("이", "가")) \(phrase)"
            }
            if parts.isEmpty { return L("파트별 페이더를 움직여 주세요.") }
            let joined = parts.joined(separator: ", ")
            return AppLanguage.isEnglish ? "In this section: \(joined)." : "이 구간에서 \(joined)."
        case .harmony:
            if chords.allSatisfy({ $0 == nil }) { return L("받는 사람이 칠 코드를 골라 주세요.") }
            return L("\(chords.map { $0 ?? "–" }.joined(separator: " | ")) 코드로 쳐 주세요.")
        case .expression:
            var parts: [String] = []
            if let exprSymbol { parts.append(L("이 구간은 ‘\(exprSymbol.label)’ 연주해 주세요.")) }
            if !tones.isEmpty { parts.append(L("톤: \(ToneStyle.allCases.filter(tones.contains).map(\.label).joined(separator: ", "))")) }
            return parts.isEmpty ? L("기호 타일이나 톤을 골라 주세요.") : parts.joined(separator: " ")
        default:
            let text = otherText.trimmingCharacters(in: .whitespacesAndNewlines)
            return text.isEmpty ? L("내용을 적어 주세요.") : text
        }
    }

    /// 보내기 전에 필수 입력이 채워졌는지 (종류마다 다름).
    private var isComplete: Bool {
        switch kind {
        case nil: return false
        case .tempo: return !beatMarks.isEmpty
        case .balance: return !fader.isEmpty
        case .harmony: return chords.contains { $0 != nil }
        case .expression: return exprSymbol != nil || !tones.isEmpty
        default: return !otherText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }

    // MARK: 보내기

    /// 입력값으로 저장할 피드백을 만든다. 문장은 한국어·영어 둘 다 만들고, 지금 언어 쪽을 원문으로 둔다.
    private func composed() -> ComposedFeedback? {
        guard let kind, isComplete else { return nil }
        func fullText() -> String {
            var lines = [summary(for: kind)]
            let note = memo.trimmingCharacters(in: .whitespacesAndNewlines)
            if !note.isEmpty { lines.append("“\(note)”") }
            let link = referenceLink.trimmingCharacters(in: .whitespacesAndNewlines)
            if kind == .expression, !link.isEmpty { lines.append("🔗 \(link)") }
            return lines.joined(separator: "\n")
        }
        let korean = AppLanguage.with(.korean, fullText)
        let english = AppLanguage.with(.english, fullText)
        return ComposedFeedback(
            timeRange: timeRange,
            kind: kind,
            targets: targets,
            text: AppLanguage.isEnglish ? english : korean,
            translations: ["ko": korean, "en": english],
            targetMix: kind == .balance ? fixedMix() : nil
        )
    }

    // MARK: 계산 · 보조

    /// 페이더대로 고친 믹스: 묻힌 파트는 키우고 튀는 파트는 줄인다 (가운데 = 그대로).
    /// 가장 큰 볼륨이 1을 넘으면 전체를 같이 낮춰 비율을 지킨다.
    private func fixedMix() -> [String: Float] {
        let raw = tracks.map { track -> (String, Float) in
            let position = Float(fader[track.id] ?? 0.5)
            return (track.id, (originalVolumes[track.id] ?? track.volume) * (1 + (0.5 - position)))
        }
        let peak = max(1, raw.map(\.1).max() ?? 1)
        return Dictionary(uniqueKeysWithValues: raw.map { ($0.0, $0.1 / peak) })
    }

    /// 구간을 반복 재생한다.
    private func playRegion() {
        if controller.isPlaying { controller.pause(); return }
        controller.loopRegion = timeRange
        controller.isLoopEnabled = true
        controller.seek(to: timeRange.lowerBound)
        controller.play()
    }

    /// 고친 믹스: 묻힌 파트는 키우고 튀는 파트는 줄인다 (가운데 = 그대로). 합이 1을 넘으면 전체를 낮춰 맞춘다.
    private func applyHearing() {
        guard hearingFixed else { restoreVolumes(); return }
        let mix = fixedMix()
        for track in tracks { if let volume = mix[track.id] { track.volume = volume } }
    }

    private func restoreVolumes() {
        for track in tracks {
            if let volume = originalVolumes[track.id] { track.volume = volume }
        }
    }

    /// 페이더 위치 → 말. 가운데는 적당, 양끝으로 갈수록 많이.
    private func mixPhrase(_ value: Double) -> String {
        switch value {
        case ..<0.2: return L("많이 묻혀요")
        case ..<0.4: return L("조금 묻혀요")
        case ...0.6: return L("적당해요")
        case ...0.8: return L("조금 튀어요")
        default: return L("많이 튀어요")
        }
    }

    private func toggle<T: Hashable>(_ set: inout Set<T>, _ value: T) {
        if set.contains(value) { set.remove(value) } else { set.insert(value) }
    }

    // MARK: 작은 부품

    private func card<Content: View>(accent: Color? = nil, @ViewBuilder content: () -> Content) -> some View {
        content()
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 14).fill(Color(uiColor: .systemBackground)))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(accent?.opacity(0.5) ?? .clear, lineWidth: 1.5))
    }

    private func chip(_ text: String, isOn: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(text)
                .font(.subheadline.weight(.semibold))
                .padding(.horizontal, 12).padding(.vertical, 8)
                .background(Capsule().fill(isOn ? Color.accentColor.opacity(0.25) : Color.secondary.opacity(0.14)))
                .overlay(Capsule().stroke(isOn ? Color.accentColor : .clear, lineWidth: 1.5))
        }
        .buttonStyle(.plain)
    }

    /// 이모지·기호가 위에 있고 이름이 아래에 있는 선택 타일 (표현·밸런스 공용).
    private func tile<Symbol: View>(label: String, color: Color, isOn: Bool,
                                    @ViewBuilder symbol: () -> Symbol, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 10) {
                symbol().foregroundStyle(isOn ? color : Color.primary)
                Text(label).font(.subheadline.weight(.semibold))
            }
            .frame(maxWidth: .infinity, minHeight: 92)
            .padding(.vertical, 8)
            .background(RoundedRectangle(cornerRadius: 12).fill(isOn ? color.opacity(0.18) : Color(uiColor: .systemBackground)))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(isOn ? color : Color.secondary.opacity(0.3), lineWidth: isOn ? 2 : 1))
        }
        .buttonStyle(.plain)
    }
}

/// 박자 격자에서 박 하나에 붙이는 표시.
private enum BeatMark: CaseIterable {
    case rushing, dragging

    var label: String { self == .rushing ? L("빨라요") : L("느려요") }
    /// 빨라요 = 앞으로 쏠림(→), 느려요 = 뒤로 처짐(←)
    var icon: String { self == .rushing ? "arrow.right" : "arrow.left" }
    var color: Color { self == .rushing ? .orange : .blue }
}

/// 톤 타일: 소리의 느낌을 파형 모양으로 보여 준다.
private enum ToneStyle: String, CaseIterable, Identifiable {
    case bright, dark, warm, sharp, clean, gritty

    var id: String { rawValue }

    var label: String {
        switch self {
        case .bright: return L("밝게")
        case .dark: return L("어둡게")
        case .warm: return L("따뜻하게")
        case .sharp: return L("날카롭게")
        case .clean: return L("깨끗하게")
        case .gritty: return L("거칠게")
        }
    }

    /// 0...1 위치에서 파형 높이 (-1...1). 밝게=잘고 빠른 물결, 어둡게=느리고 큰 물결, 날카롭게=톱니, 거칠게=잡음 섞임.
    func value(at x: Double) -> Double {
        let turn = 2 * Double.pi
        switch self {
        case .bright: return sin(x * turn * 7) * 0.45
        case .dark: return sin(x * turn * 1.5) * 0.95
        case .warm: return sin(x * turn * 3) * 0.8 + sin(x * turn * 6) * 0.15
        case .sharp: let t = x * 4; return (2 * (t - t.rounded(.down)) - 1) * 0.9
        case .clean: return sin(x * turn * 3) * 0.8
        case .gritty: return sin(x * turn * 3) * 0.6 + sin(x * 173) * 0.25 + sin(x * 91) * 0.2
        }
    }

    var lineWidth: CGFloat { self == .dark ? 4 : 2.5 }
}

private struct ToneWave: View {
    let style: ToneStyle

    var body: some View {
        Path { path in
            let width: CGFloat = 64, height: CGFloat = 32, steps = 80
            for index in 0...steps {
                let x = Double(index) / Double(steps)
                let point = CGPoint(x: x * width, y: height / 2 - CGFloat(style.value(at: x)) * (height / 2 - 2))
                if index == 0 { path.move(to: point) } else { path.addLine(to: point) }
            }
        }
        .stroke(style: StrokeStyle(lineWidth: style.lineWidth, lineCap: .round, lineJoin: .round))
        .frame(width: 64, height: 32)
    }
}

/// 표현 타일에 쓰는 악보 기호. 이름은 악보를 모르는 사람도 알아듣는 말로 붙였다.
private enum ExprSymbol: String, CaseIterable, Identifiable {
    case staccato, slur, accent, tenuto, crescendo, decrescendo

    var id: String { rawValue }

    var label: String {
        switch self {
        case .staccato: return L("끊어서")
        case .slur: return L("이어서")
        case .accent: return L("또렷하게")
        case .tenuto: return L("길게 끌어서")
        case .crescendo: return L("점점 커지게")
        case .decrescendo: return L("점점 작아지게")
        }
    }
}

/// 악보 기호를 그림 그대로 그린다 (스타카토 점, 슬러 호, 악센트, 테누토 선, 크레셴도·디크레셴도).
private struct ExprSymbolShape: View {
    let symbol: ExprSymbol

    var body: some View {
        switch symbol {
        case .staccato:
            HStack(spacing: 10) { ForEach(0..<3, id: \.self) { _ in Circle().frame(width: 9, height: 9) } }
        case .slur:
            Path { path in
                path.move(to: CGPoint(x: 0, y: 22))
                path.addQuadCurve(to: CGPoint(x: 52, y: 22), control: CGPoint(x: 26, y: -6))
            }
            .stroke(style: StrokeStyle(lineWidth: 3.5, lineCap: .round))
            .frame(width: 52, height: 26)
        case .accent:
            hairpin(width: 30, spread: 10, opensRight: true, flipped: true)
        case .tenuto:
            Capsule().frame(width: 44, height: 4)
        case .crescendo:
            hairpin(width: 52, spread: 12, opensRight: true, flipped: false)
        case .decrescendo:
            hairpin(width: 52, spread: 12, opensRight: false, flipped: false)
        }
    }

    /// 두 줄이 한 점에서 만나는 부등호 모양. accent는 짧고 굵게(>), 나머지는 길고 가늘게(<, >).
    private func hairpin(width: CGFloat, spread: CGFloat, opensRight: Bool, flipped: Bool) -> some View {
        Path { path in
            let tip = CGPoint(x: opensRight && !flipped ? 0 : width, y: spread)
            let far = opensRight && !flipped ? width : 0
            path.move(to: CGPoint(x: far, y: 0)); path.addLine(to: tip); path.addLine(to: CGPoint(x: far, y: spread * 2))
        }
        .stroke(style: StrokeStyle(lineWidth: flipped ? 4 : 3, lineCap: .round, lineJoin: .round))
        .frame(width: width, height: spread * 2)
    }
}

/// 칩을 가로로 채우고 넘치면 다음 줄로 넘기는 레이아웃.
private struct ChipFlow: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = arrange(width: proposal.width ?? .infinity, subviews: subviews)
        return CGSize(width: proposal.width ?? (rows.map(\.width).max() ?? 0),
                      height: rows.map(\.height).reduce(0, +) + spacing * CGFloat(max(0, rows.count - 1)))
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
        var rows = [Row()]
        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            let needed = rows[rows.count - 1].indices.isEmpty ? size.width : rows[rows.count - 1].width + spacing + size.width
            if needed > width, !rows[rows.count - 1].indices.isEmpty { rows.append(Row()) }
            var row = rows[rows.count - 1]
            row.width = row.indices.isEmpty ? size.width : row.width + spacing + size.width
            row.height = max(row.height, size.height)
            row.indices.append(index)
            rows[rows.count - 1] = row
        }
        return rows
    }
}
