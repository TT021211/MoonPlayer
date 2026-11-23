# MoonPlayer iOS

MoonPlayer（MoonTV / MoonTVPlus 自建影库）的 iOS 原生客户端，SwiftUI 编写，无第三方依赖。

## 功能（核心版）

- 登录自建服务器（`/api/login`，Bearer Token；地址可在登录页修改，默认 `https://tv.acxou.hair`）
- 首页与网页端一致：
  - 豆瓣热门轮播（`/api/tmdb/trending`）
  - 热门电影 / 热门剧集 / 热门综艺 / 即将上映横向片单
  - 点击豆瓣/TMDB 卡片 → 按标题全源找片 → 进入详情
- 频道与网页端左侧栏一致（12 个入口，不再展示原始采集源列表）：
  - 电影 / 剧集 / 动漫 / 综艺（豆瓣片单，支持分类筛选与无限滚动）
  - 深夜剧场 / 心动剧场 / HoHo剧场 / KinoStream / BJ剧场 / 奈飞工厂 / Pornhub / xHamster
- 频道内搜索、全局聚合搜索（`/api/search`）
- 详情页：海报、简介、选集、收藏
- 原生 HLS 播放（AVPlayer）：
  - 单击显隐控制栏、双击左右快退/快进 10 秒、中间双击暂停
  - 横向拖动进度、左半屏上下调亮度、右半屏上下调音量
  - 选集、倍速、横竖屏切换、自动连播
  - **边看边缓存（默认开）**：播放列表和分片走服务端代理，VPS 边下边存
    （列表 1h / 分片 72h / 总量 10G），播放器预缓冲 20 秒
  - 代理和直连失败会互相切换一次；设置里可手动关闭缓存改直连
  - 音频走 `.playback`，静音键打开时也有声音；播放时保持屏幕常亮
- 收藏 / 播放历史（云端同步，与 Web 端共用 `/api/favorites`、`/api/playrecords`）
- 深色主题、原生 TabBar / NavigationStack / 大标题 / 下拉刷新 / 侧滑返回 / 长按菜单 / 震动反馈
- 图片加载带 Bearer Token（`/api/image-proxy` 在鉴权中间件后面）＋ 内存/磁盘缓存
- Access Token 4 小时自动用 refreshToken 续期，401 对调用方透明

## 目录

```
apps/ios/
├── project.yml                 # XcodeGen 工程定义（不提交 .xcodeproj）
├── MoonPlayer/
│   ├── App/                    # 入口、AppState、API 客户端、方向锁、Keychain
│   ├── Models/                 # Codable 数据模型
│   ├── Services/               # APIClient / Keychain
│   ├── Design/                 # 主题与通用组件
│   ├── Views/                  # 首页 / 频道 / 搜索 / 详情 / 我的 / 收藏 / 历史 / 设置
│   ├── Player/                 # AVPlayer 封装、手势播放器
│   └── Assets.xcassets/
└── README.md
```

## 构建

### GitHub Actions（推荐，本仓库已内置）

推送到 `main` 或 `ios-app` 分支且改动 `apps/ios/**` 时自动构建：

- workflow：`.github/workflows/ios-unsigned.yml`
- runner：`macos-14`
- 产物：
  - Actions Artifact：`MoonPlayer-unsigned-ipa`
  - Release：`https://github.com/TT021211/MoonPlayer/releases/download/ios-latest/MoonPlayer-unsigned.ipa`

构建命令等价于：

```bash
xcodegen generate
xcodebuild -project MoonPlayer.xcodeproj -scheme MoonPlayer \
  -configuration Release -sdk iphoneos \
  -destination 'generic/platform=iOS' \
  -archivePath build/MoonPlayer.xcarchive \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO \
  CODE_SIGN_IDENTITY="" DEVELOPMENT_TEAM="" archive
```

### 本地 Mac

```bash
brew install xcodegen
cd apps/ios
xcodegen generate
open MoonPlayer.xcodeproj
```

真机运行需要自行配置签名；未签名 IPA 无法直接安装到普通 iOS 设备。

## 安装未签名 IPA

任选其一：

- **TrollStore**（支持的系统）：直接分享/打开 IPA 安装
- **AltStore / SideStore**：导入 IPA 后用 Apple ID 自签
- **Sideloadly**：连接设备导入 IPA 自签
- **企业签名 / 个人证书**：用 `codesign` 重签后安装

## 服务端要求

- 已部署 MoonPlayer/MoonTV Web 端，且手机能访问其地址
- 已配置至少一个采集源（`/api/source-search/sources` 有返回）
- 登录账号密码与 Web 端一致
- 频道内容来自 `maccms-hub` 网关；`aqdlt` 源需要在后台开启 `proxyMode`
- pornhub 等短签名源建议把全站 `cache_time` 调到 3600 秒以内，否则选集地址会过期

## 已知限制

- 仅收录 `.m3u8` 选集（与 Web 端一致），mp4 直链会被服务端丢弃
- 不支持离线下载、弹幕、豆瓣榜单、TVBox、私人影库（后续可加）
- 未签名包不能使用推送、App Groups 等需要 entitlement 的能力
