import Foundation

/// 통합 합주 녹음본을 서버(Demucs 파이프라인)로 보내
/// 세션(악기)별 음원으로 분리 요청하는 클라이언트.
///
/// 서버는 PoC/server/server.py (FastAPI + Demucs htdemucs_6s).
/// 시뮬레이터에서는 Mac 호스트의 localhost가 그대로 보이므로
/// 별도 설정 없이 http://127.0.0.1:8756 으로 접근 가능하다.
/// 실기기(iPad)에서 테스트할 때는 같은 Wi-Fi의 Mac IP로 바꿔주면 된다.

enum JobStatus: String, Decodable {
    case queued, processing, done, error
}

struct JobStatusResponse: Decodable {
    let job_id: String
    let status: JobStatus
    let stems: [String]?
    let error: String?
}

struct StemDefinition {
    let key: String        // 서버 API 상의 이름 (vocals, drums, bass, guitar, piano)
    let displayName: String
    let colorName: String  // asset/색상 매핑용
}

let sessionStems: [StemDefinition] = [
    .init(key: "vocals", displayName: "보컬", colorName: "vocals"),
    .init(key: "drums",  displayName: "드럼", colorName: "drums"),
    .init(key: "bass",   displayName: "베이스", colorName: "bass"),
    .init(key: "guitar", displayName: "일렉기타", colorName: "guitar"),
    .init(key: "piano",  displayName: "피아노", colorName: "piano"),
]

enum SeparationError: LocalizedError {
    case badResponse
    case serverError(String)
    case cannotReadFile

    var errorDescription: String? {
        switch self {
        case .badResponse: return "서버 응답을 해석할 수 없습니다."
        case .serverError(let msg): return "분리 실패: \(msg)"
        case .cannotReadFile: return "선택한 파일을 읽을 수 없습니다."
        }
    }
}

final class SeparationService {
    var baseURL: URL

    init(baseURL: URL = URL(string: "http://127.0.0.1:8756")!) {
        self.baseURL = baseURL
    }

    /// 녹음 파일을 업로드하고 job_id를 받는다.
    func uploadRecording(fileURL: URL) async throws -> String {
        guard fileURL.startAccessingSecurityScopedResource() else {
            throw SeparationError.cannotReadFile
        }
        defer { fileURL.stopAccessingSecurityScopedResource() }

        let fileData = try Data(contentsOf: fileURL)
        let filename = fileURL.lastPathComponent
        let boundary = "Boundary-\(UUID().uuidString)"

        var body = Data()
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"file\"; filename=\"\(filename)\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: application/octet-stream\r\n\r\n".data(using: .utf8)!)
        body.append(fileData)
        body.append("\r\n--\(boundary)--\r\n".data(using: .utf8)!)

        var request = URLRequest(url: baseURL.appendingPathComponent("jobs"))
        request.httpMethod = "POST"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.httpBody = body

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw SeparationError.badResponse
        }
        struct CreateJobResponse: Decodable { let job_id: String }
        let decoded = try JSONDecoder().decode(CreateJobResponse.self, from: data)
        return decoded.job_id
    }

    /// job 상태를 한 번 조회한다.
    func fetchStatus(jobId: String) async throws -> JobStatusResponse {
        let url = baseURL.appendingPathComponent("jobs/\(jobId)")
        let (data, response) = try await URLSession.shared.data(from: url)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw SeparationError.badResponse
        }
        return try JSONDecoder().decode(JobStatusResponse.self, from: data)
    }

    /// 완료된 job에서 특정 스템 mp3를 로컬 임시 디렉토리로 내려받는다.
    func downloadStem(jobId: String, stemKey: String) async throws -> URL {
        let url = baseURL.appendingPathComponent("jobs/\(jobId)/stems/\(stemKey).mp3")
        let (tempURL, response) = try await URLSession.shared.download(from: url)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw SeparationError.badResponse
        }
        let dest = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(jobId)-\(stemKey).mp3")
        if FileManager.default.fileExists(atPath: dest.path) {
            try FileManager.default.removeItem(at: dest)
        }
        try FileManager.default.moveItem(at: tempURL, to: dest)
        return dest
    }
}
