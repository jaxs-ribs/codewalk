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
            
            print("[Recorder] Audio session configured and ACTIVE with 5ms buffer")
            
            // Pre-create a recorder to warm up the recording pipeline
            prepareRecorder()
            
        } catch {
            print("[Recorder] Failed to setup audio session: \(error)")
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
            print("[Recorder] Recording pipeline warmed up")
            
        } catch {
            print("[Recorder] Failed to warm up recorder: \(error)")
        }
    }
    
    private func requestPermission() {
        AVAudioSession.sharedInstance().requestRecordPermission { granted in
            if !granted {
                print("[Recorder] Microphone permission denied")
            } else {
                print("[Recorder] Microphone permission granted")
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
                print("[Recorder] Failed to start recording")
                return false
            }
            
            self.recorder = newRecorder
            self.fileURL = url
            
            print("[Recorder] Recording started INSTANTLY: \(url.lastPathComponent)")
            return true
            
        } catch {
            print("[Recorder] Failed to create recorder: \(error)")
            return false
        }
    }
    
    func stop() -> URL? {
        guard let recorder = recorder else {
            print("[Recorder] No active recording")
            return nil
        }
        
        recorder.stop()
        self.recorder = nil
        
        let url = fileURL
        fileURL = nil
        
        if let url = url {
            print("[Recorder] Recording stopped: \(url.lastPathComponent)")
        }
        
        // Keep session active for next recording (no deactivation)
        
        return url
    }
    
    deinit {
        // Only deactivate when app is closing
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
}