import Foundation

final class ScriptStore {

    static let shared = ScriptStore()

    private(set) var scripts: [Script] = []
    private let fileURL: URL

    private init() {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
        fileURL = (docs ?? URL(fileURLWithPath: NSTemporaryDirectory()))
            .appendingPathComponent("scripts.json")
        load()
        if scripts.isEmpty {
            scripts = [ScriptStore.sampleScript()]
            save()
        }
    }

    // MARK: - Persistence

    func load() {
        guard let data = try? Data(contentsOf: fileURL),
              let list = try? JSONDecoder().decode([Script].self, from: data) else { return }
        scripts = list
    }

    func save() {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted]
        guard let data = try? encoder.encode(scripts) else { return }
        try? data.write(to: fileURL, options: .atomic)
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
