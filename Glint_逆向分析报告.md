# Glint 1.6.3 逆向与重建报告

> 目标包：`com.antonym.glint_1.6.3_iphoneos-arm64.deb`
> 分析方法：Mach-O / ObjC 元数据全量还原 + arm64 反汇编人工精读（capstone）
> 产物：`reconstructed/`（可编译 Theos 工程，含 23 个类的完整接口与核心实现）

---

## 0. 结论速览

Glint 不是"新增一个状态栏视图"，而是**复用系统状态栏那颗时钟 label，把它的内容改画成一个药丸**。整套设计可以概括成一句话：

> 一个 `UIWindowLevelStatusBar` 的透明覆盖窗口负责交互，真正的视觉全部发生在系统 `STUIStatusBarStringView` 上；Glint 只是给它加了一张跟随运动的圆角背景图，并通过 hook 把系统写入的文字吞掉、换成自己的富文本。

由此推出的几条关键事实，也是维护时最容易踩坑的地方：

| 事实 | 证据 |
| --- | --- |
| 不创建任何常驻状态栏视图，只挂一个 `UIView` 背景（关联对象） | `+[GLTClock backgroundForLabel:create:]` @0xc524 |
| 系统写 label 时被"吞掉"而不是"覆盖"，原文字另行保存 | `setText:` @0x4894 走 `setSystemText:forLabel:` |
| 宽度靠 `intrinsicContentSize` / `sizeThatFits:` 加 padding 撑开 | 0x4a2c / 0x4a9c |
| 文字绘制靠 `drawTextInRect:` 内缩，图标/徽标靠 `NSTextAttachment` | 0x4b0c / 0xb8c4 |
| 只有一个 1 秒定时器驱动全局刷新 | `-[GLTController start]` @0x50d8 |
| 15 种 pill 全部走同一个"内容 → 富文本"管线，无分叉渲染 | `contentForPill:` @0x7638 跳转表 |

---

## 1. 包结构与元数据

```
com.antonym.glint_1.6.3_iphoneos-arm64.deb
├── control                        # Depends: mobilesubstrate, preferenceloader, firmware (>= 14.0)
└── data.tar.lzma
    └── var/jb/
        ├── Library/MobileSubstrate/DynamicLibraries/
        │   ├── Glint.dylib        # 531,360 B  ← 主 tweak
        │   └── Glint.plist        # Filter: Bundles = [com.apple.springboard]
        ├── Library/PreferenceBundles/GlintPrefs.bundle/
        │   ├── GlintPrefs         # 169,040 B  ← 设置面板
        │   ├── Info.plist         # NSPrincipalClass = GLTRootListController
        │   ├── Root.plist         # 27 个 specifier
        │   └── icon.png/@2x/@3x
        └── Library/PreferenceLoader/Preferences/GlintPrefs.plist
```

`Glint.dylib` 是 **FAT（arm64 + arm64e）**，均为现代 chained fixups：

| 项 | 值 |
| --- | --- |
| 切片 | arm64 (cpusubtype 0) @0x4000，arm64e (0x80000002) @0x44000 |
| `__text` | 0x4000 – 0x1c5ac（约 100 KB） |
| 类 | 23 个（全部是自有 `GLT*` 类，无 category） |
| 方法 | 291 个（含类方法） |
| selector | 620 个 |
| `__cfstring` | 286 条 |
| 导入符号 | 202 个 |
| rebase / bind | 2253 / 627 |
| 链接框架 | Foundation, UIKit, EventKit, CoreLocation, Contacts, MessageUI, CoreGraphics, QuartzCore, CydiaSubstrate |

结论：**纯 Objective-C + Logos**，没有 Swift、没有字符串加密、没有控制流混淆。方法名、ivar 名、类型编码全部完好，因此接口层可以 100% 复原。

---

## 2. 架构总览

