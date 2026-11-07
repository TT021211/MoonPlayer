// 内置主题定义
export const builtInThemes = {
  default: {
    name: '默认主题',
    description: '使用系统默认样式',
    color: '#3b82f6',
    css: '',
  },
  dark_blue: {
    name: '深蓝夜空',
    description: '深邃的蓝色科技风格',
    color: '#3b82f6',
    css: `
/* 浅色模式 */
:root:not(.dark) {
  --theme-primary: #2563eb;
  --theme-primary-hover: #1d4ed8;
  --theme-bg: #dbeafe;
  --theme-bg-secondary: #eff6ff;
  --theme-text: #1e3a8a;
  --theme-text-secondary: #3b82f6;
  --theme-border: #93c5fd;
}

:root:not(.dark) body {
  background: linear-gradient(135deg, #eff6ff 0%, #dbeafe 100%) !important;
  color: var(--theme-text) !important;
}

/* 深色模式 */
.dark {
  --theme-primary: #3b82f6;
  --theme-primary-hover: #2563eb;
  --theme-bg: #0f172a;
  --theme-bg-secondary: #1e293b;
  --theme-text: #e2e8f0;
  --theme-text-secondary: #94a3b8;
  --theme-border: #334155;
}

.dark body {
  background: linear-gradient(135deg, #0f172a 0%, #1e293b 100%) !important;
  color: var(--theme-text) !important;
}

/* 通用样式 */
[class*="bg-white"]:not(.dark *), [class*="bg-gray-50"]:not(.dark *) {
  background: var(--theme-bg-secondary) !important;
  color: var(--theme-text) !important;
}

.dark [class*="bg-gray-800"], .dark [class*="bg-gray-900"] {
  background: var(--theme-bg-secondary) !important;
  color: var(--theme-text) !important;
}

[class*="border-gray"] {
  border-color: var(--theme-border) !important;
}

[class*="text-gray-600"], [class*="text-gray-700"], [class*="text-gray-800"] {
  color: var(--theme-text-secondary) !important;
}

.dark [class*="text-gray-"] {
  color: var(--theme-text-secondary) !important;
}
`,
  },
  purple_dream: {
    name: '紫色梦境',
    description: '神秘的紫色渐变风格',
    color: '#a78bfa',
    css: `
/* 浅色模式 */
:root:not(.dark) {
  --theme-primary: #7c3aed;
  --theme-primary-hover: #6d28d9;
  --theme-bg: #f3e8ff;
  --theme-bg-secondary: #faf5ff;
  --theme-text: #581c87;
  --theme-text-secondary: #7c3aed;
  --theme-border: #d8b4fe;
}

:root:not(.dark) body {
  background: linear-gradient(135deg, #faf5ff 0%, #f3e8ff 100%) !important;
  color: var(--theme-text) !important;
}

/* 深色模式 */
.dark {
  --theme-primary: #a78bfa;
  --theme-primary-hover: #8b5cf6;
  --theme-bg: #1a0b2e;
  --theme-bg-secondary: #2d1b4e;
  --theme-text: #f3e8ff;
  --theme-text-secondary: #c4b5fd;
  --theme-border: #4c1d95;
}

.dark body {
  background: linear-gradient(135deg, #1a0b2e 0%, #2d1b4e 50%, #4c1d95 100%) !important;
  color: var(--theme-text) !important;
}

/* 通用样式 */
[class*="bg-white"]:not(.dark *), [class*="bg-gray-50"]:not(.dark *) {
  background: var(--theme-bg-secondary) !important;
  color: var(--theme-text) !important;
}

.dark [class*="bg-gray-800"], .dark [class*="bg-gray-900"] {
  background: rgba(45, 27, 78, 0.8) !important;
  color: var(--theme-text) !important;
  backdrop-filter: blur(10px);
}

[class*="border-gray"] {
  border-color: var(--theme-border) !important;
}

[class*="text-gray-600"], [class*="text-gray-700"], [class*="text-gray-800"] {
  color: var(--theme-text-secondary) !important;
}

.dark [class*="text-gray-"] {
  color: var(--theme-text-secondary) !important;
}
`,
  },
  green_forest: {
    name: '翠绿森林',
    description: '清新的绿色自然风格',
    color: '#10b981',
    css: `
/* 浅色模式 */
:root:not(.dark) {
  --theme-primary: #059669;
  --theme-primary-hover: #047857;
  --theme-bg: #d1fae5;
  --theme-bg-secondary: #ecfdf5;
  --theme-text: #064e3b;
  --theme-text-secondary: #059669;
  --theme-border: #6ee7b7;
}

:root:not(.dark) body {
  background: linear-gradient(135deg, #ecfdf5 0%, #d1fae5 100%) !important;
  color: var(--theme-text) !important;
}

/* 深色模式 */
.dark {
  --theme-primary: #10b981;
  --theme-primary-hover: #059669;
  --theme-bg: #064e3b;
  --theme-bg-secondary: #065f46;
  --theme-text: #d1fae5;
  --theme-text-secondary: #6ee7b7;
  --theme-border: #047857;
}

.dark body {
  background: linear-gradient(135deg, #064e3b 0%, #065f46 100%) !important;
  color: var(--theme-text) !important;
}

/* 通用样式 */
[class*="bg-white"]:not(.dark *), [class*="bg-gray-50"]:not(.dark *) {
  background: var(--theme-bg-secondary) !important;
  color: var(--theme-text) !important;
}

.dark [class*="bg-gray-800"], .dark [class*="bg-gray-900"] {
  background: rgba(6, 95, 70, 0.9) !important;
  color: var(--theme-text) !important;
}

[class*="border-gray"] {
  border-color: var(--theme-border) !important;
}

[class*="text-gray-600"], [class*="text-gray-700"], [class*="text-gray-800"] {
  color: var(--theme-text-secondary) !important;
}

.dark [class*="text-gray-"] {
  color: var(--theme-text-secondary) !important;
}
`,
  },
  orange_sunset: {
    name: '橙色日落',
    description: '温暖的橙色日落风格',
    color: '#f97316',
    css: `
/* 浅色模式 */
:root:not(.dark) {
  --theme-primary: #ea580c;
  --theme-primary-hover: #c2410c;
  --theme-bg: #fed7aa;
  --theme-bg-secondary: #ffedd5;
  --theme-text: #7c2d12;
  --theme-text-secondary: #ea580c;
  --theme-border: #fdba74;
}

:root:not(.dark) body {
  background: linear-gradient(135deg, #ffedd5 0%, #fed7aa 100%) !important;
  color: var(--theme-text) !important;
}

/* 深色模式 */
.dark {
  --theme-primary: #f97316;
  --theme-primary-hover: #ea580c;
  --theme-bg: #431407;
  --theme-bg-secondary: #7c2d12;
  --theme-text: #fed7aa;
  --theme-text-secondary: #fdba74;
  --theme-border: #9a3412;
}

.dark body {
  background: linear-gradient(135deg, #431407 0%, #7c2d12 50%, #9a3412 100%) !important;
  color: var(--theme-text) !important;
}

/* 通用样式 */
[class*="bg-white"]:not(.dark *), [class*="bg-gray-50"]:not(.dark *) {
  background: var(--theme-bg-secondary) !important;
  color: var(--theme-text) !important;
}

.dark [class*="bg-gray-800"], .dark [class*="bg-gray-900"] {
  background: rgba(124, 45, 18, 0.85) !important;
  color: var(--theme-text) !important;
}

[class*="border-gray"] {
  border-color: var(--theme-border) !important;
}

[class*="text-gray-600"], [class*="text-gray-700"], [class*="text-gray-800"] {
  color: var(--theme-text-secondary) !important;
}

.dark [class*="text-gray-"] {
  color: var(--theme-text-secondary) !important;
}
`,
  },
  pink_candy: {
    name: '粉色糖果',
    description: '甜美的粉色糖果风格',
    color: '#ec4899',
    css: `
/* 浅色模式 */
:root:not(.dark) {
  --theme-primary: #db2777;
  --theme-primary-hover: #be185d;
  --theme-bg: #fce7f3;
  --theme-bg-secondary: #fdf2f8;
  --theme-text: #831843;
  --theme-text-secondary: #db2777;
  --theme-border: #fbcfe8;
}

:root:not(.dark) body {
  background: linear-gradient(135deg, #fdf2f8 0%, #fce7f3 100%) !important;
  color: var(--theme-text) !important;
}

/* 深色模式 */
.dark {
  --theme-primary: #ec4899;
  --theme-primary-hover: #db2777;
  --theme-bg: #500724;
  --theme-bg-secondary: #831843;
  --theme-text: #fce7f3;
  --theme-text-secondary: #fbcfe8;
  --theme-border: #9f1239;
}

.dark body {
  background: linear-gradient(135deg, #500724 0%, #831843 50%, #9f1239 100%) !important;
  color: var(--theme-text) !important;
}

/* 通用样式 */
[class*="bg-white"]:not(.dark *), [class*="bg-gray-50"]:not(.dark *) {
  background: var(--theme-bg-secondary) !important;
  color: var(--theme-text) !important;
}

.dark [class*="bg-gray-800"], .dark [class*="bg-gray-900"] {
  background: rgba(131, 24, 67, 0.85) !important;
  color: var(--theme-text) !important;
}

[class*="border-gray"] {
  border-color: var(--theme-border) !important;
}

[class*="text-gray-600"], [class*="text-gray-700"], [class*="text-gray-800"] {
  color: var(--theme-text-secondary) !important;
}

.dark [class*="text-gray-"] {
  color: var(--theme-text-secondary) !important;
}
`,
  },
  cyan_ocean: {
    name: '青色海洋',
    description: '清爽的青色海洋风格',
    color: '#06b6d4',
    css: `
/* 浅色模式 */
:root:not(.dark) {
  --theme-primary: #0891b2;
  --theme-primary-hover: #0e7490;
  --theme-bg: #cffafe;
  --theme-bg-secondary: #ecfeff;
  --theme-text: #164e63;
  --theme-text-secondary: #0891b2;
  --theme-border: #67e8f9;
}

:root:not(.dark) body {
  background: linear-gradient(135deg, #ecfeff 0%, #cffafe 100%) !important;
  color: var(--theme-text) !important;
}

/* 深色模式 */
.dark {
  --theme-primary: #06b6d4;
  --theme-primary-hover: #0891b2;
  --theme-bg: #083344;
  --theme-bg-secondary: #164e63;
  --theme-text: #cffafe;
  --theme-text-secondary: #67e8f9;
  --theme-border: #155e75;
}

.dark body {
  background: linear-gradient(135deg, #083344 0%, #164e63 100%) !important;
  color: var(--theme-text) !important;
}

/* 通用样式 */
[class*="bg-white"]:not(.dark *), [class*="bg-gray-50"]:not(.dark *) {
  background: var(--theme-bg-secondary) !important;
  color: var(--theme-text) !important;
}

.dark [class*="bg-gray-800"], .dark [class*="bg-gray-900"] {
  background: rgba(22, 78, 99, 0.9) !important;
  color: var(--theme-text) !important;
}

[class*="border-gray"] {
  border-color: var(--theme-border) !important;
}

[class*="text-gray-600"], [class*="text-gray-700"], [class*="text-gray-800"] {
  color: var(--theme-text-secondary) !important;
}

.dark [class*="text-gray-"] {
  color: var(--theme-text-secondary) !important;
}
`,
  },
  obsidian: {
    name: '曜石影院',
    description: '纯黑影院风，弱光护眼，暗部细节拉满',
    color: '#f59e0b',
    css: `
/* 浅色模式 */
:root:not(.dark) {
  --theme-primary: #b45309;
  --theme-primary-hover: #92400e;
  --theme-bg: #f5f1e8;
  --theme-bg-secondary: #efe9dc;
  --theme-text: #292524;
  --theme-text-secondary: #78716c;
  --theme-border: #d6cfbf;
}

:root:not(.dark) body {
  background: linear-gradient(135deg, #f5f1e8 0%, #e7e0d0 100%) !important;
  color: var(--theme-text) !important;
}

/* 深色模式 */
.dark {
  --theme-primary: #f59e0b;
  --theme-primary-hover: #d97706;
  --theme-bg: #000000;
  --theme-bg-secondary: #141414;
  --theme-text: #e7e5e4;
  --theme-text-secondary: #a8a29e;
  --theme-border: #292524;
}

.dark body {
  background: #000000 !important;
  color: var(--theme-text) !important;
}

/* 通用样式 */
[class*="bg-white"]:not(.dark *), [class*="bg-gray-50"]:not(.dark *) {
  background: var(--theme-bg-secondary) !important;
  color: var(--theme-text) !important;
}

.dark [class*="bg-gray-800"], .dark [class*="bg-gray-900"] {
  background: var(--theme-bg-secondary) !important;
  color: var(--theme-text) !important;
}

[class*="border-gray"] {
  border-color: var(--theme-border) !important;
}

[class*="text-gray-600"], [class*="text-gray-700"], [class*="text-gray-800"] {
  color: var(--theme-text-secondary) !important;
}

.dark [class*="text-gray-"] {
  color: var(--theme-text-secondary) !important;
}
`,
  },
  crimson: {
    name: '绯红剧场',
    description: '红黑剧场风，主色绯红，观影氛围浓',
    color: '#e11d48',
    css: `
/* 浅色模式 */
:root:not(.dark) {
  --theme-primary: #e11d48;
  --theme-primary-hover: #be123c;
  --theme-bg: #fff1f2;
  --theme-bg-secondary: #ffe4e6;
  --theme-text: #4c0519;
  --theme-text-secondary: #9f1239;
  --theme-border: #fecdd3;
}

:root:not(.dark) body {
  background: linear-gradient(135deg, #fff1f2 0%, #ffe4e6 100%) !important;
  color: var(--theme-text) !important;
}

/* 深色模式 */
.dark {
  --theme-primary: #fb4d6d;
  --theme-primary-hover: #e11d48;
  --theme-bg: #14060a;
  --theme-bg-secondary: #220a10;
  --theme-text: #ffe4e6;
  --theme-text-secondary: #fda4af;
  --theme-border: #4c0519;
}

.dark body {
  background: linear-gradient(135deg, #14060a 0%, #220a10 100%) !important;
  color: var(--theme-text) !important;
}

/* 通用样式 */
[class*="bg-white"]:not(.dark *), [class*="bg-gray-50"]:not(.dark *) {
  background: var(--theme-bg-secondary) !important;
  color: var(--theme-text) !important;
}

.dark [class*="bg-gray-800"], .dark [class*="bg-gray-900"] {
  background: var(--theme-bg-secondary) !important;
  color: var(--theme-text) !important;
}

[class*="border-gray"] {
  border-color: var(--theme-border) !important;
}

[class*="text-gray-600"], [class*="text-gray-700"], [class*="text-gray-800"] {
  color: var(--theme-text-secondary) !important;
}

.dark [class*="text-gray-"] {
  color: var(--theme-text-secondary) !important;
}
`,
  },
  ink_wash: {
    name: '水墨青瓷',
    description: '青绿水墨风，淡雅护眼，东方美学',
    color: '#0d9488',
    css: `
/* 浅色模式 */
:root:not(.dark) {
  --theme-primary: #0f766e;
  --theme-primary-hover: #115e59;
  --theme-bg: #f0fdfa;
  --theme-bg-secondary: #ccfbf1;
  --theme-text: #134e4a;
  --theme-text-secondary: #0f766e;
  --theme-border: #99f6e4;
}

:root:not(.dark) body {
  background: linear-gradient(135deg, #f0fdfa 0%, #ccfbf1 100%) !important;
  color: var(--theme-text) !important;
}

/* 深色模式 */
.dark {
  --theme-primary: #2dd4bf;
  --theme-primary-hover: #14b8a6;
  --theme-bg: #04211e;
  --theme-bg-secondary: #0a2e29;
  --theme-text: #ccfbf1;
  --theme-text-secondary: #5eead4;
  --theme-border: #115e59;
}

.dark body {
  background: linear-gradient(135deg, #04211e 0%, #0a2e29 100%) !important;
  color: var(--theme-text) !important;
}

/* 通用样式 */
[class*="bg-white"]:not(.dark *), [class*="bg-gray-50"]:not(.dark *) {
  background: var(--theme-bg-secondary) !important;
  color: var(--theme-text) !important;
}

.dark [class*="bg-gray-800"], .dark [class*="bg-gray-900"] {
  background: var(--theme-bg-secondary) !important;
  color: var(--theme-text) !important;
}

[class*="border-gray"] {
  border-color: var(--theme-border) !important;
}

[class*="text-gray-600"], [class*="text-gray-700"], [class*="text-gray-800"] {
  color: var(--theme-text-secondary) !important;
}

.dark [class*="text-gray-"] {
  color: var(--theme-text-secondary) !important;
}
`,
  },
  midnight_gold: {
    name: '午夜鎏金',
    description: '藏蓝底 + 鎏金点缀，轻奢质感',
    color: '#c9a227',
    css: `
/* 浅色模式 */
:root:not(.dark) {
  --theme-primary: #92690e;
  --theme-primary-hover: #75530b;
  --theme-bg: #faf6ea;
  --theme-bg-secondary: #f3ead0;
  --theme-text: #3b2f0b;
  --theme-text-secondary: #92690e;
  --theme-border: #e3d3a3;
}

:root:not(.dark) body {
  background: linear-gradient(135deg, #faf6ea 0%, #f3ead0 100%) !important;
  color: var(--theme-text) !important;
}

/* 深色模式 */
.dark {
  --theme-primary: #e3b93e;
  --theme-primary-hover: #c9a227;
  --theme-bg: #101325;
  --theme-bg-secondary: #1a1f38;
  --theme-text: #f3ead0;
  --theme-text-secondary: #c9b48a;
  --theme-border: #2e3560;
}

.dark body {
  background: linear-gradient(135deg, #101325 0%, #1a1f38 100%) !important;
  color: var(--theme-text) !important;
}

/* 通用样式 */
[class*="bg-white"]:not(.dark *), [class*="bg-gray-50"]:not(.dark *) {
  background: var(--theme-bg-secondary) !important;
  color: var(--theme-text) !important;
}

.dark [class*="bg-gray-800"], .dark [class*="bg-gray-900"] {
  background: var(--theme-bg-secondary) !important;
  color: var(--theme-text) !important;
}

[class*="border-gray"] {
  border-color: var(--theme-border) !important;
}

[class*="text-gray-600"], [class*="text-gray-700"], [class*="text-gray-800"] {
  color: var(--theme-text-secondary) !important;
}

.dark [class*="text-gray-"] {
  color: var(--theme-text-secondary) !important;
}
`,
  },
};

export type ThemeName = keyof typeof builtInThemes;

export function getThemeCSS(themeName: ThemeName): string {
  return builtInThemes[themeName]?.css || '';
}

export function getThemeNames(): { value: ThemeName; label: string }[] {
  return Object.entries(builtInThemes).map(([key, theme]) => ({
    value: key as ThemeName,
    label: theme.name,
  }));
}
