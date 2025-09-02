import Foundation

struct STTResponse: Decodable { let text: String?; let segments: [Segment]?; struct Segment: Decodable { let text: String? } }

/// Uploads audio files to Groq API for Whisper transcription. Uses streaming multipart/form-data.
final class STTUploader: NSObject {
  enum STTError: Error { case http(Int, String); case empty; case io }
  
  private static var uploadSession: URLSession = {
    let config = URLSessionConfiguration.default
    config.httpMaximumConnectionsPerHost = 2
    config.timeoutIntervalForRequest = 120
    config.timeoutIntervalForResource = 300
    // Force HTTP/2 over TCP instead of HTTP/3 QUIC to avoid message size limits
    // Note: assumesHTTP3Capable was removed, HTTP/2 will be used by default
    return URLSession(configuration: config)
  }()

  static func transcribe(fileURL: URL, apiKey: String, responseFormat: String = "json", completion: @escaping (Result<String,Error>)->Void) {
    let boundary = "Boundary-\(UUID().uuidString)"
    var req = URLRequest(url: URL(string: "https://api.groq.com/openai/v1/audio/transcriptions")!)
    req.httpMethod = "POST"
    req.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
    req.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
    req.setValue("application/json", forHTTPHeaderField: "Accept")
    
    // Build multipart body with streaming support
    let streamingBody = StreamingMultipartBody(boundary: boundary, fileURL: fileURL, responseFormat: responseFormat)
    
    // Use InputStream for streaming upload
    if let bodyStream = streamingBody.makeInputStream() {
      req.httpBodyStream = bodyStream
      req.setValue("\(streamingBody.contentLength)", forHTTPHeaderField: "Content-Length")
      
      uploadSession.dataTask(with: req) { data, resp, err in
        if let err = err {
          print("STT Upload error: \(err)")
          return completion(.failure(err))
        }
        guard let http = resp as? HTTPURLResponse else { return completion(.failure(STTError.http(-1, "no response"))) }
        let body = String(data: data ?? Data(), encoding: .utf8) ?? ""
        if http.statusCode != 200 {
          print("STT API error \(http.statusCode): \(body)")
          return completion(.failure(STTError.http(http.statusCode, String(body.prefix(300)))))
        }
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
    } else {
      completion(.failure(STTError.io))
    }
  }
}

/// Helper class to create streaming multipart body
private class StreamingMultipartBody {
  let boundary: String
  let fileURL: URL
  let responseFormat: String
  var contentLength: Int
  
  init(boundary: String, fileURL: URL, responseFormat: String) {
    self.boundary = boundary
    self.fileURL = fileURL
    self.responseFormat = responseFormat
    self.contentLength = 0 // Initialize first
    
    // Calculate content length
    let fileSize = (try? FileManager.default.attributesOfItem(atPath: fileURL.path)[.size] as? Int) ?? 0
    let header = self.buildHeader()
    let footer = self.buildFooter()
    self.contentLength = header.count + fileSize + footer.count
  }
  
  private func buildHeader() -> Data {
    var header = ""
    header += "--\(boundary)\r\n"
    header += "Content-Disposition: form-data; name=\"model\"\r\n\r\n"
    header += "whisper-large-v3-turbo\r\n"
    
    header += "--\(boundary)\r\n"
    header += "Content-Disposition: form-data; name=\"response_format\"\r\n\r\n"
    header += "\(responseFormat)\r\n"
    
    header += "--\(boundary)\r\n"
    header += "Content-Disposition: form-data; name=\"file\"; filename=\"audio.wav\"\r\n"
    header += "Content-Type: audio/wav\r\n\r\n"
    
    return header.data(using: .utf8)!
  }
  
  private func buildFooter() -> Data {
    return "\r\n--\(boundary)--\r\n".data(using: .utf8)!
  }
  
  func makeInputStream() -> InputStream? {
    let header = buildHeader()
    let footer = buildFooter()
    
    guard let fileStream = InputStream(fileAtPath: fileURL.path) else { return nil }
    
    // Create a composite stream that reads header, file, then footer
    return CompositeInputStream(streams: [
      InputStream(data: header),
      fileStream,
      InputStream(data: footer)
    ])
  }
}

/// Composite input stream that reads from multiple streams in sequence
private class CompositeInputStream: InputStream {
  private var streams: [InputStream]
  private var currentIndex = 0
  
  init(streams: [InputStream]) {
    self.streams = streams
    super.init(data: Data())
  }
  
  override func open() {
    for stream in streams {
      stream.open()
    }
  }
  
  override func close() {
    for stream in streams {
      stream.close()
    }
  }
  
  override func read(_ buffer: UnsafeMutablePointer<UInt8>, maxLength len: Int) -> Int {
    var totalBytesRead = 0
    var remainingLength = len
    
    while currentIndex < streams.count && remainingLength > 0 {
      let stream = streams[currentIndex]
      let bytesRead = stream.read(buffer.advanced(by: totalBytesRead), maxLength: remainingLength)
      
      if bytesRead > 0 {
        totalBytesRead += bytesRead
        remainingLength -= bytesRead
      } else if bytesRead == 0 {
        // Current stream is exhausted, move to next
        currentIndex += 1
      } else {
        // Error occurred
        return bytesRead
      }
    }
    
    return totalBytesRead
  }
  
  override var hasBytesAvailable: Bool {
    guard currentIndex < streams.count else { return false }
    return streams[currentIndex].hasBytesAvailable || currentIndex < streams.count - 1
  }
}