```
                      ┌──────────────────────────────┐
   SpringBoard ──────▶│ -[SpringBoard application…]  │  hook #1
                      │   → [GLTController start]    │
                      └──────────────┬───────────────┘
                                     │
        ┌────────────────────────────▼─────────────────────────────┐
        │ GLTController (单例, 248 B ivar)                          │
        │  _window(GLTWindow)  _touchView  _platterView  _pickerView│
        │  _clockViews / _dateViews (NSHashTable, weak)             │
        │  _timer(1s) → tick                                        │
        └───┬───────────────┬────────────────┬──────────────┬───────┘
            │               │                │              │
   ┌────────▼──────┐ ┌──────▼───────┐ ┌──────▼──────┐ ┌─────▼──────┐
   │ pillContent   │ │ platterContent│ │  GLTClock   │ │ 采样/轮询   │
   │ (15 种内容)   │ │ (卡片工厂)    │ │ (渲染引擎)  │ │ 网络/设备   │
   └───────────────┘ └───────────────┘ └──────┬──────┘ └────────────┘
                                              │
                             ┌────────────────▼─────────────────┐
                             │ 系统 STUIStatusBarStringView      │
                             │  + 关联的 UIView 背景（圆角药丸） │
                             └──────────────────────────────────┘
```

数据层（全部是单例，懒加载）：

`GLTMedia`（MediaRemote）· `GLTEvents`（EventKit）· `GLTClockItems`（MobileTimer）· `GLTUnlocks`（notify）· `GLTWeather`（Open-Meteo）· `GLTPrefs`（CFPreferences）

---

## 3. Hook 全表（20 条）

构造函数位于 `__text` 起点 **0x4000**（`LC_DYLD_CHAINED_FIXUPS` 的 `__init_offsets` 只有一项）。

| # | 类 | Selector | 替换函数 | orig 槽 |
| --- | --- | --- | --- | --- |
| 1 | SpringBoard | `applicationDidFinishLaunching:` | 0x4334 | 0x34e78 |
| 2 | SBVolumeControl | `_presentVolumeHUDWithVolume:` | 0x4378 | 0x34e80 |
| 3 | SBVolumeControl | `initWithHUDController:ringerControl:telephonyManager:conferenceManager:` | 0x4420 | 0x34e88 |
| 4 | SBNotificationBannerDestination | `postNotificationRequest:` | 0x442c | 0x34e90 |
| 5 | SBMediaController | `_mediaRemoteNowPlayingInfoDidChange:` | 0x46dc | 0x34e98 |
| 6 | SBMediaController | `_mediaRemoteNowPlayingApplicationIsPlayingDidChange:` | 0x4720 | 0x34ea0 |
| 7 | SBMediaController | `_mediaRemoteNowPlayingApplicationDidChange:` | 0x4764 | 0x34ea8 |
| 8 | STUIStatusBarTimeItem | `applyUpdate:toDisplayItem:` | 0x47a8 | 0x34eb0 |
| 9 | STUIStatusBarStringView | `setText:` | 0x4894 | 0x34eb8 |
| 10 | 同上 | `setAttributedText:` | 0x4918 | 0x34ec0 |
| 11 | 同上 | `setTextColor:` | 0x49bc | 0x34ec8 |
| 12 | 同上 | `intrinsicContentSize` | 0x4a2c | 0x34ed0 |
| 13 | 同上 | `sizeThatFits:` | 0x4a9c | 0x34ed8 |
| 14 | 同上 | `drawTextInRect:` | 0x4b0c | 0x34ee0 |
| 15 | 同上 | `layoutSubviews` | 0x4bbc | 0x34ee8 |
| 16 | 同上 | `setCenter:` | 0x4c20 | 0x34ef0 |
| 17 | 同上 | `setFrame:` | 0x4c84 | 0x34ef8 |
| 18 | 同上 | `setAlpha:` | 0x4ce8 | 0x34f00 |
| 19 | 同上 | `setHidden:` | 0x4d4c | 0x34f08 |
| 20 | 同上 | `didMoveToWindow` | 0x4db0 | 0x34f10 |

**类名回退机制（0x4128–0x4180）**：状态栏那两个类在不同 iOS 版本上分别叫 `STUIStatusBarTimeItem` / `_UIStatusBarTimeItem`、`STUIStatusBarStringView` / `_UIStatusBarStringView`。原始实现是先用 `objc_getClass` 取现代名，为 nil 再取旧名，**拿到 Class 指针后直接用 `MSHookMessageEx` 挂**，而不是按名字 `%hook`。这是混合版本场景下更稳的写法，重建版 `Tweak.xm` 沿用了它。

