import Foundation

struct STTResponse: Decodable { let text: String?; let segments: [Segment]?; struct Segment: Decodable { let text: String? } }

final class STTUploader {
  enum STTError: Error { case http(Int, String); case empty; case io }

  static func transcribe(fileURL: URL, apiKey: String, responseFormat: String = "json", completion: @escaping (Result<String,Error>)->Void) {
    // Build multipart into a temp file for low memory
    let boundary = "Boundary-\(UUID().uuidString)"
    var req = URLRequest(url: URL(string: "https://api.groq.com/openai/v1/audio/transcriptions")!)
    req.httpMethod = "POST"
    req.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
    req.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
    req.setValue("application/json", forHTTPHeaderField: "Accept")

    do {
      let tmp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
      FileManager.default.createFile(atPath: tmp.path, contents: nil)
      guard let out = try? FileHandle(forWritingTo: tmp) else { throw STTError.io }
      func write(_ s: String) { out.write(s.data(using: .utf8)!) }

      write("--\(boundary)\r\n")
      write("Content-Disposition: form-data; name=\"model\"\r\n\r\n")
      write("whisper-large-v3-turbo\r\n")

      write("--\(boundary)\r\n")
      write("Content-Disposition: form-data; name=\"response_format\"\r\n\r\n")
      write("\(responseFormat)\r\n")

      write("--\(boundary)\r\n")
      write("Content-Disposition: form-data; name=\"file\"; filename=\"audio.wav\"\r\n")
      write("Content-Type: audio/wav\r\n\r\n")
      if let inH = try? FileHandle(forReadingFrom: fileURL) {
        while autoreleasepool(invoking: {
          let chunk = inH.readData(ofLength: 256 * 1024)
          if chunk.count > 0 { out.write(chunk); return true }
          return false
        }) {}
        try? inH.close()
      } else { try? out.close(); throw STTError.io }
      write("\r\n--\(boundary)--\r\n")
      try? out.close()

      URLSession.shared.uploadTask(with: req, fromFile: tmp) { data, resp, err in
        defer { try? FileManager.default.removeItem(at: tmp) }
        if let err = err { return completion(.failure(err)) }
        guard let http = resp as? HTTPURLResponse else { return completion(.failure(STTError.http(-1, "no response"))) }
        let body = String(data: data ?? Data(), encoding: .utf8) ?? ""
        if http.statusCode != 200 { return completion(.failure(STTError.http(http.statusCode, String(body.prefix(300))))) }
        // Parse json
        if responseFormat == "json" {
          if let d = data, let parsed = try? JSONDecoder().decode(STTResponse.self, from: d), let t = parsed.text, !t.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return completion(.success(t))
          }
          // Retry once with verbose_json
          return transcribe(fileURL: fileURL, apiKey: apiKey, responseFormat: "verbose_json", completion: completion)
        } else {
          if let d = data, let parsed = try? JSONDecoder().decode(STTResponse.self, from: d) {
            let joined = (parsed.segments ?? []).compactMap { $0.text }.joined()
            if !joined.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return completion(.success(joined)) }
          }
          return completion(.failure(STTError.empty))
        }
      }.resume()
    } catch {
      return completion(.failure(error))
    }
  }
}

