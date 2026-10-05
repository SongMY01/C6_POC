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
        /// 진행자가 Mac에서 정한 테스트 버전 (없으면 nil)
        let variant: String?
        let reactions: [FeedbackReaction]?
        let titles: [PeerTitle]?
        /// 이번 합주 전에 연습을 시작한 사람들 (역할 id)
        let teamStarted: [String]?
        /// 다음 합주 시각 (epoch 초)
        let nextRehearsal: Double?
        let feedback: [FeedbackItem]?
        let patches: [Patch]?
    }

    @Published private(set) var status: Status = .offline
    @Published private(set) var songJobId: String?
    @Published private(set) var pendingCount = 0

    // 버전 B: 함께하는 느낌
    @Published private(set) var reactions: [FeedbackReaction] = []
    @Published private(set) var titles: [PeerTitle] = []
    @Published private(set) var teamStarted: Set<String> = []
    @Published private(set) var nextRehearsal: Date?
    /// 나를 뺀 다른 사람들의 지금 상태
    @Published private(set) var othersPresence: [PresenceInfo] = []
    /// 이 iPad가 지금 뭘 하는지 알려 주는 함수 (플레이어 화면이 채운다). nil이면 접속만 한 상태.
    var activityProvider: (() -> String?)?

    private(set) var baseURL: URL?
    private var lastVersion = -1
    private var queue: [Pending] = []
    private var loopTask: Task<Void, Never>?
    private var isFlushing = false
    /// 서버로 보낼 행동 기록 (유저테스트 분석용). 연결이 안 되면 쌓아 두었다 보낸다.
    private var eventQueue: [[String: Any]] = []

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
            try await flushEvents()
            try await pull()
            await syncPresence()
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

    /// 행동 기록 한 줄. 기기·역할·테스트 버전을 함께 남긴다 (tools/test_report.py로 요약).
    func log(_ name: String, _ extra: [String: Any] = [:]) {
        var event: [String: Any] = [
            "name": name,
            "device": Self.deviceId,
            "role": DeviceRole.current,
            "variant": VariantStore.shared.current.id,
            "clientTime": Date().timeIntervalSince1970,
        ]
        if !extra.isEmpty { event["extra"] = extra }
        eventQueue.append(event)
        reportStartedIfNeeded(name)
        Task { await syncNow() }
    }

    /// 기기를 구분하는 짧은 id (앱을 지우기 전까지 유지)
    private static let deviceId: String = {
        let key = "deviceId"
        if let saved = UserDefaults.standard.string(forKey: key) { return saved }
        let new = String(UUID().uuidString.prefix(4)).lowercased()
        UserDefaults.standard.set(new, forKey: key)
        return new
    }()

    // MARK: - 버전 B: 리액션 · 칭호 · 현황

    /// 리액션을 누른다. 같은 사람이 같은 이모지를 다시 누르면 취소(토글).
    func toggleReaction(_ emoji: String, feedbackId: UUID) {
        let me = DeviceRole.current
        if let mine = reactions.first(where: { $0.feedbackId == feedbackId && $0.emoji == emoji && $0.author == me }) {
            reactions.removeAll { $0.id == mine.id }
            send("reaction.remove", ["id": mine.id.uuidString])
        } else {
            let reaction = FeedbackReaction(id: UUID(), feedbackId: feedbackId, emoji: emoji, author: me, createdAt: Date())
            reactions.append(reaction)
            send("reaction.add", ["reaction": Self.json(reaction)])
            log("reaction_added", ["emoji": emoji])
        }
    }

    func giveTitle(_ title: String, to session: String) {
        let item = PeerTitle(id: UUID(), toSession: session, title: title, from: DeviceRole.current, createdAt: Date())
        titles.append(item)
        send("title.give", ["title": Self.json(item)])
        log("title_given", ["to": session, "title": title])
    }

    /// 그 세션이 가장 최근에 받은 칭호
    func latestTitle(for session: String) -> PeerTitle? {
        titles.filter { $0.toSession == session }.max { $0.createdAt < $1.createdAt }
    }

    /// 연습을 시작한 사람으로 기록한다 (한 번만 보냄). 세션 연주자만 센다.
    private var reportedStarted = false
    private func reportStartedIfNeeded(_ name: String) {
        guard !reportedStarted, !DeviceRole.isLeader,
              ["practice_start", "record_start", "attempt_added"].contains(name) else { return }
        reportedStarted = true
        teamStarted.insert(DeviceRole.current)
        send("member.started", ["role": DeviceRole.current])
    }

    /// 내 상태를 알리고 다른 사람들의 지금 상태를 받는다.
    private func syncPresence() async {
        guard let baseURL else { return }
        var request = URLRequest(url: baseURL.appendingPathComponent("sync/presence"))
        request.httpMethod = "POST"
        request.timeoutInterval = 4
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        var body: [String: Any] = ["device": Self.deviceId, "role": DeviceRole.current]
        if let activity = activityProvider?() { body["activity"] = activity }
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let decoded = try? JSONDecoder().decode(PresenceResponse.self, from: data) else { return }
        othersPresence = decoded.presence.filter { $0.device != Self.deviceId && $0.isActive }
    }

    private struct PresenceResponse: Decodable { let presence: [PresenceInfo] }

    private func flushEvents() async throws {
        guard let baseURL, !eventQueue.isEmpty else { return }
        let batch = eventQueue
        var request = URLRequest(url: baseURL.appendingPathComponent("sync/events"))
        request.httpMethod = "POST"
        request.timeoutInterval = 10
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["events": batch])
        try await check(URLSession.shared.data(for: request))
        eventQueue.removeFirst(min(batch.count, eventQueue.count))
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
        VariantStore.shared.serverVariantId = remote.variant
        // 새 로컬 변경을 아직 서버에 못 보냈으면 덮어쓰지 않는다 (방금 누른 리액션이 깜빡이지 않게).
        if queue.isEmpty {
            reactions = remote.reactions ?? []
            titles = remote.titles ?? []
            teamStarted = Set(remote.teamStarted ?? [])
            nextRehearsal = remote.nextRehearsal.map { Date(timeIntervalSince1970: $0) }
        }
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
