<p align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="docs/logo-dark.png">
    <img src="docs/logo.png" width="160" alt="ScreenRules logo">
  </picture>
</p>

<h1 align="center">ScreenRules</h1>

<p align="center">macOS 菜单栏小工具：让每个 App 的窗口<b>在你指定的屏幕</b>、以<b>你指定的大小</b>打开。</p>

## 为什么做这个

macOS 几乎把所有新窗口都开在**主屏**。双屏用户只能不停拖窗口。系统自带的 Dock「分配给显示器 N 的桌面」和 Spaces 深度绑定，行为经常不一致。

ScreenRules 用按 App 的规则解决：

- **屏幕规则** —— App 的新窗口自动开在主屏或副屏
- **尺寸规则** —— 可选把窗口调整为目标屏的 50%～100%，居中放置
- **输入法规则** —— 可选在每次切换到该 App 时自动切换到指定输入法（如 ABC / 拼音）
- **每个窗口只归位一次** —— 窗口出现时执行一次规则（0.25s / 1s 两轮修正，赢过那些建窗后自己乱动的 App，比如点 Dock 抢位置的）；之后手动移动、调整尺寸不再被干预
- 只管理标准主窗口 —— 输入法候选框、对话框、抽屉、浮动面板一律不碰

## 安装运行

需要 macOS 13+ 和 Swift 工具链（装 Xcode Command Line Tools 即可，项目不依赖 Xcode 工程）。

```sh
git clone https://github.com/cc-hearts/screen-rules.git
cd screen-rules
./run.sh        # 构建 + （重）启动
```

首次启动按提示授予**辅助功能权限**（系统设置 → 隐私与安全性 → 辅助功能）。App 每 1.5 秒自动检测授权状态，无需重启。

## 使用

1. 把要设置的 App 切到前台
2. 点菜单栏的 ScreenRules 图标 →「当前 App：xxx」
3. 选「屏幕」和/或「窗口大小」
4. 规则立即对已打开的窗口生效，之后每个新窗口都遵守

其他菜单项：

- **立即按规则整理所有窗口** —— 一键把所有有规则的 App 的窗口归位
- **打开规则文件…** —— 规则存放在 `~/Library/Application Support/ScreenRules/rules.json`
- **打开调试日志…** —— 每个监听到的事件和搬移结果都记录在 `debug.log`

## 原理

- 通过 `AXObserver` 监听所有常规 App 的 `kAXWindowCreatedNotification`，配合 `NSWorkspace` 的启动 / 激活 / 退出通知
- 按窗口 ID 去重，每个窗口只执行一次：创建时（0.25s / 1s 两轮修正），或对 ScreenRules 启动前已存在、AX 事件漏掉的窗口，在 App 下次激活时补一次
- 只有显式操作才会重新归位：菜单里改规则、或「立即按规则整理所有窗口」（未运行的 App 跳过，绝不被启动）
- 搬屏保持窗口尺寸、按相对位置映射；尺寸规则按目标屏可见区域缩放并居中
- 输入法切换基于 Text Input Source Services（TIS），在 App 激活时执行 —— 这部分不需要辅助功能权限
- 屏幕按**主/副语义**匹配而非硬件 ID —— 重新插拔、换线都不会让规则失效
- 用固定自签名证书签名（`.signing/`，不进 git），重新构建后授权不丢失

纯 SwiftPM / AppKit，约 500 行，零依赖。

## 已知限制

- 无法操作以其他用户/权限运行的 App 的窗口
- 全屏窗口按设计不处理
- 极少数 App 的非标准窗口拒绝被移动，遇到请看调试日志

## 许可证

[MIT](LICENSE)
