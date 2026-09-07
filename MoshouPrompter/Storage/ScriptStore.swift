import Foundation

final class ScriptStore {

    static let shared = ScriptStore()

    private(set) var scripts: [Script] = []
    private let fileURLs: [URL]
    private static let backupKey = "com.moshou.prompter.scripts.backup"

    private init() {
        fileURLs = ScriptStore.candidateURLs()
        load()
        if scripts.isEmpty {
            scripts = [ScriptStore.sampleScript()]
            save()
        }
    }

    // MARK: - Persistence
    //
    // 带 no-sandbox / platform-application entitlement 时系统可能收紧容器访问，
    // 所以这里准备多个落盘位置依次尝试，并额外在 UserDefaults 留一份兜底备份，
    // 保证文稿不会因为目录不可写而丢失。

    private static func candidateURLs() -> [URL] {
        let fm = FileManager.default
        var urls: [URL] = []
        if let docs = fm.urls(for: .documentDirectory, in: .userDomainMask).first {
            urls.append(docs.appendingPathComponent("scripts.json"))
        }
        if let support = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first {
            try? fm.createDirectory(at: support, withIntermediateDirectories: true)
            urls.append(support.appendingPathComponent("scripts.json"))
        }
        if let caches = fm.urls(for: .cachesDirectory, in: .userDomainMask).first {
            urls.append(caches.appendingPathComponent("scripts.json"))
        }
        urls.append(URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("scripts.json"))
        return urls
    }

    func load() {
        for url in fileURLs {
            if let data = try? Data(contentsOf: url),
               let list = try? JSONDecoder().decode([Script].self, from: data),
               !list.isEmpty {
                scripts = list
                return
            }
        }
        if let data = UserDefaults.standard.data(forKey: ScriptStore.backupKey),
           let list = try? JSONDecoder().decode([Script].self, from: data) {
            scripts = list
        }
    }

    func save() {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted]
        guard let data = try? encoder.encode(scripts) else { return }
        UserDefaults.standard.set(data, forKey: ScriptStore.backupKey)
        for url in fileURLs {
            do {
                try data.write(to: url, options: .atomic)
                return
            } catch {
                continue
            }
        }
    }

    // MARK: - CRUD

    func add(title: String, text: String) -> Script {
        let script = Script(title: title, text: text)
        scripts.insert(script, at: 0)
        save()
        return script
    }

    func update(_ script: Script) {
        guard let index = scripts.firstIndex(where: { $0.id == script.id }) else { return }
        scripts[index] = script
        save()
    }

    func delete(id: String) {
        scripts.removeAll { $0.id == id }
        save()
    }

    func script(id: String) -> Script? {
        return scripts.first { $0.id == id }
    }

    // MARK: - Sample

    static func sampleScript() -> Script {
        let text = """
        欢迎使用墨守提词器。

        一、基本用法
        1. 点右上角「新建」写稿，或从「文件」App 导入 txt。
        2. 在本页左滑文稿可一键开启悬浮提词。
        3. 全屏提词：进入文稿后点右上角「全屏」。

        二、悬浮窗
        · 应用内悬浮：拖动文字区可移动，右下角把手可缩放。
        · 系统级悬浮：设置里打开后，切到系统相机、抖音、腾讯会议，
          提词窗依然浮在最上层，边拍边看词。
        · 控制条从左到右依次是：播放/暂停、减速、加速、
          缩小字号、放大字号、镜像、点击穿透、关闭。

        三、小技巧
        · 用平板 + 提词器玻璃时，打开「镜像」可以做正反镜像。
        · 速度单位是「点/秒」，一般 40~80 比较舒服。
        · 打开「点击穿透」后，文字区不再吃掉触摸，
          可以直接操作下面的 App。

        把这段文字删掉，开始写你的稿子吧。
        """
        return Script(title: "使用说明", text: text)
    }
}