---

## 4. 渲染引擎 `GLTClock`（最核心的部分）

`GLTClock` 没有实例、没有 ivar，全部是类方法 + 关联对象。这是全工程最值得学的设计。

### 4.1 状态标志

```
0x34f30  kStyledKey       关联对象：@YES 表示这个 label 正被 Glint 接管
0x34f31  isRendering      全局 BOOL，重入保护
0x34f32  kBackgroundKey   关联对象：companion UIView
0x34f38  styledLabels     NSHashTable（weak）— 所有被接管的背景视图
0x34f40  待处理淡出表     弱引用，防止连点导致快照堆积
0x34f58  kSystemTextKey   关联对象：系统原本要写的文字
0x34f60  ?                NSHashTable（weak）— 参与 layout 的 label 集合
```

### 4.2 关键数值

| 方法 | 值 |
| --- | --- |
| `+padding` | `UIEdgeInsets(0, 9, 0, 9)` —— 左右各 9pt |
| `+outsetForLabel:` | `clamp(屏幕坐标 origin.y − 2, 1.5, 4.5)` —— 背景相对 label 的垂直外扩 |
| `+layoutBackgroundOfLabel:` | 圆角 = `高度 / 2`（纯胶囊） |
| `+apply:…animated:` 默认背景 | `[UIColor colorWithWhite:0.06 alpha:0.72]`（近黑、72% 不透明） |
| `-renderClocks` 日期标签过渡 | duration 0.25s，delay 0.2s |

### 4.3 `apply:toLabel:background:textColor:animated:`（0xd070）

```
styled = isStyled(label)
if (!content && !styled) return                      // 什么都没发生过，直接退出

if (content):
    fadeIn = animated && styled
    if (fadeIn && label 在屏幕上 && alpha > 0.01):
        fadeOutSnapshotOfLabel(label)                // 旧内容做快照淡出
    isRendering = YES
    if (!styled) setSystemText(label.text)           // 记住系统原文
    styledLabels += label;  kStyledKey = @YES
    attr = [content attributedStringWithFont:label.font color:textColor]
    if (![label.attributedText isEqualToAttributedString:attr])
        label.attributedText = attr                  // 只在真的变了才写，避免无谓重绘
    label.textColor = textColor
    background.backgroundColor = bg
    isRendering = NO
    invalidateIntrinsicContentSize / superview.setNeedsLayout / label.setNeedsLayout
    layoutBackgroundOfLabel(label)
    if (fadeIn) fadeInLabel(label)
else:
    isRendering = YES
    kStyledKey = nil
    [backgroundForLabel:create:NO] removeFromSuperview
    kBackgroundKey = nil
    label.text = 取回系统原文
    isRendering = NO
    重算布局
```

`isRendering` 的作用非常关键：写入 `attributedText` / `textColor` 时会回调被 hook 的 setter，置位后这些 hook 直接 `return`，从而不污染 `kSystemTextKey`。

### 4.4 入场动画（0xd6bc）

三层同时挂到 `label.layer`：

| key | 类型 | 参数 |
| --- | --- | --- |
| `glint.fade` | CABasicAnimation(opacity) | 0 → 1，duration **0.24**，beginTime **now+0.1**，`kCAFillModeBackwards`，`EaseOut` |
| `glint.grow` | CASpringAnimation(transform.scale) | 0.9 → 1，damping **14**，stiffness **220**，mass **1** |
| `glint.rise` | CASpringAnimation(transform.translation.y) | 6 → 0，复用上一条的 damping/stiffness |

`duration = settlingDuration`。淡出快照（0xd450）：scale 0.92 + 位移 −6，duration 0.18。
`popLabel:`（0xdb28）：先 scale 0.94，再 `animateWithDuration:0.4 delay:0 usingSpringWithDamping:0.55 initialSpringVelocity:0.5`。

### 4.5 背景视图定位（0xca1c）

```
host = label.superview
frame = [label convertRect:label.bounds toView:host]
frame = CGRectInset(frame, -outset, -outset)
background.bounds = (0,0,w,h);  background.center = (midX, midY)
background.layer.cornerRadius = h / 2
```

