import SwiftUI

// MARK: - 목업: "종류를 먼저 고르면, 그 종류에 맞는 입력창이 열린다"
//
// 인터페이스 확인용 목업이다. 아무것도 저장·전송·재생하지 않는다 (데이터 모델·동기화·오디오와 연결 안 됨).
// 기존 FeedbackComposerSheet(칩 질문 방식)와 따로 두고 나란히 비교해 볼 수 있게 한 별도 화면.

/// 목업에서 보여 줄 피드백 종류와 각 종류의 전용 입력창.
private enum MockKind: String, CaseIterable, Identifiable {
    case tempo, mix, overlap, pitch, tone, promise, praise

    var id: String { rawValue }

    var label: String {
        switch self {
        case .tempo: return "박자"
        case .mix: return "볼륨·밸런스"
        case .overlap: return "음역 겹침"
        case .pitch: return "음·음정"
        case .tone: return "표현·톤"
        case .promise: return "약속"
        case .praise: return "칭찬"
        }
    }

    var hint: String {
        switch self {
        case .tempo: return "밀려요 / 당겨요"
        case .mix: return "소리가 커요 / 작아요"
        case .overlap: return "두 악기가 겹쳐요"
        case .pitch: return "음이 틀려요"
        case .tone: return "세게 / 부드럽게"
        case .promise: return "엔딩 신호, 킥 위치"
        case .praise: return "여기 좋았어요"
        }
    }

    var icon: String {
        switch self {
        case .tempo: return "metronome"
        case .mix: return "slider.vertical.3"
        case .overlap: return "square.on.square"
        case .pitch: return "pianokeys"
        case .tone: return "waveform.path"
        case .promise: return "hand.raised"
        case .praise: return "hands.clap"
        }
    }

    var color: Color {
        switch self {
        case .tempo: return .orange
        case .mix: return .purple
        case .overlap: return .teal
        case .pitch: return .pink
        case .tone: return .indigo
        case .promise: return .blue
        case .praise: return .green
        }
    }

    /// 받는 사람에게 같이 가는 "이렇게 시작해 보세요" (종류가 정하는 연습 방법의 예시)
    var startingTip: String {
        switch self {
        case .tempo: return "70% 속도로 클릭 켜고 2번 → 원래 속도로 1번"
        case .mix: return "'원하는 믹스'로 한 번 듣고 → 내 소리 크기를 맞춰서 한 번 쳐 보기"
        case .overlap: return "두 세션만 듣고 → 내 음역을 바꿔서 한 번 쳐 보기"
        case .pitch: return "레퍼런스와 번갈아 들은 뒤 → 그 구간만 천천히 한 번"
        case .tone: return "고른 느낌을 떠올리며 한 번 → 녹음해서 비교"
        case .promise: return "확인(👍)만 누르면 끝이에요 — 연습 과제가 아니에요"
        case .praise: return "좋았던 점이에요. 그대로 가면 돼요 🙌"
        }
    }
}

struct TypedFeedbackMockSheet: View {
    let timeRange: ClosedRange<TimeInterval>
    let tracks: [StemTrack]
    let onClose: () -> Void

    // 공통
    @State private var targets: Set<String> = []
    @State private var kind: MockKind?
    @State private var memo = ""
    @State private var voiceMemoAttached = false
    @State private var showSent = false
    @State private var toast: String?

    // 박자
    @State private var tempoOffset: Double = 0
    @State private var beatSelection: Set<Int> = []
    @State private var tapTimes: [Date] = []

    // 볼륨·밸런스
    @State private var mix: [String: Double] = [:]
    @State private var mixReasons: Set<String> = []
    @State private var hearingWantedMix = false

    // 음역 겹침
    @State private var overlapA: String?
    @State private var overlapB: String?
    @State private var overlapFix: Int?

    // 음·음정
    @State private var pitchMode = 0
    @State private var mockRecording = false
    @State private var recordedSeconds: Int?
    @State private var notes: [String] = []
    @State private var sharpOn = false

