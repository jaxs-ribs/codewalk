import Foundation
import AVFoundation

/// Ultra high-performance audio recorder with always-ready recording
final class Recorder: NSObject {
    private var recorder: AVAudioRecorder?
    private var fileURL: URL?
    private let recordingQueue = DispatchQueue(label: "com.voiceagent.recording", qos: .userInteractive)
    private var isPrepared = false
    
    // Pre-configured recorder settings for reuse
    private let recorderSettings: [String: Any] = [
        AVFormatIDKey: kAudioFormatLinearPCM,
        AVSampleRateKey: 16000,
        AVNumberOfChannelsKey: 1,
        AVLinearPCMBitDepthKey: 16,
        AVLinearPCMIsFloatKey: false,
        AVLinearPCMIsBigEndianKey: false,
        AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
    ]
    
    override init() {
        super.init()
        // Immediately prepare everything
        setupAudioSession()
        requestPermission()
    }
    
    private func setupAudioSession() {
        // Do this synchronously on init to ensure it's ready
        do {
            let session = AVAudioSession.sharedInstance()
            
            // Configure for lowest latency recording
            try session.setCategory(.playAndRecord, 
                                   mode: .measurement,  // Lower latency than .spokenAudio
                                   options: [.defaultToSpeaker, .allowBluetooth])
            
            // Set preferred IO buffer duration for minimal latency (5ms)
            try session.setPreferredIOBufferDuration(0.005)
            
            // Activate session immediately and keep it active
            try session.setActive(true, options: [])
            
            log("Audio session configured and ACTIVE with 5ms buffer", category: .system, component: "Recorder")
            
            // Pre-create a recorder to warm up the recording pipeline
            prepareRecorder()
            
        } catch {
            logError("Failed to setup audio session: \(error)", component: "Recorder")
        }
    }
    
    private func prepareRecorder() {
        // Pre-initialize a recorder to warm up the system
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("warmup.wav")
        
        do {
            let warmupRecorder = try AVAudioRecorder(url: tempURL, settings: recorderSettings)
            warmupRecorder.prepareToRecord()
            
            // Start and immediately stop to fully initialize audio hardware
            warmupRecorder.record()
            warmupRecorder.stop()
            
            // Clean up warmup file
            try? FileManager.default.removeItem(at: tempURL)
            
            isPrepared = true
            log("Recording pipeline warmed up", category: .system, component: "Recorder")
            
        } catch {
            logError("Failed to warm up recorder: \(error)", component: "Recorder")
        }
    }
    
    private func requestPermission() {
        AVAudioSession.sharedInstance().requestRecordPermission { granted in
            if !granted {
                logError("Microphone permission denied", component: "Recorder")
            } else {
                log("Microphone permission granted", category: .system, component: "Recorder")
            }
        }
    }
    
    func startInstant() -> Bool {
        // Super fast synchronous start - no async needed since we're pre-warmed
        
        // Create file URL
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
        let url = caches.appendingPathComponent("recording-\(UUID().uuidString).wav")
        
        do {
            // Create new recorder (very fast since session is active)
            let newRecorder = try AVAudioRecorder(url: url, settings: recorderSettings)
            
            // Prepare and record immediately
            newRecorder.prepareToRecord()
            
            guard newRecorder.record() else {
                logError("Failed to start recording", component: "Recorder")
                return false
            }
            
            self.recorder = newRecorder
            self.fileURL = url
            
            log("Recording started: \(url.lastPathComponent)", category: .recorder)
            return true
            
        } catch {
            logError("Failed to create recorder: \(error)", component: "Recorder")
            return false
        }
    }
    
    func stop() -> URL? {
        guard let recorder = recorder else {
            log("No active recording", category: .recorder)
            return nil
        }
        
        recorder.stop()
        self.recorder = nil
        
        let url = fileURL
        fileURL = nil
        
        if let url = url {
            log("Recording stopped: \(url.lastPathComponent)", category: .recorder)
        }
        
        // Keep session active for next recording (no deactivation)
        
        return url
    }
    
    deinit {
        // Only deactivate when app is closing
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
}