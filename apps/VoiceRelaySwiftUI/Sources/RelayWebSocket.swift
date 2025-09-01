import Foundation
import Combine

/// Manages WebSocket connection to relay server. Handles reconnection and message routing.
/// Protocol: JSON messages with type field. Sends user_text, receives various event types.
final class RelayWebSocket: NSObject, ObservableObject {
  enum State: String { case idle, connecting, open, closed, error }

  private var task: URLSessionWebSocketTask?
  private var session: URLSession!
  private var heartbeatTimer: Timer?

  // Reconnect + hello context
  private var connectURL: String?
  private var sid: String = ""
  private var tok: String = ""
  private var shouldReconnect: Bool = false
  private var reconnectDelay: TimeInterval = 1
  private var reconnectWorkItem: DispatchWorkItem?
  private var isConnecting: Bool = false
  private var lastConnectionAttempt: Date = Date(timeIntervalSince1970: 0)

  @Published var state: State = .idle
  @Published var lastEvent: String = ""
  @Published var lastPayload: String = ""
  @Published var lastAck: String = ""
  @Published var closeInfo: String = ""
  @Published var logs: [(Date, String, String)] = []
  @Published var pendingConfirmation: (id: String?, executor: String, prompt: String)? = nil

  var onStateChange: ((State)->Void)?
  var onLogs: (([(Date,String,String)])->Void)?
  var onFilteredLogs: (([String])->Void)?
  var onAck: ((String)->Void)?
  var onConfirmation: ((String?, String, String)->Void)?

  func normalizeWs(_ raw: String) -> URL? {
    guard var comp = URLComponents(string: raw) else { return nil }
    if comp.scheme == nil { comp.scheme = "ws" }
    comp.path = "/ws"
    return comp.url
  }

  func connect(url: String, sid: String, tok: String) {
    // Prevent multiple simultaneous connection attempts
    guard !isConnecting else { 
      print("Already connecting, skipping duplicate attempt")
      return 
    }
    
    // Throttle connection attempts - wait at least 2 seconds between attempts
    let timeSinceLastAttempt = Date().timeIntervalSince(lastConnectionAttempt)
    guard timeSinceLastAttempt > 2.0 else {
      print("Too soon since last connection attempt, skipping")
      return
    }
    
    guard let u = normalizeWs(url) else { return }
    
    // Persist for reconnect and hello
    self.connectURL = url
    self.sid = sid
    self.tok = tok
    self.shouldReconnect = true
    // Don't reset reconnectDelay here - keep exponential backoff
    reconnectWorkItem?.cancel(); reconnectWorkItem = nil
    
    // Mark as connecting
    isConnecting = true
    lastConnectionAttempt = Date()
    
    // Reset/establish session
    disconnect(userInitiated: false)
    // Only update state if not already connecting (to avoid UI rebuilds)
    if state != .connecting {
      state = .connecting
    }
    let cfg = URLSessionConfiguration.default
    cfg.timeoutIntervalForRequest = 10 // Add timeout
    session = URLSession(configuration: cfg, delegate: self, delegateQueue: .main)
    task = session.webSocketTask(with: u)
    task?.resume()
    receiveLoop()
  }

  func disconnect(userInitiated: Bool = true) {
    heartbeatTimer?.invalidate(); heartbeatTimer = nil
    reconnectWorkItem?.cancel(); reconnectWorkItem = nil
    if userInitiated { 
      shouldReconnect = false
      reconnectDelay = 1 // Reset delay only on user-initiated disconnect
    }
    task?.cancel(with: .normalClosure, reason: nil)
    task = nil
    isConnecting = false
    // Only update state if user-initiated or if we're not about to reconnect
    if userInitiated && state != .idle { 
      state = .closed 
    }
  }

  private func startHeartbeat() {
    heartbeatTimer?.invalidate();
    heartbeatTimer = Timer.scheduledTimer(withTimeInterval: 20.0, repeats: true) { [weak self] _ in
      self?.send(json: ["type":"hb"]) }
  }

  private func sendHello() {
    let hello: [String: Any] = ["type":"hello","s":sid,"t":tok,"r":"phone"]
    send(json: hello)
    startHeartbeat()
  }

