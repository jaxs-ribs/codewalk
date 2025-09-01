import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

struct ContentView: View {
  @State private var env = EnvConfig.load()
  @State private var healthStatus: String = "checking"
  @State private var healthLatency: Int? = nil
  @State private var lastCheckedAt: Date? = nil

  @StateObject private var ws = RelayWebSocket()
  @State private var input: String = ""
  @State private var showDetails: Bool = false
  @State private var transcript: String = ""
  private let recorder = Recorder()
  @State private var recordStarted: Date? = nil
  @State private var recordMs: Double = 0
  @State private var timer: Timer? = nil
  @FocusState private var inputFocused: Bool

  enum STTState: Equatable { case idle, recording(started: Date), uploading(URL), transcribing, sending, error(String) }
  @State private var stt: STTState = .idle

  var body: some View {
    NavigationStack {
      ScrollView {
        VStack(spacing: 12) {
          Text(pillText)
            .foregroundColor(.white)
            .padding(.horizontal, 12).padding(.vertical, 6)
            .background(pillColor).cornerRadius(999)
          if let at = lastCheckedAt { Text("Last checked \(timeStr(at))\(healthLatency != nil ? " • \(healthLatency!) ms" : "")").font(.caption).foregroundColor(.gray) }

          if case .recording = stt {
            HStack(spacing: 8) {
              Text("Recording… \(String(format: "%.1f", recordMs/1000))s").font(.caption).foregroundColor(.gray)
              Button("Cancel", action: cancelRecording).buttonStyle(.bordered)
            }
          } else if case .uploading = stt {
            HStack(spacing: 8) { ProgressView().scaleEffect(0.7); Text("Uploading…").font(.caption).foregroundColor(.gray) }
          } else if case .transcribing = stt {
            HStack(spacing: 8) { ProgressView().scaleEffect(0.7); Text("Transcribing…").font(.caption).foregroundColor(.gray) }
          } else if case .sending = stt {
            HStack(spacing: 8) { ProgressView().scaleEffect(0.7); Text("Sending…").font(.caption).foregroundColor(.gray) }
          } else if case .error(let msg) = stt {
            Text("Error: \(msg)").font(.caption).foregroundColor(.red)
          }

          if !transcript.isEmpty { Text("Transcript: \(transcript)").font(.caption).foregroundColor(.gray).lineLimit(2) }

          GroupBox(label: Text("Logs").font(.headline)) {
            if ws.logs.isEmpty { Text("no logs to display yet").font(.caption).foregroundColor(.gray) }
            ForEach(Array(ws.logs.enumerated()), id: \.offset) { _, item in
              Text("\(timeStr(item.0)) [\(item.1)] \(item.2)").font(.footnote)
            }
          }

          if showDetails {
            GroupBox(label: Text("Debug").font(.headline)) {
              VStack(alignment: .leading, spacing: 4) {
                Text("State: \(ws.state.rawValue)").font(.caption).foregroundColor(.gray)
                Text("WS: \(normalizedWs() ?? "(invalid)")").font(.caption).foregroundColor(.gray).textSelection(.enabled)
                Text("sid: \(env.sessionId)").font(.caption).foregroundColor(.gray).textSelection(.enabled)
                Text("tok: \(env.token)").font(.caption).foregroundColor(.gray).textSelection(.enabled)
                if !ws.lastEvent.isEmpty { Text("Last: \(ws.lastEvent)").font(.caption).foregroundColor(.gray) }
                if !ws.closeInfo.isEmpty { Text("Close: \(ws.closeInfo)").font(.caption).foregroundColor(.gray) }
                if !ws.lastAck.isEmpty { Text("Ack: \(ws.lastAck)").font(.caption).foregroundColor(.gray) }
                if !ws.lastPayload.isEmpty { Text("Payload: \(ws.lastPayload)").font(.caption).foregroundColor(.gray).lineLimit(3) }
              }
            }
          }
          Button(showDetails ? "Hide details" : "Show details") { showDetails.toggle() }
        }.padding()
      }
      .navigationTitle("VoiceRelay")
      .toolbar {
        // Top-right quick actions
        ToolbarItemGroup(placement: .navigationBarTrailing) {
          Button { ws.requestLogs() } label: { Label("Logs", systemImage: "list.bullet.rectangle") }
          Button { ws.disconnect() } label: { Label("Disconnect", systemImage: "bolt.slash") }
        }
        // Bottom bar input + actions
        ToolbarItemGroup(placement: .bottomBar) {
          TextField("Type a message…", text: $input)
            .textFieldStyle(.roundedBorder)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled(true)
            .submitLabel(.send)
            .onSubmit(onSend)
            .disabled(ws.state != .open)
            .focused($inputFocused)
          Button(action: onRecordOrStop) {
            if case .recording = stt { Label("Stop", systemImage: "stop.circle.fill") }
            else { Label("Rec", systemImage: "mic.circle.fill") }
          }
          .disabled({ if case .uploading = stt { return true }; if case .transcribing = stt { return true }; if case .sending = stt { return true }; return false }())
          Button(action: onSend) { Label("Send", systemImage: "paperplane.fill") }
            .disabled(ws.state != .open || input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
      }
    }
    .onAppear(perform: onAppear)
    .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in
      connect()
    }
  }

  private var pillText: String { healthStatus == "connected" ? "Connected" : healthStatus == "disconnected" ? "Disconnected" : "Checking…" }
  private var pillColor: Color { healthStatus == "connected" ? .green : healthStatus == "disconnected" ? .red : .gray }

  private func onAppear() {
    healthCheck()
    connect()
  }
  private func timeStr(_ d: Date) -> String { let f = DateFormatter(); f.dateFormat = "HH:mm:ss"; return f.string(from: d) }
  private func normalizedWs() -> String? {
    guard var u = URL(string: env.relayWsUrl) else { return nil }
    u.deleteLastPathComponent(); // ensure path base
    return u.absoluteString.hasSuffix("/ws") ? u.absoluteString : (URL(string: env.relayWsUrl)?.absoluteString ?? env.relayWsUrl)
  }

  private func healthCheck() {
    guard var comp = URLComponents(string: env.relayWsUrl) else { return }
    // derive http health
    comp.scheme = "http"
    comp.path = comp.path.hasSuffix("/ws") ? String(comp.path.dropLast(3)) : comp.path
    var url = comp.url
    if url == nil, let u = URL(string: env.relayWsUrl) { url = u }
    guard let health = url?.appendingPathComponent("/health") else { return }
    healthStatus = "checking"
    let started = Date()
    var req = URLRequest(url: health)
    req.timeoutInterval = 5
    URLSession.shared.dataTask(with: req) { data, resp, _ in
      DispatchQueue.main.async {
        self.healthLatency = Int(Date().timeIntervalSince(started)*1000)
        self.lastCheckedAt = Date()
        if let http = resp as? HTTPURLResponse, http.statusCode == 200 {
          self.healthStatus = "connected"
        } else { self.healthStatus = "disconnected" }
      }
    }.resume()
  }

  private func connect() {
    ws.connect(url: env.relayWsUrl, sid: env.sessionId, tok: env.token)
  }

  private func onSend() {
    let msg = input.trimmingCharacters(in: .whitespacesAndNewlines)
    input = ""
    guard !msg.isEmpty else { return }
    ws.sendUserText(msg)
  }

  private func onRecordOrStop() {
    switch stt {
    case .recording: stopRecordingAndSend()
    default: startRecording()
    }
  }

  private func startRecording() {
    guard case .idle = stt else { return }
    recorder.requestPermission { granted in
      guard granted else { stt = .idle; openSettingsAlert(); return }
      recorder.start { result in
        switch result {
        case .success:
          let now = Date()
          recordStarted = now
          stt = .recording(started: now)
          timer?.invalidate(); timer = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { _ in
            recordMs = -(recordStarted ?? Date()).timeIntervalSinceNow * 1000
          }
        case .failure(let err):
          stt = .error(err.localizedDescription)
          showError("Recorder error", err.localizedDescription)
          resetStt()
        }
      }
    }
  }

  private func stopRecordingAndSend() {
    guard case .recording = stt else { return }
    timer?.invalidate(); timer = nil
    recorder.stop { result in
      switch result {
      case .success(let url):
        stt = .uploading(url)
        // size guard
        if let attrs = try? FileManager.default.attributesOfItem(atPath: url.path), let size = attrs[.size] as? NSNumber, size.intValue > 25*1024*1024 {
          showError("Too large", "Audio exceeds 25 MB free-tier limit.")
          resetStt(); return
        }
        stt = .transcribing
        STTUploader.transcribe(fileURL: url, apiKey: env.groqApiKey) { res in
          DispatchQueue.main.async {
            switch res {
            case .success(let text):
              transcript = text
              stt = .sending
              ws.send(json: ["type":"user_text","text":text,"final":true,"source":"stt","metadata":["source":"stt","audioMs":Int(recordMs)]])
              resetStt()
            case .failure(let err):
              stt = .error(err.localizedDescription)
              showError("Transcription error", err.localizedDescription)
              resetStt()
            }
          }
        }
      case .failure(let err):
        stt = .error(err.localizedDescription)
        showError("Stop error", err.localizedDescription)
        resetStt()
      }
    }
  }

  private func cancelRecording() {
    timer?.invalidate(); timer = nil
    recorder.stop { result in
      if case .success(let url) = result { try? FileManager.default.removeItem(at: url) }
      resetStt()
    }
  }

  private func resetStt() {
    recordStarted = nil
    recordMs = 0
    timer?.invalidate(); timer = nil
    stt = .idle
  }

  private func showError(_ title: String, _ msg: String) {
    #if canImport(UIKit)
    let alert = UIAlertController(title: title, message: msg, preferredStyle: .alert)
    alert.addAction(UIAlertAction(title: "OK", style: .default))
    firstKeyWindow()?.rootViewController?.present(alert, animated: true)
    #endif
  }

  private func openSettingsAlert() {
    #if canImport(UIKit)
    let alert = UIAlertController(title: "Microphone Access Needed", message: "Enable microphone in Settings to record audio.", preferredStyle: .alert)
    alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
    alert.addAction(UIAlertAction(title: "Open Settings", style: .default, handler: { _ in
      if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
    }))
    firstKeyWindow()?.rootViewController?.present(alert, animated: true)
    #endif
  }

  #if canImport(UIKit)
  private func firstKeyWindow() -> UIWindow? {
    return UIApplication.shared.connectedScenes
      .compactMap { $0 as? UIWindowScene }
      .flatMap { $0.windows }
      .first { $0.isKeyWindow }
  }
  #endif
}
