import SwiftUI

/// 동기화 상태 한 줄 표시: ● 동기화됨 / 보내는 중 / 서버 연결 안 됨.
struct SyncStatusLabel: View {
    @ObservedObject private var sync = SyncClient.shared
    var compact = false

    var body: some View {
        HStack(spacing: 6) {
            Circle().fill(color).frame(width: 8, height: 8)
            if !compact || sync.pendingCount > 0 {
                Text(text).font(.caption.weight(.medium))
            }
        }
        .foregroundStyle(compact ? Color.white.opacity(0.7) : .secondary)
    }

    private var color: Color {
        switch sync.status {
        case .synced: return sync.pendingCount > 0 ? .yellow : .green
        case .syncing: return .yellow
        case .offline, .failed: return .red
        }
    }

    private var text: String {
        if sync.pendingCount > 0 { return "보내는 중 \(sync.pendingCount)" }
        switch sync.status {
        case .synced: return "동기화됨"
        case .syncing: return "동기화 중…"
        case .offline: return "서버 연결 안 됨 — 변경은 기기에 보관"
        case .failed(let message): return "동기화 오류: \(message)"
        }
    }
}
