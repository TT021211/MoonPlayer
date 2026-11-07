/** 备用 OpenList 源（可添加无限条，路径用「源名@路径」指定） */
export interface OpenListExtraSource {
  name: string; // 源名字，唯一、非空、不含 @
  url: string; // OpenList 服务器地址
  username: string;
  password: string;
}

export interface AdminConfig {
  ConfigSubscribtion: {
    URL: string;
    AutoUpdate: boolean;
    LastCheck: string;
    // 拉取配置代理：拉取配置订阅时使用的 HTTP 代理，留空则回退到环境变量
    // CONFIG_SUBSCRIPTION_PROXY
    Proxy?: string;
  };
  ConfigFile: string;
  SiteConfig: {
    SiteName: string;
    Announcement: string;
    // 公告显示模式：once=单次显示（每个用户每条公告仅显示一次，换公告则重新显示）；every=每次显示（每次打开首页都显示）
    AnnouncementDisplayMode?: 'once' | 'every';
    SearchDownstreamMaxPage: number;
    SiteInterfaceCacheTime: number;
    // 频道开关：被禁用的导航频道 key（见 lib/channels NAV_CHANNELS），默认全开
    DisabledChannels?: string[];
    DoubanProxyType: string;
    DoubanProxy: string;
    DoubanImageProxyType: string;
    DoubanImageProxy: string;
    DisableYellowFilter: boolean;
    FluidSearch: boolean;
    // TMDB配置
    TMDBApiKey?: string;
    TMDBProxy?: string;
    TMDBReverseProxy?: string;
    // TMDB 图片默认地址：用户未在本地数据源设置中配置时，图片默认使用该地址
    TMDBImageBaseUrl?: string;
    // 动漫/Bangumi配置
    BangumiDataSource?:
      | 'direct'
      | 'server-proxy'
      | 'custom-baseurl'
      | 'sakura';
    BangumiApiBaseUrl?: string;
    BangumiImageBaseUrl?: string;
    BangumiProxy?: string;
    LiveChartProxy?: string;
    BannerDataSource?: string; // 轮播图数据源：TMDB、TX 或 Douban
    RecommendationDataSource?: string; // 更多推荐数据源：Douban、TMDB、Mixed
    // 本地设置云同步模式：off=关闭，manual=手动（面板右上角备份/恢复按钮），auto=自动（进入网站静默拉取、面板打开静默同步）
    LocalSettingsSyncMode?: 'off' | 'manual' | 'auto';
    // Pansou配置
    PansouApiUrl?: string;
    PansouUsername?: string;
    PansouPassword?: string;
    PansouKeywordBlocklist?: string;
    // 磁链配置
    MagnetProxy?: string;
    MagnetMikanReverseProxy?: string;
    MagnetDmhyReverseProxy?: string;
    MagnetAcgripReverseProxy?: string;
    MagnetNyaaReverseProxy?: string;
    // 评论功能开关
    EnableComments: boolean;
    // 自定义去广告代码
    CustomAdFilterCode?: string;
    CustomAdFilterVersion?: number; // 代码版本号（时间戳）
    // 注册相关配置
    EnableRegistration?: boolean; // 开启注册
    RequireRegistrationInviteCode?: boolean; // 注册时要求邀请码
    RegistrationInviteCode?: string; // 通用注册邀请码
    RegistrationRequireTurnstile?: boolean; // 注册启用Cloudflare Turnstile
    LoginRequireTurnstile?: boolean; // 登录启用Cloudflare Turnstile
    TurnstileSiteKey?: string; // Cloudflare Turnstile Site Key
    TurnstileSecretKey?: string; // Cloudflare Turnstile Secret Key
    DefaultUserTags?: string[]; // 新注册用户的默认用户组
    // 求片功能配置
    EnableMovieRequest?: boolean; // 启用求片功能
    MovieRequestCooldown?: number; // 求片冷却时间（秒），默认3600
    // OIDC配置
    EnableOIDCLogin?: boolean; // 启用OIDC登录
    EnableOIDCRegistration?: boolean; // 启用OIDC注册
    OIDCIssuer?: string; // OIDC Issuer URL (用于自动发现)
    OIDCAuthorizationEndpoint?: string; // 授权端点
    OIDCTokenEndpoint?: string; // Token端点
    OIDCUserInfoEndpoint?: string; // 用户信息端点
    OIDCClientId?: string; // OIDC Client ID
    OIDCClientSecret?: string; // OIDC Client Secret
    OIDCButtonText?: string; // OIDC登录按钮文字
    OIDCMinTrustLevel?: number; // 最低信任等级（仅LinuxDo网站有效，为0时不判断）
    // 流量统计配置
    AnalyticsEnabled?: boolean; // 是否启用流量统计
    AnalyticsProvider?: 'umami' | 'google' | 'clarity' | 'custom'; // 统计服务提供商
    AnalyticsScriptUrl?: string; // 脚本URL（Umami: umami.js地址; GA: gtag URL; 自定义: 脚本src）
    AnalyticsWebsiteId?: string; // 网站ID（Umami: website_id; GA: Measurement ID如G-XXXX; 自定义: 留空）
    AnalyticsCustomScript?: string; // 自定义统计代码（仅custom模式使用，完整的HTML脚本内容）
  };
  UserConfig: {
    Users: {
      username: string;
      role: 'user' | 'admin' | 'owner';
      banned?: boolean;
      enabledApis?: string[]; // 优先级高于tags限制
      tags?: string[]; // 多 tags 取并集限制
    }[];
    Tags?: {
      name: string;
      enabledApis: string[];
      permissions?: string[];
    }[];
  };
  SpecialSourceApis?: string[]; // 特殊源 key 列表，默认对普通入口隐藏
  ClientAdSourceApis?: string[]; // 客户端去广告源 key 列表：MoonTVPlus APP / OrionTV 请求 source-detail 时 m3u8 套 proxy-m3u8
  SourceConfig: {
    key: string;
    name: string;
    api: string;
    detail?: string;
    from: 'config' | 'custom';
    disabled?: boolean;
    proxyMode?: boolean; // 代理模式开关：启用后由服务器代理m3u8和ts分片
    weight?: number; // 权重：用于排序和优选评分，默认0，范围0-100
  }[];
  CustomCategories: {
    name?: string;
    type: 'movie' | 'tv';
    query: string;
    from: 'config' | 'custom';
    disabled?: boolean;
  }[];
  LiveConfig?: {
    key: string;
    name: string;
    url: string; // m3u 地址
    ua?: string;
    epg?: string; // 节目单
    from: 'config' | 'custom';
    channelNumber?: number;
    disabled?: boolean;
    proxyMode?: 'full' | 'm3u8-only' | 'direct';
  }[];
  ThemeConfig?: {
    enableBuiltInTheme: boolean; // 是否启用内置主题
    builtInTheme: string; // 内置主题名称
    customCSS: string; // 自定义CSS
    enableCache: boolean; // 是否启用浏览器缓存
    cacheMinutes: number; // 缓存时间（分钟）
    cacheVersion: number; // CSS版本号（用于缓存控制）
    loginBackgroundImage?: string; // 登录界面背景图
    registerBackgroundImage?: string; // 注册界面背景图
    homeBackgroundImage?: string; // 首页背景图
    // 进度条图标配置
    progressThumbType?: 'default' | 'preset' | 'custom'; // 图标类型
    progressThumbPresetId?: string; // 预制图标ID
    progressThumbCustomUrl?: string; // 自定义图标URL
    // 初始化加载样式：播放页/直播页首屏加载动画的款式
    loadingStyle?: 'classic' | 'grid' | 'talisman';
    // 评分星标样式：视频卡片右上角评分徽章的款式
    rateBadgeStyle?: 'default' | 'flag' | 'medal';
  };
  OpenListConfig?: {
    Enabled: boolean; // 是否启用私人影库功能
    URL: string; // 主 OpenList 服务器地址
    Username: string; // 账号（用于登录获取Token）
    Password: string; // 密码（用于登录获取Token）
    RootPath?: string; // 旧字段：根目录路径（向后兼容，迁移后删除）
    RootPaths?: string[]; // 根目录路径列表，支持「源名@路径」
    ExtraSources?: OpenListExtraSource[]; // 备用 OpenList 源列表
    OfflineDownloadPath: string; // 离线下载目录，支持「源名@路径」，默认 "/"
    LastRefreshTime?: number; // 上次刷新时间戳
    ResourceCount?: number; // 资源数量
    ScanInterval?: number; // 定时扫描间隔（分钟），0表示关闭，最低60分钟
    ScanMode?: 'torrent' | 'name' | 'hybrid'; // 扫描模式：torrent=种子库匹配，name=名字匹配，hybrid=混合模式（默认）
    DisableVideoPreview?: boolean; // 禁用预览视频，直接返回直连链接
    /**
     * 路径元信息（最长前缀匹配 folder 路径）
     * key: 规范化路径前缀，如 /videos 可匹配 /videos/某影片；
     *      也可写「源名@/videos」只对指定源生效（无前缀则对所有源生效）
     */
    PathMeta?: {
      [path: string]: {
        category: string; // 分类名
        refresh14m: boolean; // 该路径播放时是否启用 14 分钟 URL 续期
        proxyPlay: boolean; // 该路径播放链接是否使用服务器代理播放
        proxyCacheMinutes: number; // 代理播放时链接最终重定向的缓存时长（分钟），默认 60
      };
    };
  };
  NetDiskConfig?: {
    Quark?: {
      Enabled: boolean;
      Cookie: string;
      SavePath: string;
      PlayMode?: 'direct_first' | 'transcode_first';
      MultiThreadPlayback?: boolean;
    };
    Mobile?: {
      Enabled: boolean;
      Authorization: string;
    };
    Baidu?: {
      Enabled: boolean;
      Cookie: string;
    };
    Tianyi?: {
      Enabled: boolean;
      Account: string;
      Password: string;
    };
    Pan123?: {
      Enabled: boolean;
      Account: string;
      Password: string;
    };
    UC?: {
      Enabled: boolean;
      Cookie: string;
      Token?: string;
      SavePath: string;
    };
    Pan115?: {
      Enabled: boolean;
      Cookie: string;
    };
  };
  MusicConfig?: {
    Enabled?: boolean;
    BaseUrl?: string;
    Token?: string;
    ProxyEnabled?: boolean;
  };
  EmbyConfig?: {
    // 新格式：多源配置（推荐）
    Sources?: Array<{
      key: string; // 唯一标识，如 'emby1', 'emby2'
      name: string; // 显示名称，如 '家庭Emby', '公司Emby'
      enabled: boolean; // 是否启用
      ServerURL: string; // Emby服务器地址
      ApiKey?: string; // API Key（推荐方式）
      Username?: string; // 用户名（或使用API Key）
      Password?: string; // 密码
      UserId?: string; // 用户ID（登录后获取）
      AuthToken?: string; // 认证令牌（用户名密码登录后获取）
      Libraries?: string[]; // 要显示的媒体库ID（可选，默认全部）
      LastSyncTime?: number; // 最后同步时间戳
      ItemCount?: number; // 媒体项数量
      isDefault?: boolean; // 是否为默认源（用于向后兼容）
      // 高级流媒体选项
      removeEmbyPrefix?: boolean; // 播放链接移除/emby前缀
      appendMediaSourceId?: boolean; // 拼接MediaSourceId参数
      transcodeMp4?: boolean; // 转码mp4
      proxyPlay?: boolean; // 视频播放代理开关
      customUserAgent?: string; // 自定义User-Agent
      embyAuthorizationHeader?: string; // 自定义 X-Emby-Authorization 请求头
    }>;
    // 旧格式：单源配置（向后兼容）
    Enabled?: boolean;
    ServerURL?: string;
    ApiKey?: string;
    Username?: string;
    Password?: string;
    UserId?: string;
    AuthToken?: string;
    Libraries?: string[];
    embyAuthorizationHeader?: string;
    LastSyncTime?: number;
    ItemCount?: number;
  };
  XiaoyaConfig?: {
    Enabled: boolean; // 是否启用
    ServerURL: string; // Alist 服务器地址
    Token?: string; // Token 认证（推荐）
    Username?: string; // 用户名认证（备选）
    Password?: string; // 密码认证（备选）
    DisableVideoPreview?: boolean; // 禁用预览视频，直接返回直连链接
  };
}

export interface AdminConfigResult {
  Role: 'owner' | 'admin';
  Config: AdminConfig;
}
