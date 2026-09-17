# ScreenRules

菜单栏小工具：让指定 App 的**新窗口自动打开在主屏 / 副屏**。

## 原理

- 通过 Accessibility API（AXObserver）监听所有 App 的 `kAXWindowCreatedNotification`（新窗口创建事件）
- 命中规则后，把窗口搬到目标屏：保持窗口尺寸，按“相对位置比例”映射到目标屏，并夹取在可见区域内
- 规则持久化在 `~/Library/Application Support/ScreenRules/rules.json`
- 纯 AppKit / SwiftPM 实现，不依赖 Xcode，无第三方库

## 构建 & 运行

```sh
./build.sh            # 编译 + 打包 + 临时签名，产出 ScreenRules.app
open ScreenRules.app  # 启动（菜单栏出现双显示器图标）
```

首次启动会弹“辅助功能”授权请求，去 **系统设置 → 隐私与安全性 → 辅助功能** 里勾选 ScreenRules。
授权会自动生效（App 每秒轮询检测），菜单栏图标点开没有 ⚠️ 警告即表示就绪。

## 使用

1. 切换到你想设置的 App（让它成为前台 App）
2. 点菜单栏的 ScreenRules 图标 → “当前 App：xxx”
3. 选「新窗口打开在主屏 / 副屏」，规则立即生效（已打开的窗口也会顺便搬过去）
4. 「立即按规则整理所有窗口」= 一键把所有有规则的 App 的窗口归位

## 备注

- 显示器识别用「主屏/副屏」语义而不是硬件 ID，所以重新插拔、换接口后规则依然正确（主屏 = 系统设置里带菜单栏的那台）
- 重新 `build.sh` 后临时签名的哈希会变，如果权限失效，在辅助功能列表里删掉旧条目重新授权即可
- 想开机自启：系统设置 → 通用 → 登录项 → 添加 ScreenRules.app
- 已知限制：少数 App（部分 Electron / 自绘窗口）创建窗口后还会自己抢位置，窗口创建后有 0.25s 延迟再搬，正常都能盖住
