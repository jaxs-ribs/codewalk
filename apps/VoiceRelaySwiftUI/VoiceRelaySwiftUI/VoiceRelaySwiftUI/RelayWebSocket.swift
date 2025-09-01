import Foundation

final class RelayWebSocket: NSObject {
  enum State: String { case idle, connecting, open, closed, error }

  private var task: URLSessionWebSocketTask?
  private var session: URLSession!
  private var heartbeatTimer: Timer?

  @Published var state: State = .idle
  @Published var lastEvent: String = ""
  @Published var lastPayload: String = ""
  @Published var lastAck: String = ""
  @Published var closeInfo: String = ""
  @Published var logs: [(Date, String, String)] = []

  var onStateChange: ((State)->Void)?
  var onLogs: (([(Date,String,String)])->Void)?
  var onAck: ((String)->Void)?

  func normalizeWs(_ raw: String) -> URL? {
    guard var comp = URLComponents(string: raw) else { return nil }
    if comp.scheme == nil { comp.scheme = "ws" }
    comp.path = "/ws"
    return comp.url
  }

  func connect(url: String, sid: String, tok: String) {
    guard let u = normalizeWs(url) else { return }
    disconnect()
    state = .connecting
    let cfg = URLSessionConfiguration.default
    session = URLSession(configuration: cfg, delegate: self, delegateQueue: .main)
    task = session.webSocketTask(with: u)
    task?.resume()
    receiveLoop()
    // send hello when opened in delegate
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
      self.sendHello(sid: sid, tok: tok)
    }
  }

  func disconnect() {
    heartbeatTimer?.invalidate(); heartbeatTimer = nil
    task?.cancel(with: .normalClosure, reason: nil)
    task = nil
    state = .closed
  }

  private func sendHello(sid: String, tok: String) {
    let hello: [String: Any] = ["type":"hello","s":sid,"t":tok,"r":"phone"]
    send(json: hello)
    heartbeatTimer = Timer.scheduledTimer(withTimeInterval: 20.0, repeats: true) { [weak self] _ in
      self?.send(json: ["type":"hb"]) }
  }

  func send(json: [String: Any]) {
    guard let t = task else { return }
    if let data = try? JSONSerialization.data(withJSONObject: json), let s = String(data: data, encoding: .utf8) {
      t.send(.string(s)) { [weak self] error in
        if let e = error { self?.lastEvent = "send:error: \(e.localizedDescription)" } else { self?.lastEvent = "send:ok" }
      }
    }
  }

  func sendUserText(_ text: String) {
    let payload: [String: Any] = ["type":"user_text","text":text,"final":true,"source":"phone"]
    send(json: payload)
  }

  func requestLogs(limit: Int = 200) {
    let id = UUID().uuidString.replacingOccurrences(of: "-", with: "")
    send(json: ["type":"get_logs","id":id,"limit":limit])
  }

  private func receiveLoop() {
    task?.receive { [weak self] result in
      guard let self = self else { return }
      switch result {
      case .success(let msg):
        switch msg {
        case .string(let str): self.handleMessage(str)
        case .data(let data): self.handleMessage(String(data: data, encoding: .utf8) ?? "")
        @unknown default: break
        }
        self.receiveLoop()
      case .failure(let err):
        self.state = .error
        self.closeInfo = err.localizedDescription
      }
    }
  }

  private func handleMessage(_ s: String) {
    lastEvent = "ws:message"
    guard let data = s.data(using: .utf8), let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
      lastPayload = s; return
    }
    if let t = obj["type"] as? String, t == "frame", let frame = obj["frame"] as? String, obj["b64"] as? Bool == false {
      if let fd = frame.data(using: .utf8), let inner = try? JSONSerialization.jsonObject(with: fd) as? [String:Any] {
        if inner["type"] as? String == "ack" {
          let ackText = (inner["text"] as? String) ?? "ack"
          lastAck = ackText
          onAck?(ackText)
        } else if inner["type"] as? String == "logs", let items = inner["items"] as? [[String: Any]] {
          let mapped: [(Date,String,String)] = items.map { it in
            let ts = (it["ts"] as? Double ?? Date().timeIntervalSince1970) / 1000.0
            let type = it["type"] as? String ?? ""
            let message = it["message"] as? String ?? ""
            return (Date(timeIntervalSince1970: ts), type, message)
          }
          logs = mapped
          onLogs?(mapped)
        }
        lastPayload = String(data: fd, encoding: .utf8) ?? ""
      }
    }
  }
}

extension RelayWebSocket: URLSessionWebSocketDelegate {
  func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask, didOpenWithProtocol protocol: String?) {
    state = .open
    lastEvent = "ws:open"
  }

  func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask, didCloseWith closeCode: URLSessionWebSocketTask.CloseCode, reason: Data?) {
    state = .closed
    closeInfo = "code=\(closeCode.rawValue)"
  }
}

