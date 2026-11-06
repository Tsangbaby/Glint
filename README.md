# Glint 1.6.3 源码重建包

从 `com.antonym.glint_1.6.3_iphoneos-arm64.deb` 逆向还原的完整工程。

## 包内结构

```
Glint-1.6.3-source/
├── Glint_逆向分析报告.md      ← 先看这个
├── reconstructed/              ← 可编译的 Theos 工程
│   ├── Makefile / control / Glint.plist / layout/
│   ├── Glint.h / GlintPrivate.h / Tweak.xm
│   ├── Headers/               23 个类头文件（精确 ivar 偏移 + 291 个方法签名）
│   ├── Sources/               14 个实现文件
│   └── prefs/                 设置面板 bundle（Root.plist 等为原始文件）
├── analysis/                  逆向过程中的数据产物
└── tools/                     可复用的分析脚本
```

## 编译

```bash
export THEOS=/opt/theos
cd reconstructed
make package THEOS_PACKAGE_SCHEME=rootless
```

产物：`packages/com.antonym.glint_1.6.3_iphoneos-arm64.deb`
需要 Theos + iOS SDK 14+ + ldid。

## 说明

- `Headers/` 是从 ObjC 元数据**直接生成**的，不是推测，因此 ABI 与 1.6.3 一致。
- `Sources/` 中反汇编可逐条验证的部分占多数；推断部分（徽标/进度条几何、卡片 padding
  拆分、选择器网格动效、`visibleDateOfLabel:` 返回值语义）在代码里有注释标注。
  详细分级见报告第 11.3 节。
- 本工程在 Windows 上完成，尚未实际编译（无 Theos/iOS SDK）。若 `make` 报错，
  多数是 SDK 版本差异（如 `UIScene`、`EKAuthorizationStatusFullAccess`、
  `kCLAuthorizationStatusAuthorizedAlways` 的可用性标注）。

## analysis/ 内容

| 文件 | 内容 |
| --- | --- |
| `objc_full.txt` | 23 个类 / 291 个方法 / 全部 ivar 偏移与类型编码 |
| `fingerprint.txt` | 436 个函数的语义指纹（selector + 字符串 + 数值常量） |
| `ctor.txt` | 构造函数反汇编（20 条 hook 注册） |
| `apply.txt` | `+[GLTClock apply:toLabel:…]` 完整反汇编 |
| `render.txt` | `-[GLTController renderClocks]` 完整反汇编 |
| `sels.txt` / `cf.txt` | 620 个 selector / 286 条 `__cfstring` |

## tools/ 用法

```bash
python tools/dx.py <dylib> dump 0xA0D0 200   # 带注释反汇编（msgSend[sel] / SEL() / @"str" / CLS()）
python tools/dx.py <dylib> sels              # 全部 selector
python tools/oc.py <dylib>                   # 类/方法/ivar 全量还原
python tools/gen_headers.py <objc_dump.txt> <out_dir>
```
