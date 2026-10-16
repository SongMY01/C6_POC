import Foundation

public struct Patch: Identifiable, Codable, Equatable, Sendable {
    public let id: UUID
    public var sessionId: String
    public var startTime: TimeInterval
    public var endTime: TimeInterval
    public var createdAt: Date
    /// 녹음 파일의 몇 초 지점부터 startTime에 재생할지. 패치 왼쪽 끝을 잘라내면 늘어난다.
    public var sourceStart: TimeInterval = 0
    /// 곡에 반영된(채택된) 버전인지. 피드백에서 "통과"한 시도의 패치가 채택되고,
    /// 채택된 패치는 곡을 열 때 기본으로 켜진다. 같은 세션에서 구간이 겹치는 채택 패치는 하나뿐.
    public var isAdopted: Bool = false
    /// 리더가 피드백(음·연주)에 붙인 시범 녹음. 세션의 재녹음 버전 목록·레인에는 나오지 않는다.
    public var isReference: Bool = false

    public var timeRange: ClosedRange<TimeInterval> {
        startTime...endTime
    }
    public var duration: TimeInterval { endTime - startTime }

    public init(id: UUID = UUID(), sessionId: String, startTime: TimeInterval, endTime: TimeInterval,
                createdAt: Date = Date(), sourceStart: TimeInterval = 0, isAdopted: Bool = false, isReference: Bool = false) {
        self.id = id
        self.sessionId = sessionId
        self.startTime = startTime
        self.endTime = endTime
        self.createdAt = createdAt
        self.sourceStart = sourceStart
        self.isAdopted = isAdopted
        self.isReference = isReference
    }
}

extension Patch {
    /// sourceStart가 없던 예전 manifest도 읽을 수 있게 한다.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        sessionId = try c.decode(String.self, forKey: .sessionId)
        startTime = try c.decode(TimeInterval.self, forKey: .startTime)
        endTime = try c.decode(TimeInterval.self, forKey: .endTime)
        createdAt = try c.decode(Date.self, forKey: .createdAt)
        sourceStart = try c.decodeIfPresent(TimeInterval.self, forKey: .sourceStart) ?? 0
        isAdopted = try c.decodeIfPresent(Bool.self, forKey: .isAdopted) ?? false
        isReference = try c.decodeIfPresent(Bool.self, forKey: .isReference) ?? false
    }
}

/// 재녹음 패치 저장소. 녹음 파일과 목록을 로컬에 두고, 바뀐 내용은 SyncClient로 서버에 보낸다
/// (새 녹음은 파일까지 업로드). 다른 기기의 변경은 replaceAll로 들어온다.