    // 표현·톤
    @State private var toneSoft: Double = 0.5
    @State private var toneLength: Double = 0.5
    @State private var toneTags: Set<String> = []
    @State private var referenceLink = ""

    // 약속
    @State private var promisePreset: String?
    @State private var promiseText = ""
    @State private var promiseAudience: Set<String> = []

    // 칭찬
    @State private var praiseEmoji: String?
    @State private var praiseText = ""

    private let baselineMix = 0.8

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    mockBanner
                    rangeAndTargets
                    kindPicker
                    if let kind {
                        inputCard(for: kind)
                        commonInputs
                        recipientPreview(for: kind)
                    }
                }
                .padding(20)
                .frame(maxWidth: 760)
                .frame(maxWidth: .infinity)
            }
            .background(Color(uiColor: .systemGroupedBackground))
            .navigationTitle("종류별로 쓰기")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("닫기", action: onClose) }
                ToolbarItem(placement: .confirmationAction) {
                    Button("보내기") { showSent = true }.disabled(kind == nil)
                }
            }
            .overlay(alignment: .bottom) {
                if let toast {
                    Text(toast)
                        .font(.subheadline.weight(.semibold))
                        .padding(.horizontal, 16).padding(.vertical, 10)
                        .background(Capsule().fill(Color.black.opacity(0.82)))
                        .foregroundStyle(.white)
                        .padding(.bottom, 24)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .animation(.easeOut(duration: 0.2), value: toast)
            .alert("목업이에요", isPresented: $showSent) {
                Button("확인", action: onClose)
            } message: {
                Text("인터페이스 확인용이라 저장하거나 전송하지 않아요.")
            }
        }
    }

    // MARK: 위쪽

    private var mockBanner: some View {
        HStack(spacing: 8) {
            Image(systemName: "hammer.fill")
            Text("목업 — 화면만 확인하는 용도예요. 아무것도 저장·재생되지 않아요.")
                .font(.footnote.weight(.semibold))
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.yellow.opacity(0.25)))
    }

    private var rangeAndTargets: some View {
        card {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Label("\(formatTime(timeRange.lowerBound)) ~ \(formatTime(timeRange.upperBound))", systemImage: "scope")
                        .font(.headline.monospacedDigit())
                    Spacer()
                    Text("지금 잡힌 구간").font(.caption).foregroundStyle(.secondary)
                }
                Divider()
                Text("받는 세션").font(.subheadline.weight(.semibold))
                MockFlow(spacing: 8) {
                    chip("👥 전체", isOn: targets.isEmpty) { targets.removeAll() }
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
                    Text("어떤 피드백이에요?").font(.headline)
                    Spacer()
                    if kind == nil { Text("먼저 종류를 골라 주세요").font(.caption).foregroundStyle(.secondary) }
                }
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 10)], spacing: 10) {
                    ForEach(MockKind.allCases) { item in
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
    private func inputCard(for kind: MockKind) -> some View {
        card(accent: kind.color) {
            VStack(alignment: .leading, spacing: 14) {
                Label("\(kind.label) 입력", systemImage: kind.icon)
                    .font(.headline)
                    .foregroundStyle(kind.color)
                switch kind {
                case .tempo: tempoInput
                case .mix: mixInput
                case .overlap: overlapInput
                case .pitch: pitchInput
                case .tone: toneInput
                case .promise: promiseInput
                case .praise: praiseInput
                }
            }
        }
    }

    // 박자: 방향 + 정도 슬라이더, 어느 박인지, 탭으로 원하는 박자 알려주기
    private var tempoInput: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(spacing: 4) {
                Text(tempoLabel).font(.title3.weight(.bold)).foregroundStyle(tempoOffset == 0 ? Color.secondary : Color.orange)
                Slider(value: $tempoOffset, in: -2...2, step: 1).tint(Color.secondary.opacity(0.35))
                HStack {
                    Text("많이").frame(maxWidth: .infinity, alignment: .leading)
                    Text("조금")
                    Text("딱 맞아요").frame(maxWidth: .infinity)
                    Text("조금")
                    Text("많이").frame(maxWidth: .infinity, alignment: .trailing)
                }
                .font(.caption2).foregroundStyle(.secondary)
                HStack {
                    Text("◀ 뒤져요").font(.caption.weight(.semibold))
                    Spacer()
                    Text("앞서요 ▶").font(.caption.weight(.semibold))
                }
            }
            Divider()
            Text("어느 박이에요?").font(.subheadline.weight(.semibold))
            MockFlow(spacing: 8) {
                chip("구간 전체", isOn: beatSelection.isEmpty) { beatSelection.removeAll() }
                ForEach(1...4, id: \.self) { beat in
                    chip("\(beat)박", isOn: beatSelection.contains(beat)) { toggle(&beatSelection, beat) }
                }
            }
            Divider()
            Text("원하는 박자를 탭으로 알려주기").font(.subheadline.weight(.semibold))
            HStack(spacing: 12) {
                Button {
                    tapTimes.append(Date())
                    if tapTimes.count > 8 { tapTimes.removeFirst() }
                } label: {
                    Text("TAP")
                        .font(.title3.weight(.heavy))
                        .frame(width: 96, height: 56)
                        .background(RoundedRectangle(cornerRadius: 12).fill(Color.orange.opacity(0.18)))
                }
                .buttonStyle(.plain)
                VStack(alignment: .leading, spacing: 2) {
                    Text(tappedBPM.map { "약 \($0) BPM" } ?? "박자에 맞춰 눌러 보세요")
                        .font(.headline.monospacedDigit())
                    Text(tapTimes.isEmpty ? "리더가 원하는 템포를 그대로 전달해요" : "\(tapTimes.count)번 탭함")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                if !tapTimes.isEmpty { Button("지우기") { tapTimes.removeAll() }.font(.footnote) }
            }
        }
    }

    // 볼륨·밸런스: 직접 섞은 "원하는 믹스" 첨부
    private var mixInput: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("이렇게 들리면 좋겠어요 — 직접 섞어 보세요").font(.subheadline.weight(.semibold))
            ForEach(tracks) { track in
                let value = mixValue(track.id)
                HStack(spacing: 10) {
                    Text("\(track.instrumentEmoji) \(track.displayName)")
                        .font(.subheadline).frame(width: 96, alignment: .leading)
                    Slider(value: Binding(get: { mixValue(track.id) }, set: { mix[track.id] = $0 }), in: 0...1)
                        .tint(track.tint)
                    Text(mixDeltaText(value))
                        .font(.caption.weight(.bold)).frame(width: 36)
                        .foregroundStyle(abs(value - baselineMix) < 0.1 ? Color.secondary : Color.purple)
                }
            }
            HStack(spacing: 10) {
                Picker("믹스", selection: $hearingWantedMix) {
                    Text("처음 믹스").tag(false)
                    Text("원하는 믹스").tag(true)
                }
                .pickerStyle(.segmented)
                Button {
                    showToast("목업: 실제로는 이 믹스로 구간이 재생돼요")
                } label: { Label("들어보기", systemImage: "play.fill") }
                    .buttonStyle(.bordered)
                Button("되돌리기") { mix.removeAll() }.font(.footnote)
            }
            Divider()
            Text("왜 그렇게 들려요?").font(.subheadline.weight(.semibold))
            MockFlow(spacing: 8) {
                ForEach(["세게 쳐서", "원래 소리가 작아서", "밴드에서 비중이", "녹음 위치가 달라서"], id: \.self) { reason in
                    chip(reason, isOn: mixReasons.contains(reason)) { toggle(&mixReasons, reason) }
                }
            }
        }
    }

    // 음역 겹침: 두 세션을 맞대고 처방 고르기
    private var overlapInput: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                sessionMenu(title: "첫 번째", selection: $overlapA)
                Image(systemName: "arrow.left.arrow.right").foregroundStyle(.secondary)
                sessionMenu(title: "두 번째", selection: $overlapB)
            }
            Divider()
            Text("어떻게 하면 좋을까요?").font(.subheadline.weight(.semibold))
            MockFlow(spacing: 8) {
                ForEach(Array(overlapFixes.enumerated()), id: \.offset) { index, text in
                    chip(text, isOn: overlapFix == index) { overlapFix = index }
                }
            }
            Button {
                showToast("목업: 실제로는 이 두 세션만 켜서 구간을 재생해요")
            } label: { Label("두 세션만 듣기", systemImage: "headphones") }
                .buttonStyle(.bordered)
                .disabled(overlapA == nil || overlapB == nil)
        }
    }

    // 음·음정: 시범 녹음 또는 건반으로 음 짚기
    private var pitchInput: some View {
        VStack(alignment: .leading, spacing: 14) {
            Picker("방식", selection: $pitchMode) {
                Text("🎙 시범 녹음").tag(0)
                Text("🎹 건반으로 짚기").tag(1)
            }
            .pickerStyle(.segmented)
            if pitchMode == 0 {
                HStack(spacing: 14) {
                    Button {
                        if mockRecording { recordedSeconds = 4 } else { recordedSeconds = nil }
                        mockRecording.toggle()
                    } label: {
                        Image(systemName: mockRecording ? "stop.fill" : "circle.fill")
                            .font(.title)
                            .foregroundStyle(.red)
                            .frame(width: 64, height: 64)
                            .background(Circle().fill(Color.red.opacity(0.12)))
                    }
                    .buttonStyle(.plain)
                    VStack(alignment: .leading, spacing: 6) {
                        Text(mockRecording ? "● 녹음 중…" : (recordedSeconds.map { "시범 녹음 \($0)초 첨부됨" } ?? "맞는 연주를 직접 쳐서 녹음해요"))
                            .font(.subheadline.weight(.semibold))
                        MockWaveform(active: mockRecording, filled: recordedSeconds != nil)
                            .frame(height: 28)
                    }
                    if recordedSeconds != nil && !mockRecording {
                        Button { showToast("목업: 실제로는 시범 녹음이 재생돼요") } label: { Image(systemName: "play.circle.fill").font(.title2) }
                    }
                }
            } else {
                Text("맞는 음을 차례로 눌러 주세요").font(.caption).foregroundStyle(.secondary)
                HStack(spacing: 6) {
                    ForEach(["C", "D", "E", "F", "G", "A", "B"], id: \.self) { note in
                        Button {
                            notes.append(note + (sharpOn ? "♯" : ""))
                        } label: {
                            Text(note)
                                .font(.headline)
                                .frame(maxWidth: .infinity, minHeight: 64, alignment: .bottom)
                                .padding(.bottom, 8)
                                .background(RoundedRectangle(cornerRadius: 6).fill(Color.white))
                                .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.secondary.opacity(0.4)))
                                .foregroundStyle(.black)
                        }
                        .buttonStyle(.plain)
                    }
                }
                HStack {
                    Toggle("♯ 반음 올림", isOn: $sharpOn).toggleStyle(.button).font(.footnote)
                    Spacer()
                    Text(notes.isEmpty ? "아직 없음" : notes.joined(separator: " → "))
                        .font(.headline.monospaced())
                    if !notes.isEmpty { Button("지우기") { notes.removeAll() }.font(.footnote) }
                }
            }
        }
    }

    // 표현·톤: 슬라이더 + 느낌 태그 + 레퍼런스 링크
    private var toneInput: some View {
        VStack(alignment: .leading, spacing: 14) {
            axisSlider(left: "세게", right: "부드럽게", value: $toneSoft)
            axisSlider(left: "짧게 끊어서", right: "길게 이어서", value: $toneLength)
            Divider()
            Text("느낌").font(.subheadline.weight(.semibold))
            MockFlow(spacing: 8) {
                ForEach(["깨끗하게", "거칠게", "밝게", "어둡게", "여유 있게", "또렷하게"], id: \.self) { tag in
                    chip(tag, isOn: toneTags.contains(tag)) { toggle(&toneTags, tag) }
                }
            }
            HStack(spacing: 8) {
                Image(systemName: "link").foregroundStyle(.secondary)
                TextField("참고할 영상·곡 링크 (선택)", text: $referenceLink)
                    .textInputAutocapitalization(.never).autocorrectionDisabled()
            }
            .padding(10)
            .background(RoundedRectangle(cornerRadius: 10).fill(Color.secondary.opacity(0.1)))
        }
    }

    // 약속: 연습 과제가 아니라 확인 카드
    private var promiseInput: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("무엇을 약속해요?").font(.subheadline.weight(.semibold))
            MockFlow(spacing: 8) {
                ForEach(["엔딩 신호", "킥 위치", "솔로 순서", "카운트", "직접 쓰기"], id: \.self) { preset in
                    chip(preset, isOn: promisePreset == preset) { promisePreset = preset }
                }
            }
            TextField("내용 (예: 드럼이 4박 카운트 후 심벌)", text: $promiseText, axis: .vertical)
                .lineLimit(2...4)
                .padding(10)
                .background(RoundedRectangle(cornerRadius: 10).fill(Color.secondary.opacity(0.1)))
            Divider()
            Text("확인이 필요한 사람").font(.subheadline.weight(.semibold))
            MockFlow(spacing: 8) {
                chip("전원", isOn: promiseAudience.isEmpty) { promiseAudience.removeAll() }
                ForEach(tracks) { track in
                    chip("\(track.instrumentEmoji) \(track.displayName)", isOn: promiseAudience.contains(track.id)) {
                        toggle(&promiseAudience, track.id)
                    }
                }
            }
            Label("확인(👍)을 받으면 끝나요. 연습 과제 목록에는 안 들어가요.", systemImage: "info.circle")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    // 칭찬: 이모지 한 번
    private var praiseInput: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                ForEach(["🔥", "🎯", "👏", "💪"], id: \.self) { emoji in
                    Button { praiseEmoji = emoji } label: {
                        Text(emoji).font(.largeTitle)
                            .frame(width: 64, height: 64)
                            .background(Circle().fill(praiseEmoji == emoji ? Color.green.opacity(0.25) : Color.secondary.opacity(0.12)))
                            .overlay(Circle().stroke(praiseEmoji == emoji ? Color.green : .clear, lineWidth: 2))
                    }
                    .buttonStyle(.plain)
                }
            }
            TextField("한마디 (선택) — 예: 이번 필인 최고였어요!", text: $praiseText)
                .padding(10)
                .background(RoundedRectangle(cornerRadius: 10).fill(Color.secondary.opacity(0.1)))
        }
    }

    // MARK: 공통 입력 (한 줄 메모 · 음성 메모)

    private var commonInputs: some View {
        card {
            VStack(alignment: .leading, spacing: 12) {
                Text("덧붙이기 (선택)").font(.subheadline.weight(.semibold))
                TextField("한 줄 메모", text: $memo)
                    .padding(10)
                    .background(RoundedRectangle(cornerRadius: 10).fill(Color.secondary.opacity(0.1)))
                HStack(spacing: 12) {
                    Button {
                        voiceMemoAttached.toggle()
                    } label: {
                        Label(voiceMemoAttached ? "음성 메모 0:07 첨부됨" : "음성 메모 남기기", systemImage: voiceMemoAttached ? "mic.fill" : "mic")
                    }
                    .buttonStyle(.bordered)
                    .tint(voiceMemoAttached ? .red : .accentColor)
                    if voiceMemoAttached {
                        MockWaveform(active: false, filled: true).frame(height: 22)
                        Button { voiceMemoAttached = false } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary) }
                    }
                }
            }
        }
    }

    // MARK: 받는 사람 화면 미리보기

    private func recipientPreview(for kind: MockKind) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("받는 사람에게는 이렇게 보여요").font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)
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
                if !memo.isEmpty { Text("“\(memo)”").font(.callout).foregroundStyle(.secondary) }
                if voiceMemoAttached { Label("음성 메모 0:07", systemImage: "waveform").font(.caption).foregroundStyle(.secondary) }
                Divider()
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "lightbulb.fill").foregroundStyle(.yellow)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("이렇게 시작해 보세요").font(.caption.weight(.bold))
                        Text(kind.startingTip).font(.footnote)
                    }
                }
                HStack {
                    Spacer()
                    Text("▶ 바로 해보기").font(.footnote.weight(.bold))
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
        if targets.isEmpty { return "전체" }
        return tracks.filter { targets.contains($0.id) }.map(\.displayName).joined(separator: ", ")
    }

    private func summary(for kind: MockKind) -> String {
        switch kind {
        case .tempo:
            if tempoOffset == 0 { return "박자는 잘 맞아요." }
            let beats = beatSelection.isEmpty ? "구간 전체에서" : beatSelection.sorted().map { "\($0)박" }.joined(separator: ", ") + "에서"
            var text = "\(beats) \(tempoLabel)"
            if let bpm = tappedBPM { text += " · 원하는 템포 약 \(bpm) BPM" }
            return text
        case .mix:
            let changed = tracks.compactMap { track -> String? in
                let value = mixValue(track.id)
                if abs(value - baselineMix) < 0.1 { return nil }
                return "\(track.displayName) \(value > baselineMix ? "↑" : "↓")"
            }
            var text = changed.isEmpty ? "믹스를 움직여서 원하는 소리를 보여 주세요." : "이렇게 섞어 주세요: " + changed.joined(separator: ", ")
            if !mixReasons.isEmpty { text += " (" + mixReasons.sorted().joined(separator: " · ") + ")" }
            return text
        case .overlap:
            guard let a = name(of: overlapA), let b = name(of: overlapB) else { return "겹치는 두 세션을 골라 주세요." }
            let fix = overlapFix.map { overlapFixes[$0] } ?? "어떻게 할지 골라 주세요"
            return "\(a)과(와) \(b)의 음역이 겹쳐요 → \(fix)"
        case .pitch:
            if pitchMode == 0 {
                return recordedSeconds.map { "맞는 연주를 시범 녹음으로 남겼어요 (\($0)초)" } ?? "시범 녹음을 남겨 주세요."
            }
            return notes.isEmpty ? "맞는 음을 건반으로 짚어 주세요." : "맞는 음: " + notes.joined(separator: " → ")
        case .tone:
            var parts: [String] = []
            if toneSoft < 0.4 { parts.append("더 세게") } else if toneSoft > 0.6 { parts.append("더 부드럽게") }
            if toneLength < 0.4 { parts.append("짧게 끊어서") } else if toneLength > 0.6 { parts.append("길게 이어서") }
            parts += toneTags.sorted()
            return parts.isEmpty ? "원하는 느낌을 골라 주세요." : parts.joined(separator: " · ")
        case .promise:
            let text = promiseText.trimmingCharacters(in: .whitespacesAndNewlines)
            let head = promisePreset ?? "약속"
            return text.isEmpty ? "\(head) — 내용을 적어 주세요." : "\(head): \(text)"
        case .praise:
            let text = praiseText.trimmingCharacters(in: .whitespacesAndNewlines)
            return "\(praiseEmoji ?? "👏") \(text.isEmpty ? "여기 좋았어요!" : text)"
        }
    }

    // MARK: 계산 · 보조

    private var tempoLabel: String {
        switch tempoOffset {
        case ...(-2): return "많이 뒤져요"
        case -1: return "조금 뒤져요"
        case 1: return "조금 앞서요"
        case 2...: return "많이 앞서요"
        default: return "딱 맞아요"
        }
    }

    private var tappedBPM: Int? {
        guard tapTimes.count >= 3 else { return nil }
        let gaps = zip(tapTimes.dropFirst(), tapTimes).map { $0.timeIntervalSince($1) }
        let average = gaps.reduce(0, +) / Double(gaps.count)
        return average > 0 ? Int((60 / average).rounded()) : nil
    }

    private func mixValue(_ id: String) -> Double { mix[id] ?? baselineMix }

    private func mixDeltaText(_ value: Double) -> String {
        let delta = Int(((value - baselineMix) * 10).rounded())
        return delta == 0 ? "–" : (delta > 0 ? "+\(delta)" : "\(delta)")
    }

    private var overlapFixes: [String] {
        let a = name(of: overlapA) ?? "첫 번째"
        let b = name(of: overlapB) ?? "두 번째"
        return ["\(b)을(를) 한 옥타브 올려요", "\(a)이(가) 비워 줘요", "번갈아 쳐요", "한쪽 소리를 줄여요"]
    }

    private func name(of id: String?) -> String? {
        guard let id else { return nil }
        return tracks.first { $0.id == id }?.displayName
    }

    private func toggle<T: Hashable>(_ set: inout Set<T>, _ value: T) {
        if set.contains(value) { set.remove(value) } else { set.insert(value) }
    }

    private func showToast(_ text: String) {
        toast = text
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { if toast == text { toast = nil } }
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

    private func sessionMenu(title: String, selection: Binding<String?>) -> some View {
        Menu {
            ForEach(tracks) { track in
                Button("\(track.instrumentEmoji) \(track.displayName)") { selection.wrappedValue = track.id }
            }
        } label: {
            HStack {
                Text(name(of: selection.wrappedValue) ?? title).font(.subheadline.weight(.semibold))
                Spacer()
                Image(systemName: "chevron.up.chevron.down").font(.caption)
            }
            .padding(12)
            .frame(maxWidth: .infinity)
            .background(RoundedRectangle(cornerRadius: 10).fill(Color.secondary.opacity(0.12)))
        }
    }

    private func axisSlider(left: String, right: String, value: Binding<Double>) -> some View {
        VStack(spacing: 2) {
            Slider(value: value, in: 0...1).tint(.indigo)
            HStack {
                Text(left).font(.caption.weight(.semibold))
                Spacer()
                Text(right).font(.caption.weight(.semibold))
            }
            .foregroundStyle(.secondary)
        }
    }
}

/// 녹음 파형 모양 장식 (목업). 녹음 중이면 움직이는 것처럼 보이게 높이를 흔든다.
private struct MockWaveform: View {
    let active: Bool
    let filled: Bool

    var body: some View {
        TimelineView(.animation(minimumInterval: 0.12, paused: !active)) { context in
            let tick = Int(context.date.timeIntervalSinceReferenceDate * 8)
            HStack(spacing: 3) {
                ForEach(0..<28, id: \.self) { index in
                    let base = abs(sin(Double(index) * 0.7)) * 0.7 + 0.2
                    let wobble = active ? abs(sin(Double(index + tick) * 0.9)) * 0.5 : 0
                    Capsule()
                        .fill(filled || active ? Color.red.opacity(0.75) : Color.secondary.opacity(0.35))
                        .frame(width: 3, height: 28 * min(1, base * (active ? 0.6 + wobble : 1)))
                }
            }
            .frame(maxHeight: .infinity)
        }
    }
}

/// 칩을 가로로 채우고 넘치면 다음 줄로 넘기는 레이아웃 (목업 전용).
private struct MockFlow: Layout {
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