每次 `layoutSubviews` / `setCenter:` / `setFrame:` / `setAlpha:` / `setHidden:` / `didMoveToWindow` 都会重跑这段——这就是"药丸永远贴着时钟走"的原因，也是它能扛住横竖屏切换和灵动岛布局变化的原因。

---

## 5. 控制器状态机

### 5.1 启动顺序（0x50d8）

```
枚举 UIApplication.connectedScenes，挑 screen == UIScreen.mainScreen 的 UIWindowScene
GLTWindow(frame = 主屏 bounds), windowLevel = UIWindowLevelStatusBar, 背景透明
rootViewController = 空白 UIViewController（view 透明）
moveWindowToScene:
_touchView = UIView（近乎全透明的 0.001 白）— 唯一接收手势的视图
    ├ UITapGestureRecognizer  → clockTapped
    └ UILongPressGestureRecognizer → clockLongPressed:   minimumPressDuration ≈ 0.45s
rootView.addSubview(_touchView)
NSDateFormatter ×2（时间 / 日期）
UIDevice.batteryMonitoringEnabled = YES
注册 6 个通知：键盘 frame 变化、键盘隐藏、电量变化、电池状态、GLTSourcesDidChange、GLTPrefsDidChange
[GLTEvents sharedEvents]  [GLTUnlocks sharedUnlocks]  [GLTMedia mediaDidChange]
NSTimer 1.0s → tick
prefsChanged
```

### 5.2 每秒 `tick`（0x5b44）

```
sampleNetwork          // getifaddrs 差分算实时网速
checkDevices           // BCBatteryDeviceController 差分 → 连接/断开药丸
if (wantsWeather)  GLTWeather refreshForcing:NO
if (enabled)       GLTClockItems refresh
update
```

### 5.3 三种"抢占式"状态

`volume` / `connection` / `notification` 会临时覆盖所选 pill，各自带一个到期时间 `NSDate`，并且会 `updateAfter:` 预约一次刷新来收尾：

| 状态 | 触发 | 时长来源 | 卡片 |
| --- | --- | --- | --- |
| volume | `_presentVolumeHUDWithVolume:` hook | `volumeDuration`（默认 1.5s） | 无 |
| connection | 配件连接/断开 | `notificationDuration`（默认 3s） | 有（设备列表） |
| notification | `postNotificationRequest:` hook | `notificationDuration` | 有（通知卡） |

### 5.4 `shownKind` —— 动画的唯一开关

```
volume          → "volume"
connection      → "connection %@ %d"
notification    → "notification %p"
其它            → "pill %ld"
```

`renderClocks` 里比较本次与上次的 `shownKind` 字符串，**只有变了才走动画**：

```
BOOL animated = (_shownKind != nil) && ![kind isEqualToString:_shownKind];
```

这是个很值得抄的做法：用一个可读字符串当"渲染版本号"，既有语义又便于调试。

---

## 6. 15 个 pill 全表

编号**就是**写入 `com.antonym.glint` 的 `pill` 值，也是 `Root.plist` 的 `validValues`，**不可重编号**。

| # | 名称 | 图标 | 内容来源 | 卡片 |
| --- | --- | --- | --- | --- |
| 0 | Time | `clock` | `_timeFormatter`（`jmm` / `jmmss`） | — |
| 1 | Date | `calendar` | `_dateFormatter`（`EEEdMMM`） | 事件卡 |
| 2 | Battery | `battery.100` | `GLTDevice` 列表首项 | — |
| 3 | Network Speed | `arrow.up.arrow.down` | `getifaddrs` 差分，`↓xK ↑yK` | — |
| 4 | Now Playing | `music.note` | `GLTMedia` | 媒体卡 |
| 5 | Calendar | `calendar` | 今日剩余事件数（徽标） | 事件卡 |
| 6 | Reminders | `checklist` | 未完成提醒数（徽标） | 提醒卡 |
| 7 | Weather | `cloud.sun` | Open-Meteo | 天气卡 |
| 8 | Alarm & Timer | `alarm` | `GLTClockItems` | 计时卡 |
| 9 | Next Event | `calendar.badge.clock` | 下一条非全天事件 | 事件卡 |
| 10 | Sunrise & Sunset | `sunrise` | `nextSunEvent:` | 天气卡 |
| 11 | Storage & Memory | `internaldrive` | `attributesOfFileSystemForPath:@"/private/var"` | 存储卡 |
| 12 | Countdown | `hourglass` | `countdownDate` 差值 | 倒计时卡 |
| 13 | Unlocks | `lock.open` | `notify` 锁屏状态计数 | 解锁卡 |
| 14 | Quick Message | `square.and.pencil` | 固定文案 "Message" | 发信卡 |

