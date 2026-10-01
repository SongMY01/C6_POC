import Foundation
import Combine

/// 여러 iPad 동기화 클라이언트. 기준 저장소는 Mac 서버(server/sync.py).
///
/// - 로컬에서 바뀐 내용은 저장소(FeedbackStore/PatchStore)가 먼저 반영하고(화면 즉시 갱신),
///   같은 내용을 작은 작업(op)으로 이 클라이언트에 넘긴다 → 서버로 전송.
/// - 3초마다(그리고 로컬 변경 직후) 서버 상태를 받아 버전이 바뀌었으면 저장소를 통째로 교체한다.
/// - 보낼 작업이 남아 있는 동안에는 받은 상태를 적용하지 않는다 — 아직 서버에 안 간
///   내 변경이 잠깐 사라졌다 돌아오는 깜빡임을 막기 위해.
/// - 서버에 연결이 안 되면 작업을 쌓아 두었다가 다시 연결되면 보낸다.
@MainActor
final class SyncClient: ObservableObject {
    static let shared = SyncClient()

    enum Status: Equatable {
        case offline
        case syncing
        case synced(Date)
        case failed(String)
    }

    /// 서버 상태 한 벌
    struct RemoteState: Decodable {
        let version: Int
        let songJobId: String?
        let feedback: [FeedbackItem]?
        let patches: [Patch]?
    }

    @Published private(set) var status: Status = .offline
    @Published private(set) var songJobId: String?
    @Published private(set) var pendingCount = 0

    private(set) var baseURL: URL?
    private var lastVersion = -1
    private var queue: [Pending] = []
    private var loopTask: Task<Void, Never>?
    private var isFlushing = false

    /// 서버에서 받은 상태를 각 저장소에 적용하는 콜백 (플레이어 화면이 연결한다).
    private var onRemoteFeedback: (([FeedbackItem]) -> Void)?
    private var onRemotePatches: (([Patch]) -> Void)?
    /// 녹음 파일을 어디에 둘지 (PatchStore가 알려준다)
    private var audioURLForPatch: ((Patch) -> URL)?

    /// 플레이어 화면이 열릴 때 저장소를 연결한다. 연결 즉시 서버 상태 전체를 다시 받아 적용한다.
    func attach(feedback: @escaping ([FeedbackItem]) -> Void,
                patches: @escaping ([Patch]) -> Void,
                audioURL: @escaping (Patch) -> URL) {
        onRemoteFeedback = feedback
        onRemotePatches = patches
        audioURLForPatch = audioURL
        lastVersion = -1
        Task { await syncNow() }
    }

    func detach() {
        onRemoteFeedback = nil
        onRemotePatches = nil
        audioURLForPatch = nil
    }

    private enum Pending {
        case op([String: Any])
        case upload(patchId: UUID, fileURL: URL)
    }

    private init() {}

    // MARK: - 연결

    func configure(baseURL: URL) {
        guard self.baseURL != baseURL else { return }
        self.baseURL = baseURL
        lastVersion = -1
        startLoop()
    }

    private func startLoop() {
        loopTask?.cancel()
        loopTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.syncNow()
                try? await Task.sleep(nanoseconds: 3_000_000_000)
            }
        }
    }

    /// 보낼 것을 보내고 최신 상태를 받아온다.
    func syncNow() async {
        guard baseURL != nil, !isFlushing else { return }
        isFlushing = true
        defer { isFlushing = false }
        if case .synced = status {} else { status = .syncing }
        do {
            try await flush()
            try await pull()
            status = .synced(Date())
        } catch {
            status = (error as? URLError) != nil ? .offline : .failed(error.localizedDescription)
        }
    }

    // MARK: - 보내기

    func send(_ type: String, _ payload: [String: Any]) {
        queue.append(.op(["type": type, "payload": payload]))
        pendingCount = queue.count
        Task { await syncNow() }
    }

    /// Codable 값을 서버로 보낼 JSON 객체로 바꾼다 (앱이 저장하는 모양 그대로).
    static func json<T: Encodable>(_ value: T) -> Any {
        guard let data = try? JSONEncoder().encode(value),
              let object = try? JSONSerialization.jsonObject(with: data) else { return NSNull() }
        return object
    }

    func uploadAudio(patchId: UUID, fileURL: URL) {
        queue.append(.upload(patchId: patchId, fileURL: fileURL))
        pendingCount = queue.count
    }

    private func flush() async throws {
        guard let baseURL else { return }
        while let next = queue.first {
            switch next {
            case .upload(let patchId, let fileURL):
                if let data = try? Data(contentsOf: fileURL) {
                    var request = URLRequest(url: baseURL.appendingPathComponent("sync/patches/\(patchId.uuidString)/audio"))
                    request.httpMethod = "PUT"
                    request.timeoutInterval = 30
                    request.httpBody = data
                    try await check(URLSession.shared.data(for: request))
                }
                queue.removeFirst()
            case .op:
                // 연속된 작업은 한 번에 묶어 보낸다
                var ops: [[String: Any]] = []
                while case .op(let op)? = queue.first {
                    ops.append(op)
                    queue.removeFirst()
                }
                var request = URLRequest(url: baseURL.appendingPathComponent("sync/ops"))
                request.httpMethod = "POST"
                request.timeoutInterval = 10
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                request.httpBody = try JSONSerialization.data(withJSONObject: ["ops": ops])
                do {
                    try await check(URLSession.shared.data(for: request))
                } catch {
                    queue.insert(contentsOf: ops.map { .op($0) }, at: 0)
                    pendingCount = queue.count
                    throw error
                }
            }
            pendingCount = queue.count
        }
    }

    // MARK: - 받기

    private func pull() async throws {
        guard let baseURL, queue.isEmpty else { return }
        var components = URLComponents(url: baseURL.appendingPathComponent("sync/state"), resolvingAgainstBaseURL: false)!
        components.queryItems = [URLQueryItem(name: "since", value: String(lastVersion))]
        var request = URLRequest(url: components.url!)
        request.timeoutInterval = 5
        let (data, _) = try await check(URLSession.shared.data(for: request))
        let remote = try JSONDecoder().decode(RemoteState.self, from: data)
        guard remote.version != lastVersion, let feedback = remote.feedback, let patches = remote.patches else { return }
        songJobId = remote.songJobId
        // 저장소가 아직 연결 안 됐거나(곡 선택 화면), 받는 사이에 새 로컬 변경이 생겼으면
        // 적용하지 않는다 — 버전을 기억하지 않으므로 다음 주기에 다시 받는다.
        guard let onRemoteFeedback, let onRemotePatches, queue.isEmpty else { return }
        await downloadMissingAudio(patches)
        guard queue.isEmpty else { return }
        lastVersion = remote.version
        onRemotePatches(patches)
        onRemoteFeedback(feedback)
    }

    private func downloadMissingAudio(_ patches: [Patch]) async {
        guard let baseURL, let audioURLForPatch else { return }
        for patch in patches {
            let dest = audioURLForPatch(patch)
            guard !FileManager.default.fileExists(atPath: dest.path) else { continue }
            let url = baseURL.appendingPathComponent("sync/patches/\(patch.id.uuidString)/audio")
            guard let (tmp, response) = try? await URLSession.shared.download(from: url),
                  (response as? HTTPURLResponse)?.statusCode == 200 else { continue }
            try? FileManager.default.moveItem(at: tmp, to: dest)
        }
    }

    @discardableResult
    private func check(_ result: (Data, URLResponse)) throws -> (Data, URLResponse) {
        guard let http = result.1 as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
        return result
    }
}
