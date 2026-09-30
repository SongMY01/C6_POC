import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @StateObject private var viewModel = SessionViewModel()
    @State private var showingFilePicker = false
    @State private var showingServerSettings = false

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
                Section("분리 서버 주소") {
                    TextField("http://127.0.0.1:8756", text: $viewModel.serverURLText)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    Text("시뮬레이터: 127.0.0.1 그대로 사용\n실기기: 같은 Wi-Fi의 Mac IP로 변경")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("서버 설정")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("완료") { showingServerSettings = false }
                }
            }
        }
        .presentationDetents([.medium])
    }
}

#Preview {
    ContentView()
}
