import SwiftUI

/// 설정 화면의 "테스트 버전" 섹션. 진행자용 — 기기별로 직접 고르거나 서버(Mac) 전환을 따르게 한다.
struct VariantPickerSection: View {
    @ObservedObject private var variants = VariantStore.shared

    var body: some View {
        Section {
            Button {
                variants.setOverride(nil)
            } label: {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("서버 따름 (권장)").foregroundStyle(.primary)
                        Text("진행자가 Mac에서 전환 → 지금: \(AppVariant.find(variants.serverVariantId)?.name ?? AppVariant.base.name)")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    if variants.isFollowingServer { Image(systemName: "checkmark") }
                }
            }
            ForEach(AppVariant.all) { variant in
                Button {
                    variants.setOverride(variant.id)
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("\(variant.code) · \(variant.name)").foregroundStyle(.primary)
                            Text(variant.summary).font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        if variants.overrideId == variant.id { Image(systemName: "checkmark") }
                    }
                }
            }
        } header: {
            Text("테스트 버전 (진행자용)")
        } footer: {
            Text("서버 따름이면 Mac에서 `python tools/set_variant.py A`로 모든 iPad를 한 번에 바꿉니다. 직접 고르면 이 기기만 고정됩니다. 화면에는 이름 대신 코드(A/B/C)만 표시됩니다.")
        }
    }
}

/// 화면 구석에 작게 보이는 현재 버전 코드. 스크린샷·영상에도 어느 버전인지 남는다.
struct VariantBadge: View {
    @ObservedObject private var variants = VariantStore.shared
    var onDark = true

    var body: some View {
        Text("버전 \(variants.current.code)")
            .font(.system(size: 11, weight: .semibold, design: .rounded))
            .padding(.horizontal, 7).padding(.vertical, 2)
            .background(Capsule().fill((onDark ? Color.white : Color.black).opacity(0.14)))
            .foregroundStyle((onDark ? Color.white : Color.black).opacity(0.7))
    }
}
