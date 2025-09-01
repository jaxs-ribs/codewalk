import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

/// Main UI. Manages WebSocket connection, audio recording, and STT transcription.
/// Architecture: ContentView -> RelayWebSocket -> Server
///                        -> Recorder -> STTUploader -> Groq API
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
  @State private var logSummary: String = ""
  @State private var isSummarizingLogs: Bool = false
  private let logSummarizer: LogSummarizer

  /// Recording/transcription state machine
  enum STTState: Equatable { case idle, recording(started: Date), uploading(URL), transcribing, sending, error(String) }
  @State private var stt: STTState = .idle
  
  init() {
    let env = EnvConfig.load()
    self.logSummarizer = LogSummarizer(groqApiKey: env.groqApiKey)
  }

  var body: some View {
    NavigationStack {
      ZStack {
        LinearGradient(gradient: Gradient(colors: [Color(red: 0.05, green: 0.05, blue: 0.15), Color(red: 0.1, green: 0.1, blue: 0.2)]), startPoint: .top, endPoint: .bottom)
          .ignoresSafeArea(.all)
        
        ScrollView {
          VStack(spacing: 20) {
            connectionStatusCard
            
            if case .recording = stt {
              recordingCard
            } else if case .uploading = stt {
              statusCard(icon: "arrow.up.circle.fill", text: "Uploading…", color: .blue)
            } else if case .transcribing = stt {
              statusCard(icon: "waveform", text: "Transcribing…", color: .purple)
            } else if case .sending = stt {
              statusCard(icon: "paperplane.fill", text: "Sending…", color: .green)
            } else if case .error(let msg) = stt {
              errorCard(msg)
            }
            
            if !transcript.isEmpty {
              transcriptCard
            }
            
            logsCard
            
            if showDetails {
              debugCard
            }
            
            Button(action: { showDetails.toggle() }) {
              Label(showDetails ? "Hide Details" : "Show Details", systemImage: showDetails ? "chevron.up.circle.fill" : "chevron.down.circle.fill")
                .font(.system(size: 16, weight: .medium, design: .rounded))
                .foregroundColor(.white.opacity(0.8))
                .padding(.horizontal, 20)
                .padding(.vertical, 10)
                .background(Color.white.opacity(0.1))
                .cornerRadius(20)
            }
            .padding(.bottom, 100)
          }
          .padding(.horizontal)
          .padding(.top, 20)
        }
      }
      .navigationTitle("Voice Relay")
      .navigationBarTitleDisplayMode(.large)
      .toolbar {
        ToolbarItemGroup(placement: .navigationBarTrailing) {
          Button(action: { fetchAndSummarizeLogs() }) {
            Image(systemName: "list.bullet.rectangle.fill")
              .foregroundColor(.white)
              .font(.system(size: 18))
          }
          Button(action: { ws.disconnect() }) {
            Image(systemName: "bolt.slash.fill")
              .foregroundColor(.white)
              .font(.system(size: 18))
          }
        }
      }
      .safeAreaInset(edge: .bottom) {
        inputBar
      }
    }
    .preferredColorScheme(.dark)
    .onAppear(perform: onAppear)
    .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in
      connect()
    }
    .alert("Confirm Executor Launch", isPresented: .constant(ws.pendingConfirmation != nil)) {
      Button("Cancel", role: .cancel) {
        if let details = ws.pendingConfirmation {
          ws.sendConfirmResponse(id: details.id, accept: false)
        }
      }
      Button("Confirm") {
        if let details = ws.pendingConfirmation {
          ws.sendConfirmResponse(id: details.id, accept: true)
        }
      }
    } message: {
      if let details = ws.pendingConfirmation {
        Text("Launch \(details.executor) with prompt:\n\n\(details.prompt)")
      }
    }
  }
  
  private var connectionStatusCard: some View {
    HStack(spacing: 12) {
      Circle()
        .fill(healthStatus == "connected" ? Color.green : healthStatus == "disconnected" ? Color.red : Color.orange)
        .frame(width: 12, height: 12)
        .overlay(
          Circle()
            .stroke(Color.white.opacity(0.3), lineWidth: 2)
            .scaleEffect(healthStatus == "checking" ? 2 : 1)
            .opacity(healthStatus == "checking" ? 0 : 1)
            .animation(.easeOut(duration: 1).repeatForever(autoreverses: false), value: healthStatus)
        )
      
      VStack(alignment: .leading, spacing: 2) {
        Text(healthStatus == "connected" ? "Connected" : healthStatus == "disconnected" ? "Disconnected" : "Connecting…")
          .font(.system(size: 16, weight: .semibold, design: .rounded))
          .foregroundColor(.white)
        
        if let at = lastCheckedAt {
          Text("Last checked \(timeStr(at))\(healthLatency != nil ? " • \(healthLatency!) ms" : "")")
            .font(.system(size: 12, weight: .regular, design: .monospaced))
            .foregroundColor(.white.opacity(0.6))
        }
      }
      
      Spacer()
    }
    .padding(16)
    .background(
      RoundedRectangle(cornerRadius: 16)
        .fill(Color.white.opacity(0.1))
        .overlay(
          RoundedRectangle(cornerRadius: 16)
            .stroke(Color.white.opacity(0.2), lineWidth: 1)
        )
    )
  }
  
  private var recordingCard: some View {
    HStack(spacing: 16) {
      ZStack {
        Circle()
          .fill(Color.red)
          .frame(width: 20, height: 20)
        Circle()
          .stroke(Color.red, lineWidth: 3)
          .frame(width: 30, height: 30)
          .scaleEffect(1.5)
          .opacity(0.3)
          .animation(.easeInOut(duration: 1).repeatForever(autoreverses: true), value: recordMs)
      }
      
      Text("Recording… \(String(format: "%.1f", recordMs/1000))s")
        .font(.system(size: 16, weight: .medium, design: .rounded))
        .foregroundColor(.white)
      
      Spacer()
      
      Button(action: cancelRecording) {
        Text("Cancel")
          .font(.system(size: 14, weight: .semibold, design: .rounded))
          .foregroundColor(.white)
          .padding(.horizontal, 16)
          .padding(.vertical, 8)
          .background(Color.red.opacity(0.3))
          .cornerRadius(12)
      }
    }
    .padding(16)
    .background(
      RoundedRectangle(cornerRadius: 16)
        .fill(Color.red.opacity(0.1))
        .overlay(
          RoundedRectangle(cornerRadius: 16)
            .stroke(Color.red.opacity(0.3), lineWidth: 1)
        )
    )
  }
  
  private func statusCard(icon: String, text: String, color: Color) -> some View {
    HStack(spacing: 12) {
      Image(systemName: icon)
        .font(.system(size: 20))
        .foregroundColor(color)
      
      Text(text)
        .font(.system(size: 16, weight: .medium, design: .rounded))
        .foregroundColor(.white)
      
      Spacer()
      
      ProgressView()
        .progressViewStyle(CircularProgressViewStyle(tint: color))
        .scaleEffect(0.8)
    }
    .padding(16)
    .background(
      RoundedRectangle(cornerRadius: 16)
        .fill(color.opacity(0.1))
        .overlay(
          RoundedRectangle(cornerRadius: 16)
            .stroke(color.opacity(0.3), lineWidth: 1)
        )
    )
  }
  
  private func errorCard(_ message: String) -> some View {
    HStack(spacing: 12) {
      Image(systemName: "exclamationmark.triangle.fill")
        .font(.system(size: 20))
        .foregroundColor(.red)
      
      Text("Error: \(message)")
        .font(.system(size: 14, weight: .medium, design: .rounded))
        .foregroundColor(.white)
        .lineLimit(2)
      
      Spacer()
    }
    .padding(16)
    .background(
      RoundedRectangle(cornerRadius: 16)
        .fill(Color.red.opacity(0.1))
        .overlay(
          RoundedRectangle(cornerRadius: 16)
            .stroke(Color.red.opacity(0.3), lineWidth: 1)
        )
    )
  }
  
  private var transcriptCard: some View {
    VStack(alignment: .leading, spacing: 8) {
      Label("Transcript", systemImage: "text.quote")
        .font(.system(size: 14, weight: .semibold, design: .rounded))
        .foregroundColor(.white.opacity(0.7))
      
      Text(transcript)
        .font(.system(size: 14, weight: .regular, design: .rounded))
        .foregroundColor(.white)
        .lineLimit(3)
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.black.opacity(0.3))
        .cornerRadius(8)
    }
    .padding(16)
    .background(
      RoundedRectangle(cornerRadius: 16)
        .fill(Color.white.opacity(0.05))
        .overlay(
          RoundedRectangle(cornerRadius: 16)
            .stroke(Color.white.opacity(0.1), lineWidth: 1)
        )
    )
  }
  
  private var logsCard: some View {
    VStack(alignment: .leading, spacing: 12) {
      HStack {
        Label("Activity Summary", systemImage: "list.bullet.rectangle")
          .font(.system(size: 16, weight: .semibold, design: .rounded))
          .foregroundColor(.white)
        
        Spacer()
        
        if isSummarizingLogs {
          ProgressView()
            .progressViewStyle(CircularProgressViewStyle(tint: .white))
            .scaleEffect(0.7)
        }
      }
      
      ScrollView {
        VStack(alignment: .leading, spacing: 8) {
          if !logSummary.isEmpty {
            Text(logSummary)
              .font(.system(size: 14, weight: .regular, design: .rounded))
              .foregroundColor(.white.opacity(0.9))
              .padding(12)
              .frame(maxWidth: .infinity, alignment: .leading)
              .background(Color.black.opacity(0.2))
              .cornerRadius(8)
          } else if ws.logs.isEmpty {
            Text("No activity yet")
              .font(.system(size: 13, weight: .regular, design: .monospaced))
              .foregroundColor(.white.opacity(0.4))
              .italic()
          } else if !isSummarizingLogs {
            Text("Tap the logs button to fetch activity summary")
              .font(.system(size: 13, weight: .regular, design: .monospaced))
              .foregroundColor(.white.opacity(0.4))
              .italic()
          }
        }
      }
      .frame(maxHeight: 400)
    }
    .padding(16)
    .background(
      RoundedRectangle(cornerRadius: 16)
        .fill(Color.white.opacity(0.05))
        .overlay(
          RoundedRectangle(cornerRadius: 16)
            .stroke(Color.white.opacity(0.1), lineWidth: 1)
        )
    )
  }
  
  private var debugCard: some View {
    VStack(alignment: .leading, spacing: 12) {
      Label("Debug Information", systemImage: "ant.circle")
        .font(.system(size: 16, weight: .semibold, design: .rounded))
        .foregroundColor(.white)
      
      VStack(alignment: .leading, spacing: 8) {
        debugRow("State", ws.state.rawValue)
        debugRow("WebSocket", normalizedWs() ?? "(invalid)")
        debugRow("Session ID", String(env.sessionId.prefix(12)) + "...")
        debugRow("Token", String(env.token.prefix(12)) + "...")
        if !ws.lastEvent.isEmpty { debugRow("Last Event", ws.lastEvent) }
        if !ws.closeInfo.isEmpty { debugRow("Close Info", ws.closeInfo) }
        if !ws.lastAck.isEmpty { debugRow("Last Ack", ws.lastAck) }
        if !ws.lastPayload.isEmpty { debugRow("Payload", ws.lastPayload, lineLimit: 2) }
      }
      .padding(12)
      .background(Color.black.opacity(0.3))
      .cornerRadius(8)
    }
    .padding(16)
    .background(
      RoundedRectangle(cornerRadius: 16)
        .fill(Color.white.opacity(0.05))
        .overlay(
          RoundedRectangle(cornerRadius: 16)
            .stroke(Color.white.opacity(0.1), lineWidth: 1)
        )
    )
  }
  
  private func debugRow(_ label: String, _ value: String, lineLimit: Int = 1) -> some View {
    HStack(alignment: .top) {
      Text(label + ":")
        .font(.system(size: 12, weight: .semibold, design: .monospaced))
        .foregroundColor(.white.opacity(0.5))
        .frame(width: 80, alignment: .leading)
      
      Text(value)
        .font(.system(size: 12, weight: .regular, design: .monospaced))
        .foregroundColor(.white.opacity(0.8))
        .lineLimit(lineLimit)
        .textSelection(.enabled)
      
      Spacer()
    }
  }
  
  private var inputBar: some View {
    VStack(spacing: 0) {
      Divider()
        .background(Color.white.opacity(0.2))
      
      HStack(spacing: 12) {
        HStack {
          TextField("Type a message…", text: $input)
            .font(.system(size: 16, weight: .regular, design: .rounded))
            .foregroundColor(.white)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled(true)
            .submitLabel(.send)
            .onSubmit(onSend)
            .focused($inputFocused)
            .accentColor(.blue)
          
          if !input.isEmpty {
            Button(action: { input = "" }) {
              Image(systemName: "xmark.circle.fill")
                .font(.system(size: 16))
                .foregroundColor(.white.opacity(0.5))
            }
          }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color.white.opacity(0.1))
        .cornerRadius(24)
        
        Button(action: onRecordOrStop) {
          ZStack {
            Circle()
              .fill(sttButtonColor)
              .frame(width: 44, height: 44)
            
            Image(systemName: sttButtonIcon)
              .font(.system(size: 20, weight: .semibold))
              .foregroundColor(.white)
          }
        }
        .disabled(sttButtonDisabled)
        
        Button(action: onSend) {
          ZStack {
            Circle()
              .fill(sendButtonColor)
              .frame(width: 44, height: 44)
            
            Image(systemName: "paperplane.fill")
              .font(.system(size: 18, weight: .semibold))
              .foregroundColor(.white)
          }
        }
        .disabled(ws.state != .open || input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
      }
      .padding(.horizontal, 16)
      .padding(.vertical, 12)
      .background(
        Color(red: 0.08, green: 0.08, blue: 0.12)
          .overlay(
            LinearGradient(gradient: Gradient(colors: [Color.white.opacity(0.05), Color.clear]), startPoint: .top, endPoint: .bottom)
          )
      )
    }
  }
  
  private var sttButtonIcon: String {
    if case .recording = stt { return "stop.fill" }
    return "mic.fill"
  }
  
  private var sttButtonColor: Color {
    if case .recording = stt { return Color.red }
    if sttButtonDisabled { return Color.white.opacity(0.2) }
    return Color.blue
  }
  
  private var sttButtonDisabled: Bool {
    if case .uploading = stt { return true }
    if case .transcribing = stt { return true }
    if case .sending = stt { return true }
    return false
  }
  
  private var sendButtonColor: Color {
    ws.state != .open || input.isEmpty ? Color.white.opacity(0.2) : Color.green
  }
  
  private func logColor(for level: String) -> Color {
    switch level.lowercased() {
    case "error": return .red
    case "warn": return .orange
    case "info": return .blue
    case "debug": return .purple
    default: return .white.opacity(0.6)
    }
  }

  private func onAppear() {
    healthCheck()
    connect()
  }
  
  private func timeStr(_ d: Date) -> String {
    let f = DateFormatter()
    f.dateFormat = "HH:mm:ss"
    return f.string(from: d)
  }
  
  private func normalizedWs() -> String? {
    guard var u = URL(string: env.relayWsUrl) else { return nil }
    u.deleteLastPathComponent()
    return u.absoluteString.hasSuffix("/ws") ? u.absoluteString : (URL(string: env.relayWsUrl)?.absoluteString ?? env.relayWsUrl)
  }

  private func healthCheck() {
    guard var comp = URLComponents(string: env.relayWsUrl) else { return }
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
        if let attrs = try? FileManager.default.attributesOfItem(atPath: url.path), let size = attrs[.size] as? NSNumber {
          let sizeInMB = Double(size.intValue) / (1024.0 * 1024.0)
          print("Audio file size: \(String(format: "%.2f", sizeInMB)) MB (\(size.intValue) bytes)")
          if size.intValue > 25*1024*1024 {
            showError("Too large", "Audio exceeds 25 MB free-tier limit.")
            resetStt(); return
          }
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
    // Clean up old audio files in cache asynchronously
    DispatchQueue.global(qos: .background).async {
      let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
      if let files = try? FileManager.default.contentsOfDirectory(at: caches, includingPropertiesForKeys: nil) {
        for file in files where file.lastPathComponent.hasPrefix("sound-") && file.pathExtension == "wav" {
          try? FileManager.default.removeItem(at: file)
        }
      }
    }
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
  
  private func fetchAndSummarizeLogs() {
    isSummarizingLogs = true
    logSummary = ""
    
    // Request filtered logs optimized for summarization
    ws.requestFilteredLogs()
    
    // Set up observer to wait for filtered logs response
    ws.onFilteredLogs = { filteredItems in
      // Convert filtered strings to a format the summarizer can use
      let formattedText = filteredItems.joined(separator: "\n")
      
      // Use the summarizer with pre-filtered content
      self.logSummarizer.summarizeFilteredText(formattedText) { result in
        self.isSummarizingLogs = false
        switch result {
        case .success(let summary):
          self.logSummary = summary
        case .failure(let error):
          self.logSummary = "Failed to summarize: \(error.localizedDescription)"
        }
      }
    }
  }
}