`+pillOrder`（0x1b81c）返回 `@[@0 … @14]`，即严格递增 —— 长按选择器与点击循环都用它。

### 6.1 内容解析跳转表（0x7638）

`contentForPill:` 用 `__const` 里一张 15 字节的偏移表做 `br` 分派（0x27f40）。反解结果与上表完全一致，说明编号语义在编译器层面也是集中的。

### 6.2 几个值得注意的实现细节

- **Battery**：`percent < 0` → `--%`；充电固定 `battery.100.bolt`；否则按 0/25/50/75/100 分档。
- **Network Speed**：占位符是 `↓0K ↑0K`（UTF-16 cfstring，字面量里带 `U+2193/U+2191`）；速率格式 `%.1fM` / `%.0fK`。
- **Next Event**：标题超过 18 字符截断补 `…`；时间描述分 `now` / `in %ld min` / `today` / `tomorrow`；图标颜色取 `event.calendar.CGColor`。
- **Countdown**：`today` / `1 day` / `%ld days` / `1 day ago` / `%ld days ago`，日期用 `startOfDayForDate:` 归一后再算天数差，避免跨时区误差。
- **Alarm & Timer**：计时器优先于闹钟；`%ld:%02ld:%02ld`（≥1h）或 `%ld:%02ld`；暂停态用 `pausedTimerRemaining`。

---

## 7. 卡片（platter）系统

`GLTPlatterView` 是一层毛玻璃圆角容器，`GLTPlatterContent` 是它的内容基类，子类只需描述"行"。

卡片工厂在二进制里是**匿名静态函数**（紧跟各自类的 `.cxx_destruct` 之后），由 `platterContent`（0x8fa8）的跳转表（0x27f4f，`pill − 1` 索引）分派：

| pill | 工厂地址 | 产出 |
| --- | --- | --- |
| 1 / 5 / 9 | 0xf7f4 | 事件列表（最多 5 条，色点 + 标题 + 时间） |
| 4 | 0xf180 | `GLTMediaPlatterView` |
| 6 | 0x105b0 | `GLTRemindersPlatterView`（圆形勾选按钮） |
| 7 / 10 | 0x10ad8 | 天气（大图标 + 温度 + H/L + 10 小时条 + Open-Meteo 署名） |
| 8 | 0x125e4 | `GLTClockPlatterView` |
| 11 | 0x12600 | 存储（free of total + 内存） |
| 12 | 0x12e7c | 倒计时（大数字 + 目标日期） |
| 13 | 0x13340 | 解锁（今日 / 昨日） |
| 14 | 0x14ef4 | `GLTComposePlatterView` |
| 2 / 3 | — | 无卡片（点按只触发循环） |
| volume | — | 无卡片 |

打开动画（0x9170）常量：`scale 0.92` + `translation −14`，`duration 0.42`，spring damping `0.78`，圆角 `22`，宽度 `min(屏宽−24, 380)`，顶部偏移 `safeAreaInsets.top + 6`。

---

## 8. 数据层

### 8.1 `GLTMedia`

`dlopen` MediaRemote，`dlsym` 三个函数：`MRMediaRemoteRegisterForNowPlayingNotifications` / `MRMediaRemoteGetNowPlayingInfo` / `MRMediaRemoteGetNowPlayingApplicationIsPlaying`。
原生键名全部硬编码（`kMRMediaRemoteNowPlayingInfoTitle` 等 7 个）。
`elapsed` 不是直接取快照值，而是 `ElapsedTime + (now − Timestamp) × PlaybackRate`，并按 duration 截断 —— 这是进度条能连续走的原因。
播放控制走 `SBMediaController` 的 `togglePlayPauseForEventSource:` / `changeTrack:eventSource:`。

