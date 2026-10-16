// swift-tools-version: 6.0
import PackageDescription

// 의존 방향 (위층은 아래층만 import, Feature끼리는 import 금지)
//
//   BandApp                       ← 루트 Reducer(AppFeature). 모든 Feature를 조립하고 연결한다.
//   BandSession / BandPlayer / BandRehearsal / BandSync / BandPractice   ← Feature (서로 import 금지)
//   BandUI                        ← Feature들이 함께 쓰는 공용 뷰
//   BandServices                  ← 바깥 세계와 닿는 의존성 (서버, 저장소, 오디오 ...)
//   BandFoundation                ← 모델과 순수 규칙 (UI·부수효과 없음)

let tca = Target.Dependency.product(name: "ComposableArchitecture", package: "swift-composable-architecture")
let dependencies = Target.Dependency.product(name: "Dependencies", package: "swift-dependencies")
let dependenciesMacros = Target.Dependency.product(name: "DependenciesMacros", package: "swift-dependencies")

func local(_ name: String) -> Target.Dependency { .target(name: name) }

let featureNames = ["Session", "Player", "Rehearsal", "Sync", "Practice"]

let featureTargets: [Target] = featureNames.flatMap { name -> [Target] in
    [
        .target(
            name: "Band\(name)",
            dependencies: [local("BandFoundation"), local("BandServices"), local("BandUI"), tca],
            path: "Sources/Band\(name)"
        ),
        .testTarget(
            name: "Band\(name)Tests",
            dependencies: [local("Band\(name)")],
            path: "Tests/Band\(name)Tests"
        ),
    ]
}

let package = Package(
    name: "BandKit",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(
            name: "BandKit",
            targets: ["BandFoundation", "BandServices", "BandUI", "BandApp"] + featureNames.map { "Band\($0)" }
        ),
    ],
    dependencies: [
        .package(url: "https://github.com/pointfreeco/swift-composable-architecture", exact: "1.26.2"),
        .package(url: "https://github.com/pointfreeco/swift-dependencies", exact: "1.17.1"),
    ],
    targets: [
        .target(name: "BandFoundation"),
        .testTarget(name: "BandFoundationTests", dependencies: [local("BandFoundation")]),

        .target(name: "BandServices", dependencies: [local("BandFoundation"), dependencies, dependenciesMacros]),

        .target(name: "BandUI", dependencies: [local("BandFoundation")]),

        .target(
            name: "BandApp",
            dependencies: [local("BandFoundation"), local("BandServices"), local("BandUI"), tca] + featureNames.map { local("Band\($0)") }
        ),
        .testTarget(name: "BandAppTests", dependencies: [local("BandApp"), local("BandFoundation"), local("BandServices"), tca] + featureNames.map { local("Band\($0)") }),
    ] + featureTargets,
    swiftLanguageModes: [.v5]
)
