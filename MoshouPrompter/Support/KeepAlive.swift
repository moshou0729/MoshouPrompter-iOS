import AVFoundation
import Foundation
import UIKit

/// 后台保活：播放一段「运行时生成的静音 WAV」并循环，
/// 配合 Info.plist 的 UIBackgroundModes=audio，
/// 让 App 切到后台后系统级悬浮窗里的文字还能继续滚。
final class KeepAlive {

    static let shared = KeepAlive()

    private var player: AVAudioPlayer?
    private var isRunning = false
    private var backgroundTask: UIBackgroundTaskIdentifier = .invalid

    private init() {}

    func start() {
        if isRunning { return }
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .default, options: [.mixWithOthers])
        try? session.setActive(true)

        if player == nil {
            let url = KeepAlive.silentFileURL()
            if !FileManager.default.fileExists(atPath: url.path) {
                try? KeepAlive.makeSilentWAV().write(to: url)
            }
            let created = try? AVAudioPlayer(contentsOf: url)
            created?.numberOfLoops = -1
            created?.volume = 0.0
            player = created
        }
        player?.play()
        isRunning = true

        // 音频之外再加一层后台任务，双保险，避免切走后被立刻挂起
        if backgroundTask == .invalid {
            backgroundTask = UIApplication.shared.beginBackgroundTask { [weak self] in
                self?.stop()
            }
        }
    }

    func stop() {
        if !isRunning && backgroundTask == .invalid { return }
        player?.stop()
        isRunning = false
        if backgroundTask != .invalid {
            UIApplication.shared.endBackgroundTask(backgroundTask)
            backgroundTask = .invalid
        }
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    // MARK: - Silent WAV (generated at runtime, no binary asset needed)

    private static func silentFileURL() -> URL {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
        let dir = caches ?? URL(fileURLWithPath: NSTemporaryDirectory())
        return dir.appendingPathComponent("silence.wav")
    }

    static func makeSilentWAV(seconds: Int = 5, sampleRate: Int = 8000) -> Data {
        let sampleCount = sampleRate * seconds
        let dataSize = sampleCount * 2
        var data = Data()

        func ascii(_ text: String) {
            data.append(contentsOf: Array(text.utf8))
        }
        func le32(_ value: UInt32) {
            data.append(UInt8(value & 0xFF))
            data.append(UInt8((value >> 8) & 0xFF))
            data.append(UInt8((value >> 16) & 0xFF))
            data.append(UInt8((value >> 24) & 0xFF))
        }
        func le16(_ value: UInt16) {
            data.append(UInt8(value & 0xFF))
            data.append(UInt8((value >> 8) & 0xFF))
        }

        ascii("RIFF")
        le32(UInt32(36 + dataSize))
        ascii("WAVE")
        ascii("fmt ")
        le32(16)
        le16(1)                              // PCM
        le16(1)                              // mono
        le32(UInt32(sampleRate))             // sample rate
        le32(UInt32(sampleRate * 2))         // byte rate
        le16(2)                              // block align
        le16(16)                             // bits per sample
        ascii("data")
        le32(UInt32(dataSize))
        data.append(contentsOf: [UInt8](repeating: 0, count: dataSize))
        return data
    }
}
