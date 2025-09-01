import Foundation
import AVFoundation

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
      try session.setCategory(.playAndRecord, mode: .spokenAudio, options: [.defaultToSpeaker, .allowBluetooth])
      try session.setActive(true)
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
    if let u = url { completion(.success(u)) } else { completion(.failure(NSError(domain: "rec", code: -3, userInfo: [NSLocalizedDescriptionKey: "no file"])))}
    do { try AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation) } catch {}
  }
}
