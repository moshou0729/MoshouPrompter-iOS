# 墨守提词器 (MoshouPrompter-iOS)

iOS 14 提词器，UIKit 全手写，**支持系统级悬浮窗**（需 TrollStore / 越狱环境）。

## 功能

- 文稿管理：新建 / 编辑 / 复制 / 删除 / 从剪贴板 / 从文件导入 .txt
- 全屏提词：可调字号、行距、左右边距、滚动速度、背景色、参考线、水平镜像
- 应用内悬浮窗：可拖动 / 缩放 / 点击穿透
- **系统级悬浮窗**：用 SpringBoardServices 的
  `SBSAccessibilityWindowHostingController` 把悬浮窗注册成无障碍窗口，
  切到系统相机 / 抖音 / 会议 App 也能继续显示
- 后台保活：开启系统级悬浮时，循环播放一段运行时生成的静音音频，
  让 App 在后台时提词文字依然能滚动
- TrollStore 直装：无签名 IPA，TrollStore 直接安装

## 构建

```bash
git push origin main   # 触发 GitHub Actions（macos-14 + Xcode 15.4）
```

产物 `MoshouPrompter-vX.Y.Z.ipa` 作为 workflow artifact 上传，
下载后用 TrollStore 安装即可。

## 技术要点

- `SBS/SBSWindowHosting.h/m` 是系统级悬浮窗的私有 API 桥接层，
  通过 `NSInvocation + NSSelectorFromString` 动态调用，
  编译期不链接私有框架，运行时拿不到就自动降级为应用内悬浮。
- `Support/KeepAlive.swift` 用 GCD 定时器 + AVAudioSession(.playback) + 运行时
  生成的静音 WAV 循环播放，让 App 切到后台不被冻结。
- `Prompter/PrompterEngine.swift` 是滚动引擎，文字按「点/秒」匀速上滚，
  用 `DispatchSourceTimer` 而非 CADisplayLink，保证后台时仍能跑。
- `Float/FloatingPrompterViewController.swift` 里的 `PassthroughView`
  实现了点击穿透：文字区不挡下面的 App，控制条仍可点。