### 8.2 `GLTEvents`

`EKEventStore`，只取 **今天 0 点 → +2 天**（`kGLTLookahead = 2×86400`），因此卡片文案才敢写 "today or tomorrow"。
事件排序 `compareStartDateWithEvent:`；提醒按 `dueDateComponents.date` 排序，无到期时间排最后。
监听 `EKEventStoreChangedNotification` 自动 refresh。

### 8.3 `GLTClockItems`

`dlopen` MobileTimer，`MTAlarmManager.alarmsSync` + `MTTimerManager.getCurrentTimerSync`。
这些 `*Sync` 接口会阻塞，所以放在串行队列 `com.antonym.glint.clock` 上跑。
筛掉未启用、`nextFireDate <= now` 的闹钟；结果与上次不同才发 `GLTSourcesDidChangeNotification`。

### 8.4 `GLTUnlocks`

`notify_register_dispatch("com.apple.springboard.lockstate")`，状态由 1 → 0 时 `today++`。
持久化到 `com.antonym.glint.unlocks`：`today` / `yesterday` / `day`（`yyyy-MM-dd`）。
`rollOverIfNeeded` 比对 `day` 字符串，跨天时 `yesterday = today; today = 0`。

### 8.5 `GLTWeather`

固定 URL（唯一一处网络请求）：

```
https://api.open-meteo.com/v1/forecast?latitude=%.2f&longitude=%.2f
&current=temperature_2m,apparent_temperature,weather_code,is_day
&hourly=temperature_2m,weather_code,is_day
&daily=temperature_2m_max,temperature_2m_min,precipitation_probability_max,sunrise,sunset
&timezone=auto&forecast_days=2
```

- 定位精度 `kCLLocationAccuracyKilometer`（约 1 km，与 plist 里的隐私说明一致）
- 配了 `weatherCity` 就跳过定位，直接 `geocodeAddressString:`
- 解析用 `en_US_POSIX` + `yyyy-MM-dd'T'HH:mm`，并按 `utc_offset_seconds` 设置时区
- WMO code → SF Symbol 的映射共 12 组（0/1/2/3/45-48/51-55/56-57/61-63/65/66-67/71-77/80-82/85-86/95-99）

### 8.6 设备电量

`NSClassFromString(@"BCBatteryDeviceController")` → `connectedDevices`，用 `@try` 包住（私有 API 变动时不能崩 SpringBoard）。
按 `identifier` 去重；多段设备（AirPods L/R/Case）把 `parts` 拼成 details 文本。
名称关键词 → 图标 11 组：`airpods max / airpods pro / airpods / beats / watch / pencil / mouse / trackpad / keyboard / iphone / ipad`。
手机自身从 `UIDevice.batteryLevel` 补，`internal` 标记，排序时置顶。

### 8.7 快捷信息

联系人搜索：纯电话号码字符 → 当号码；含 `@` → 当邮箱；否则按姓名查 `CNContactStore`。
发送走 IMCore：`IMDaemonController.connectToDaemon…` → `IMAccountController.activeIMessageAccount/activeSMSAccount` → `imHandleWithID:` → `IMChatRegistry.chatForIMHandle:` → `IMMessage.instantMessageWithText:flags:threadIdentifier:` → `sendMessage:`。
**整段带 `@try`**，失败则回退到 `MFMessageComposeViewController`，再退到 `sms:` URL。最近 5 位收件人存在 `com.antonym.glint.recents`。

---

## 9. 设置项（16 个键）

`com.antonym.glint`：