  private func scheduleReconnect() {
    guard shouldReconnect, let url = connectURL else { return }
    
    // Cancel any existing reconnect work
    reconnectWorkItem?.cancel()
    
    print("Scheduling reconnect in \(reconnectDelay) seconds")
    
    let work = DispatchWorkItem { [weak self] in
      guard let self = self else { return }
      // Reset connection state before attempting
      self.isConnecting = false
      self.connect(url: url, sid: self.sid, tok: self.tok)
    }
    reconnectWorkItem = work
    DispatchQueue.main.asyncAfter(deadline: .now() + reconnectDelay, execute: work)
    
    // Exponential backoff up to 60s (better for mobile)
    reconnectDelay = min(reconnectDelay * 2, 60)
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
  
  func requestFilteredLogs(limit: Int = 100) {
    let id = UUID().uuidString.replacingOccurrences(of: "-", with: "")
    send(json: ["type":"get_filtered_logs","id":id,"limit":limit])
  }
  
  func sendConfirmResponse(id: String?, accept: Bool) {
    var payload: [String: Any] = [
      "type": "confirm_response",
      "for": "executor_launch",
      "accept": accept
    ]
    if let id = id {
      payload["id"] = id
    }
    send(json: payload)
    pendingConfirmation = nil
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
        self.heartbeatTimer?.invalidate(); self.heartbeatTimer = nil
        self.isConnecting = false
        self.scheduleReconnect()
      }
    }
  }

  private func handleMessage(_ s: String) {
    lastEvent = "ws:message"
    guard let data = s.data(using: .utf8), let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
      lastPayload = s; return
    }
    
    // Check if this is a wrapped frame message
    if let t = obj["type"] as? String, t == "frame", let frame = obj["frame"] as? String, obj["b64"] as? Bool == false {
      if let fd = frame.data(using: .utf8), let inner = try? JSONSerialization.jsonObject(with: fd) as? [String:Any] {
        processInnerMessage(inner)
        lastPayload = String(data: fd, encoding: .utf8) ?? ""
      }
    } else {
      // Handle direct messages (not wrapped in frame)
      processInnerMessage(obj)
      lastPayload = s
    }
  }
  
  private func processInnerMessage(_ msg: [String: Any]) {
    if msg["type"] as? String == "ack" {
      let ackText = (msg["text"] as? String) ?? "ack"
      lastAck = ackText
      onAck?(ackText)
    } else if msg["type"] as? String == "prompt_confirmation" {
      let id = msg["id"] as? String
      let executor = (msg["executor"] as? String) ?? "Claude"
      let prompt = (msg["prompt"] as? String) ?? ""
      pendingConfirmation = (id: id, executor: executor, prompt: prompt)
      print("DEBUG: Received prompt_confirmation - id: \(id ?? "nil"), executor: \(executor), prompt: \(prompt)")
      print("DEBUG: onConfirmation callback is \(onConfirmation != nil ? "set" : "nil")")
      onConfirmation?(id, executor, prompt)
    } else if msg["type"] as? String == "logs", let items = msg["items"] as? [[String: Any]] {
      let mapped: [(Date,String,String)] = items.map { it in
        let ts = (it["ts"] as? Double ?? Date().timeIntervalSince1970) / 1000.0
        let type = it["type"] as? String ?? ""
        let message = it["message"] as? String ?? ""
        return (Date(timeIntervalSince1970: ts), type, message)
      }
      logs = mapped
      onLogs?(mapped)
    } else if msg["type"] as? String == "filtered_logs", let items = msg["items"] as? [String] {
      // Handle pre-filtered logs for summarization
      onFilteredLogs?(items)
    }
  }
}

extension RelayWebSocket: URLSessionWebSocketDelegate {
  func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask, didOpenWithProtocol protocol: String?) {
    state = .open
    lastEvent = "ws:open"
    isConnecting = false
    reconnectDelay = 1 // Reset backoff on successful connection
    // Send hello and start heartbeats now that we are open
    sendHello()
  }

  func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask, didCloseWith closeCode: URLSessionWebSocketTask.CloseCode, reason: Data?) {
    state = .closed
    closeInfo = "code=\(closeCode.rawValue)"
    heartbeatTimer?.invalidate(); heartbeatTimer = nil
    isConnecting = false
    scheduleReconnect()
  }
}
