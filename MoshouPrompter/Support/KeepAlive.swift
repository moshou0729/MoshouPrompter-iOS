import AVFoundation
import Foundation
import UIKit

/// 后台保活：播放一段「运行时生成的静音 WAV」并循环，
/// 配合 Info.plist 的 UIBackgroundModes=audio，
/// 让 App 切到后台后系统级悬浮窗里的文字还能继续滚。
///
/// 三个要点（都是踩过的坑）：
/// 1. backgroundTask 到期的 handler 绝不能调 stop()，否则等于自己掐断音频、
///    系统立刻挂起 App，悬浮窗就冻成一张静态图。正确做法是原地续期。
/// 2. 音频被打断（别的 App 抢声道、来电）后必须自己恢复播放。
/// 3. 加心跳兜底：发现 player 停了就重新拉起来。
final class KeepAlive {

    static let shared = KeepAlive()

    private var player: AVAudioPlayer?
    private var isRunning = false
    private var backgroundTask: UIBackgroundTaskIdentifier = .invalid
    private var heartbeat: Timer?
    private var displayLink: CADisplayLink?
    private var lastReassertSecond: Int = -1
    private var interruptionObserver: NSObjectProtocol?

    private init() {}

    // MARK: - Public

    func start() {
        guard !isRunning else { return }
        isRunning = true

        activateSession()
        ensurePlayer()
        player?.play()

        installInterruptionObserver()
        startBackgroundTask()
        startHeartbeat()
        startDisplayLink()
    }

    func stop() {
        guard isRunning else { return }
        isRunning = false

        player?.pause()
        heartbeat?.invalidate()
        heartbeat = nil
        stopDisplayLink()
        removeInterruptionObserver()
        endBackgroundTask()

        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    // MARK: - Audio

    private func activateSession() {
        let session = AVAudioSession.sharedInstance()
        // mixWithOthers：不抢抖音/相机的声音
        try? session.setCategory(.playback, mode: .default, options: [.mixWithOthers])
        try? session.setActive(true)
    }

    private func ensurePlayer() {
        if player != nil { return }
        let url = KeepAlive.silentFileURL()
        if !FileManager.default.fileExists(atPath: url.path) {
            try? KeepAlive.makeSilentWAV().write(to: url)
        }
        let created = try? AVAudioPlayer(contentsOf: url)
        created?.numberOfLoops = -1
        created?.volume = 0.0
        player = created
    }

    // MARK: - Background task（到期续期，不是停活）

    private func startBackgroundTask() {
        endBackgroundTask()
        backgroundTask = UIApplication.shared.beginBackgroundTask { [weak self] in
            // 到期：续一个新的。这里千万不能 stop()！
            guard let self = self, self.isRunning else { return }
            self.startBackgroundTask()
        }
    }

    private func endBackgroundTask() {
        if backgroundTask != .invalid {
            UIApplication.shared.endBackgroundTask(backgroundTask)
            backgroundTask = .invalid
        }
    }

    // MARK: - Heartbeat

    private func startHeartbeat() {
        heartbeat?.invalidate()
        let timer = Timer.scheduledTimer(withTimeInterval: 4.0, repeats: true) { [weak self] _ in
            guard let self = self, self.isRunning else { return }
            if self.player?.isPlaying != true {
                self.activateSession()
                self.ensurePlayer()
                self.player?.play()
                self.startBackgroundTask()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        heartbeat = timer
    }

    // MARK: - Display link（保持 SBS 窗口在 background 持续合成）
    //
    // iOS 14 上 App 进入 background 后，SpringBoard 默认会在 1 秒左右释放
    // SBS 窗口的 contextId，悬浮窗随之消失。这里挂一个 CADisplayLink，
    // 每帧主动触发 window 的 layer 提交新内容，让 SpringBoard 认为 window
    // 仍在活动状态，从而继续合成。配合音频 + beginBackgroundTask，App
    // 不会被冻结，CADisplayLink 在 background 下也会持续触发。
    private func startDisplayLink() {
        stopDisplayLink()
        let link = CADisplayLink(target: self, selector: #selector(displayLinkTick(_:)))
        link.preferredFramesPerSecond = 10  // 10 fps 已够驱动 layer 重绘，省电
        link.add(to: .main, forMode: .common)
        displayLink = link
    }

    private func stopDisplayLink() {
        displayLink?.invalidate()
        displayLink = nil
    }

    @objc private func displayLinkTick(_ link: CADisplayLink) {
        guard isRunning else { return }
        // 1) 强制让 floating window 的 layer 提交一帧
        if let window = FloatingWindowManager.shared.unsafeWindow {
            window.layer.setNeedsDisplay()
            window.rootViewController?.view.setNeedsLayout()
            window.rootViewController?.view.layoutIfNeeded()
        }
        // 2) 每秒最多主动 reassert 一次（防御 SpringBoard 释放）
        let second = Int(link.timestamp)
        if second != lastReassertSecond, PrompterSettings.shared.systemWide {
            lastReassertSecond = second
            FloatingWindowManager.shared.touchForBackground()
        }
    }

    // MARK: - Interruption

    private func installInterruptionObserver() {
        guard interruptionObserver == nil else { return }
        interruptionObserver = NotificationCenter.default.addObserver(
            forName: AVAudioSession.interruptionNotification,
            object: nil,
            queue: .main) { [weak self] note in
                guard let self = self, self.isRunning else { return }
                guard let raw = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
                      let type = AVAudioSession.InterruptionType(rawValue: raw) else { return }
                if type == .ended {
                    self.activateSession()
                    self.player?.play()
                }
            }
    }

    private func removeInterruptionObserver() {
        if let observer = interruptionObserver {
            NotificationCenter.default.removeObserver(observer)
            interruptionObserver = nil
        }
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