| 键 | 类型 | 默认 | 范围/说明 |
| --- | --- | --- | --- |
| `enabled` | BOOL | YES | 总开关 |
| `pill` | int | 0 | 0–14 |
| `tapToCycle` | BOOL | YES | 点按切下一个 pill |
| `showSeconds` | BOOL | NO | 切换 `jmm` / `jmmss` |
| `showMediaWhilePlaying` | BOOL | YES | 播放中强制 Now Playing |
| `backgroundStyle` | int | 0 | 0 Default / 1 Color |
| `backgroundColor` | string | `#000000` | `#RRGGBB` |
| `textColor` | string | `#FFFFFF` | `#RRGGBB` |
| `weatherCity` | string | "" | 空 = 用定位 |
| `countdownTitle` | string | "" | |
| `countdownDate` | date | nil | |
| `deviceConnections` | BOOL | YES | |
| `replaceBanners` | BOOL | YES | |
| `notificationDuration` | double | 3 | 1–8 |
| `replaceVolumeHUD` | BOOL | YES | |
| `volumeDuration` | double | 1.5 | 0.5–5 |

所有开关都通过 Darwin 通知 `com.antonym.glint/reload` 通知 tweak；`GLTPrefs` 收到后 `reload` 并广播 `GLTPrefsDidChangeNotification`，控制器据此 `prefsChanged`。

---

## 10. 私有 API 与适配风险

| 私有依赖 | 用法 | 风险 |
| --- | --- | --- |
| `STUIStatusBarStringView` / `STUIStatusBarTimeItem` | 主要 hook 目标 | 类名在 iOS 13/17 上带下划线前缀；重建版已做双名回退 |
| `SBVolumeControl._presentVolumeHUDWithVolume:` | 替换音量 HUD | iOS 16+ 音量 HUD 有重构，需按版本验证 |
| `SBNotificationBannerDestination.postNotificationRequest:` | 拦截横幅 | 通知中心架构改动时失效 |
| `SBMediaController` 三个 notify + 播放控制 | 媒体信息 | MediaRemote 私有，`dlsym` 失败要静默降级 |
| `SBApplicationController` / `UIImage._applicationIconImageForBundleIdentifier:format:scale:` | 通知卡图标 | 图标 API 私有 |
| `MTAlarmManager` / `MTTimerManager` | 闹钟/计时 | MobileTimer 私有 |
| `BCBatteryDeviceController` | 配件电量 | BatteryCenter 私有 |
| `IMDaemonController` / `IMChatRegistry` / `IMMessage` | 发 iMessage | IMCore 私有，已做三级回退 |
| `UIApplication.launchApplicationWithIdentifier:suspended:` | 打开通知来源 App | 私有 |
| `CLLocationManager.setAuthorizationStatusByType:forBundleIdentifier:` | 给 SpringBoard 授定位 | 私有，需 `respondsToSelector` 保护 |

维护建议：**所有私有入口都先 `respondsToSelector:` / `NSClassFromString` 判空**，失败就走公开回退路径。原作者的代码风格就是如此（每个私有调用外面都套 `_objc_opt_respondsToSelector` 和 `@try`）。

---

## 11. 重建工程

```
reconstructed/
├── Makefile                 # rootless (var/jb) 构建，ARCHS = arm64 arm64e
├── control                  # 与原始包一致
├── Glint.plist              # Filter: com.apple.springboard（原始文件）
├── layout/…/GlintPrefs.plist
├── Glint.h                  # umbrella
├── GlintPrivate.h           # 通知名、pill 枚举、卡片工厂、私有 API 声明
├── Tweak.xm                 # 20 条 hook（4 条 Logos + 16 条手写 MSHookMessageEx）
├── Headers/                 # 23 个类头文件，ivar 偏移 + 291 个方法签名
├── Sources/
│   ├── GLTPrefs.m           GLTPillContent.m   GLTClock.m
│   ├── GLTController.m      GLTWindow.m        GLTUtilities.m
│   ├── GLTPlatterView.m     GLTInteractivePlatters.m  GLTInfoPlatters.m
│   ├── GLTMedia.m           GLTEvents.m        GLTClockItems.m
│   ├── GLTWeather.m         GLTModels.m
└── prefs/
    ├── Makefile
    ├── Resources/           # Root.plist / Info.plist / 图标（原始文件）
    ├── GLTRootListController.m
    └── GLTCells.m           # 滑杆 / 取色 / 日期三种自定义 cell
```

### 11.1 头文件的可信度

`Headers/*.h` 由 ObjC 元数据**直接生成**，不是猜的：

