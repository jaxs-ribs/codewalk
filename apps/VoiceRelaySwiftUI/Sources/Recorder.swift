import Foundation
import AVFoundation

/// Records audio to WAV files (16kHz, mono, 16-bit PCM) for STT transcription.
final class Recorder: NSObject, AVAudioRecorderDelegate {
  private var recorder: AVAudioRecorder?
  private(set) var fileURL: URL?

  func requestPermission(completion: @escaping (Bool)->Void) {
    AVAudioSession.sharedInstance().requestRecordPermission { granted in
      DispatchQueue.main.async { completion(granted) }
    }
  }

  func start(completion: @escaping (Result<URL,Error>)->Void) {
    let session = AVAudioSession.sharedInstance()
    do {
      // Only set category if it's different to avoid unnecessary work
      if session.category != .playAndRecord {
        try session.setCategory(.playAndRecord, mode: .spokenAudio, options: [.defaultToSpeaker, .allowBluetooth])
      }
      // Only activate if not already active
      if !session.isOtherAudioPlaying {
        try session.setActive(true, options: [])
      }
    } catch { return completion(.failure(error)) }

    let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
    let url = caches.appendingPathComponent("sound-\(UUID().uuidString).wav")
    let settings: [String: Any] = [
      AVFormatIDKey: kAudioFormatLinearPCM,
      AVSampleRateKey: 16000,
      AVNumberOfChannelsKey: 1,
      AVLinearPCMBitDepthKey: 16,
      AVLinearPCMIsFloatKey: false,
      AVLinearPCMIsBigEndianKey: false,
      AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue,
    ]
    do {
      recorder = try AVAudioRecorder(url: url, settings: settings)
      recorder?.delegate = self
      recorder?.isMeteringEnabled = true
      recorder?.prepareToRecord()
      guard recorder?.record() == true else { throw NSError(domain: "rec", code: -1, userInfo: [NSLocalizedDescriptionKey: "record failed"]) }
      fileURL = url
      completion(.success(url))
    } catch {
      completion(.failure(error))
    }
  }

  func stop(completion: @escaping (Result<URL,Error>)->Void) {
    guard let r = recorder else { return completion(.failure(NSError(domain: "rec", code: -2, userInfo: [NSLocalizedDescriptionKey: "not recording"])))}
    r.stop()
    recorder = nil
    let url = fileURL
    fileURL = nil
    if let u = url { 
      completion(.success(u))
      // Deactivate audio session asynchronously to avoid blocking UI
      DispatchQueue.global(qos: .background).async {
        do { 
          try AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation) 
        } catch {
          print("Failed to deactivate audio session: \(error)")
        }
      }
    } else { 
      completion(.failure(NSError(domain: "rec", code: -3, userInfo: [NSLocalizedDescriptionKey: "no file"])))
    }
  }
}
