import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @StateObject private var viewModel = SessionViewModel()
    @State private var showingFilePicker = false
    @State private var showingServerSettings = false
    @ObservedObject private var sync = SyncClient.shared
    @AppStorage("deviceRole") private var role = DeviceRole.leader

    var body: some View {
        NavigationStack {
            Group {
                if viewModel.state == .ready {
                    // 트랙 뷰는 GarageBand처럼 화면 전체를 쓴다.
                    StemPlayerView(controller: viewModel.playerController, onReset: viewModel.reset)
                        .toolbar(.hidden, for: .navigationBar)
                } else {
                    VStack(spacing: 24) {
                        header

                        switch viewModel.state {
                        case .idle:
                            roleAndSharedSong
                            pickPrompt
                        case .fileSelected(let name):
                            fileSelectedView(name: name)
                        case .uploading:
                            statusView(title: "녹음 파일 업로드 중…", subtitle: nil)
                        case .separating:
                            statusView(title: "세션별로 분리하는 중…", subtitle: "보컬 · 드럼 · 베이스 · 기타 · 피아노")
                        case .downloadingStems(let done, let total):
                            statusView(title: "분리된 트랙 내려받는 중…", subtitle: "\(done)/\(total)")
                        case .ready:
                            EmptyView()
                        case .failed(let message):
                            failedView(message: message)
                        }

                        Spacer()
                    }
                    .padding(32)
                    .navigationTitle("합주 세션 분리 PoC")
                    .toolbar {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button {
                                showingServerSettings = true
                            } label: {
                                Image(systemName: "gearshape")
                            }
                        }
                    }
                }
            }
            .task {
                // 앱을 켜면 바로 서버를 찾아 동기화를 시작한다 (공유 곡 여부를 알기 위해)
                if !viewModel.isManualServer { await viewModel.detectServer() }
            }
            .sheet(isPresented: $showingServerSettings) {
                serverSettingsSheet
            }
            .fileImporter(
                isPresented: $showingFilePicker,
                allowedContentTypes: [.audio, .mpeg4Audio, .mp3, UTType(filenameExtension: "m4a") ?? .audio],
                allowsMultipleSelection: false
            ) { result in
                if case .success(let urls) = result, let url = urls.first {
                    viewModel.fileWasPicked(url)
                }
            }
        }
    }

    private var header: some View {
        VStack(spacing: 4) {
            Text("통합 녹음본 → 세션별 음원 분리")
                .font(.title2).bold()
            Text("Demucs(htdemucs_6s) 로컬 서버 연동 검증용 프로토타입")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    /// 이 iPad를 누가 쓰는지 고르고, 리더가 분리해 둔 공유 곡을 바로 여는 영역.
    private var roleAndSharedSong: some View {
        VStack(spacing: 16) {
            VStack(spacing: 8) {
                Text("이 iPad는").font(.subheadline).foregroundStyle(.secondary)
                Picker("역할", selection: $role) {
                    ForEach(DeviceRole.options, id: \.id) { option in
                        Text(option.label).tag(option.id)
                    }
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 640)
            }
            if sync.songJobId != nil || viewModel.hasCachedSong {
                Button {
                    viewModel.loadSharedSong()
                } label: {
                    Label("합주 곡 열기 (공유됨)", systemImage: "music.note.house")
                        .font(.title3.weight(.semibold))
                        .padding(.horizontal, 12).padding(.vertical, 6)
                }
                .buttonStyle(.borderedProminent)
                Text(sync.songJobId == nil
                     ? "서버에 연결되지 않았어요 — 이 기기에 저장된 곡을 엽니다."
                     : "리더가 분리해 둔 곡을 바로 엽니다. 새 녹음을 분리하려면 아래에서 파일을 고르세요.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            SyncStatusLabel()
            Divider().padding(.vertical, 8)
        }
    }

    private var pickPrompt: some View {
        VStack(spacing: 16) {
            Image(systemName: "waveform.badge.mic")
                .font(.system(size: 64))
                .foregroundStyle(.secondary)
            Text("합주 녹음 파일을 선택하세요")
                .font(.headline)
            Button("녹음 파일 선택") { showingFilePicker = true }
                .buttonStyle(.borderedProminent)
        }
    }

    private func fileSelectedView(name: String) -> some View {
        VStack(spacing: 16) {
            Label(name, systemImage: "doc.badge.waveform")
                .font(.headline)
            HStack {
                Button("다른 파일 선택") { showingFilePicker = true }
                    .buttonStyle(.bordered)
                Button("분리 시작") { viewModel.startSeparation() }
                    .buttonStyle(.borderedProminent)
            }
        }
    }

    private func statusView(title: String, subtitle: String?) -> some View {
        VStack(spacing: 12) {
            ProgressView()
                .scaleEffect(1.4)
            Text(title).font(.headline)
            if let subtitle {
                Text(subtitle).font(.subheadline).foregroundStyle(.secondary)
            }
        }
    }

    private func failedView(message: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 48))
                .foregroundStyle(.red)
            Text(message)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            Button("다시 시도") { viewModel.reset() }
                .buttonStyle(.borderedProminent)
        }
    }

    private var serverSettingsSheet: some View {
        NavigationStack {
            Form {
                Section {
                    if let status = viewModel.serverStatus {
                        Text(status).font(.subheadline)
                    }
                    Button("자동으로 찾기") { Task { await viewModel.detectServer() } }
                } header: {
                    Text("분리 서버")
                } footer: {
                    Text("분리를 시작할 때마다 아래 후보 중 응답하는 서버를 자동으로 고릅니다.")
                }
                Section("후보") {
                    ForEach(serverCandidates) { candidate in
                        Button {
                            viewModel.setManualServer(candidate.url)
                        } label: {
                            HStack {
                                Text(candidate.name)
                                Spacer()
                                Text(candidate.url).font(.caption.monospaced()).foregroundStyle(.secondary)
                                if viewModel.serverURLText == candidate.url {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }
                }
                Section("직접 입력") {
                    TextField("http://127.0.0.1:8756", text: Binding(
                        get: { viewModel.serverURLText },
                        set: { viewModel.setManualServer($0) }
                    ))
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                }
            }
            .navigationTitle("서버 설정")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("완료") { showingServerSettings = false }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .task { if !viewModel.isManualServer { await viewModel.detectServer() } }
    }
}

#Preview {
    ContentView()
}