- 类名、父类、实例大小 —— `class_ro_t` / `class_t`
- ivar 名字、类型编码、**精确偏移** —— `ivar_list_t`（注释里带 `0xNN`）
- 方法签名 —— relative method list 的 `types` 字段（如 `v20@0:8B16`）

因此头文件里的 ABI 与 1.6.3 完全一致，可以放心 `dlopen` 别人的 dylib 对着这套头文件用，或者用这套头文件去 hook 第三方扩展。

### 11.2 编译

```bash
export THEOS=/opt/theos
cd reconstructed
make package THEOS_PACKAGE_SCHEME=rootless
# 产物：packages/com.antonym.glint_1.6.3_iphoneos-arm64.deb
```

依赖：Theos + iOS SDK 14+ + `ldid`。rootless 目标会自动把安装路径改写到 `/var/jb`。

### 11.3 已验证 vs 推断

| 级别 | 内容 |
| --- | --- |
| **反汇编逐条验证** | 20 条 hook 及顺序；`GLTClock` 全部类方法的控制流与常量；`renderClocks` / `apply:` / `fadeIn` 的参数；`contentForPill:` 跳转表；`platterContent` 跳转表；`GLTPrefs reload` 全部默认值与区间；`pillOrder` / `nameForPill:` / `symbolForPill:` 表；Open-Meteo URL；WMO 映射；15 个 pill 的编号 |
| **指纹级验证**（selector + 字符串 + 数值） | 各数据源的字段与调用顺序；设备关键词表；联系人/IMCore 调用链；卡片内的字号与间距 |
| **推断**（行为等价，数值可能有偏差） | 徽标与进度条的绘制几何；`heightForWidth:` 的 padding 拆分；选择器网格列数与动效曲线；`visibleDateOfLabel:` 的返回值语义（原实现也只返回 `[NSDate date]` 当哨兵）；`IMChatRegistry` 的具体 selector |

推断部分在源码里都有 `// ≈` 或注释标注，方便逐个用真机对照修正。

---

## 12. 二次开发入口速查

| 想做的事 | 改哪里 |
| --- | --- |
| 加一个新 pill | `GlintPrivate.h` 的 `GLTPill` 尾部追加（**只能往后加**）+ `GLTPrefs` 的 `nameForPill:` / `symbolForPill:` / `pillOrder` + `contentForPill:` + `Root.plist` 的 `validTitles/validValues` |
| 改药丸外观 | `+[GLTClock padding]` / `outsetForLabel:` / `renderClocks` 的默认背景色 |
| 改动画手感 | `+[GLTClock fadeInLabel:]` 的 damping/stiffness、`popLabel:` 的 spring、`openPlatter:` 的 0.42/0.78 |
| 换天气源 | `GLTWeather.m` 的 `kGLTForecastURL` + `applyForecast:place:` 的解析 |
| 加一个卡片 | 在 `GLTInfoPlatters.m` 里写工厂，`GLTPrivate.h` 声明，`platterContent` 里加 case |
| 改设置项 | `reconstructed/prefs/Resources/Root.plist` + `GLTPrefs reload` 同步加键 |

---

## 13. 分析产物索引

| 文件 | 内容 |
| --- | --- |
| `analysis/objc_full.txt` | 23 个类 / 291 个方法 / 全部 ivar 偏移与类型编码 |
| `analysis/fingerprint.txt` | 436 个函数的语义指纹（selector + 字符串 + 数值常量） |
| `analysis/sels.txt` | 620 个 selector |
| `analysis/cf.txt` | 286 条 `__cfstring` |
| `analysis/ctor.txt` | 构造函数（20 条 hook 注册）完整反汇编 |
| `analysis/apply.txt` | `+[GLTClock apply:toLabel:…]` 完整反汇编 |
| `analysis/render.txt` | `-[GLTController renderClocks]` 完整反汇编 |
| `tools/` | `mo.py`（Mach-O）/`fx.py`（chained fixups）/`oc.py`（ObjC 元数据）/`dx.py`（带注释反汇编）/`fp.py`（指纹）/`gen_headers.py`（头文件生成） |

工具链可复用于同族插件：`python tools/dx.py <dylib> dump 0xADDR 200` 即可拿到带 `msgSend[sel]` / `SEL()` / `@"str"` / `CLS()` 注释的反汇编。
