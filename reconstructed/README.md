# Glint 1.6.3 — 重建工程

本目录是根据 `Glint.dylib 1.6.3` 逆向得到的可编译 Theos 工程。
逆向过程、证据与置信度说明见上一级的 `Glint_逆向分析报告.md`。

## 目录

| 路径 | 说明 |
| --- | --- |
| `Headers/` | 23 个类的接口。**由 ObjC 元数据直接生成**，含精确 ivar 偏移与 291 个方法签名 |
| `Tweak.xm` | 20 条 hook。4 条稳定类用 Logos，状态栏那 16 条用 `MSHookMessageEx` 按 Class 指针挂（与原实现一致，支持新旧类名） |
| `Sources/` | 实现。核心是 `GLTClock.m`（渲染引擎）与 `GLTController.m`（状态机） |
| `prefs/` | 设置面板 bundle。`Resources/` 下的 plist 与图标是原始文件 |
| `layout/` | PreferenceLoader 入口 plist（原始文件） |
| `Glint.plist` | MobileSubstrate filter（原始文件，仅注入 SpringBoard） |

## 编译

```bash
export THEOS=/opt/theos
make package THEOS_PACKAGE_SCHEME=rootless
```

产物：`packages/com.antonym.glint_1.6.3_iphoneos-arm64.deb`

需要：Theos、iOS SDK 14+、`ldid`。`ARCHS = arm64 arm64e`。

## 从哪读起

1. `Headers/GLTController.h` —— 27 个 ivar 就是整个状态机
2. `Sources/GLTClock.m` —— 这个 tweak 的全部视觉技巧都在这里
3. `Sources/GLTController.m` 的 `renderClocks` / `contentForPill:` / `platterContent`
4. `Tweak.xm` 末尾的 `%ctor` —— 20 条 hook 的注册表

## 已知差异（推断而非逐条验证）

报告第 11.3 节有完整清单。集中在：

- 徽标 / 进度条的绘制几何（`GLTPillContent.m`）
- 卡片内边距拆分（`GLTPlatterView.m` 的 `heightForWidth:`）
- 选择器网格列数与入场曲线（`GLTController.m` 的 `showPicker`）
- `visibleDateOfLabel:` 的返回值语义

这些都带注释标注，可用真机逐项对照修正。

## 修改约定

- `GLTPill` 枚举**只能往后追加**，数值是持久化到用户默认值的
- 新增 pill 需要同步 5 处：`GlintPrivate.h`、`GLTPrefs` 的 `nameForPill:` / `symbolForPill:` / `pillOrder`、`contentForPill:`、`prefs/Resources/Root.plist`
- 私有 API 调用一律先 `respondsToSelector:` / `NSClassFromString` 判空，失败走公开回退
