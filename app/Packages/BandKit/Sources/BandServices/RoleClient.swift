import BandFoundation
import Dependencies
import DependenciesMacros
import Foundation

/// 이 기기의 역할(리더 또는 세션). 지금의 `DeviceRole`(UserDefaults 전역)을 대신한다. 담당: App
@DependencyClient
public struct RoleClient: Sendable {
    public var current: @Sendable () -> Person = { .leader }
    public var set: @Sendable (_ person: Person) -> Void
}

extension RoleClient: DependencyKey {
    // TODO(App 담당): UserDefaults("deviceRole")에 저장하도록 구현한다.
    public static let liveValue = RoleClient()
    public static let testValue = RoleClient()
    public static let previewValue = RoleClient(current: { .leader }, set: { _ in })
}

extension DependencyValues {
    public var roleClient: RoleClient {
        get { self[RoleClient.self] }
        set { self[RoleClient.self] = newValue }
    }
}
