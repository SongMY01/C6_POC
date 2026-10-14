import Foundation

/// 앱 표시 언어. 기본은 영어이고, 홈 화면의 언어 버튼으로 한국어로 바꿀 수 있다.
/// 한국어 문장이 곧 키이고, 영어 번역은 `englishStrings`(Localization+English.swift)에 있다.
enum AppLanguage: String, CaseIterable, Identifiable {
    case english = "en"
    case korean = "ko"

    static let storageKey = "appLanguage"

    var id: String { rawValue }
    var label: String { self == .english ? "English" : "한국어" }

    static var current: AppLanguage {
        get { override ?? AppLanguage(rawValue: UserDefaults.standard.string(forKey: storageKey) ?? "") ?? .english }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: storageKey) }
    }

    /// 잠깐 다른 언어로 문장을 만들 때만 쓴다 (`with`). 화면 표시 언어는 바꾸지 않는다.
    private static var override: AppLanguage?

    /// body 안의 `L()`이 이 언어로 번역되게 해서 실행한다. 예: 보낼 피드백 문장을 한국어·영어로 둘 다 만들기.
    static func with<T>(_ language: AppLanguage, _ body: () -> T) -> T {
        let previous = override
        override = language
        defer { override = previous }
        return body()
    }

    static var isEnglish: Bool { current == .english }
}

/// `L("… \(값) …")` 처럼 보간이 들어간 문장도 하나의 키(`… %@ …`)로 번역하기 위한 타입.
struct LKey: ExpressibleByStringInterpolation {
    struct Interpolation: StringInterpolationProtocol {
        var format = ""
        var args: [String] = []
        init(literalCapacity: Int, interpolationCount: Int) {}
        mutating func appendLiteral(_ literal: String) { format += literal }
        mutating func appendInterpolation<T>(_ value: T) {
            format += "%@"
            args.append(String(describing: value))
        }
    }

    let format: String
    let args: [String]

    init(stringLiteral value: String) { format = value; args = [] }
    init(stringInterpolation: Interpolation) { format = stringInterpolation.format; args = stringInterpolation.args }
}

/// 현재 언어로 번역한 문자열. 번역이 없으면 한국어 원문을 그대로 쓴다.
/// 번역문에서는 `%1$@`, `%2$@`로 값의 순서를 바꿀 수 있다.
func L(_ key: LKey) -> String {
    var text = key.format
    if AppLanguage.isEnglish, let english = englishStrings[key.format] { text = english }
    guard !key.args.isEmpty else { return text }
    for (index, arg) in key.args.enumerated() {
        text = text.replacingOccurrences(of: "%\(index + 1)$@", with: arg)
    }
    var result = ""
    var rest = Substring(text)
    var next = 0
    while let range = rest.range(of: "%@") {
        result += rest[..<range.lowerBound]
        if next < key.args.count { result += key.args[next] }
        next += 1
        rest = rest[range.upperBound...]
    }
    return result + rest
}
