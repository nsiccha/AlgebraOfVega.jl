import { defineConfig } from 'vitepress'
import { tabsMarkdownPlugin } from 'vitepress-plugin-tabs'
import { mathjaxPlugin } from './mathjax-plugin'
import footnote from "markdown-it-footnote";
import path from 'path'

const mathjax = mathjaxPlugin()

function getBaseRepository(base: string): string {
  if (!base || base === '/') return '/';
  const parts = base.split('/').filter(Boolean);
  return parts.length > 0 ? `/${parts[0]}/` : '/';
}

const baseTemp = {
  base: 'REPLACE_ME_DOCUMENTER_VITEPRESS',// TODO: replace this in makedocs!
}

const navTemp = {
  nav: 'REPLACE_ME_DOCUMENTER_VITEPRESS',
}

const nav = [
  ...navTemp.nav,
  {
    component: 'VersionPicker'
  }
]

// https://vitepress.dev/reference/site-config
export default defineConfig({
  base: 'REPLACE_ME_DOCUMENTER_VITEPRESS',// TODO: replace this in makedocs!
  title: 'REPLACE_ME_DOCUMENTER_VITEPRESS',
  description: 'REPLACE_ME_DOCUMENTER_VITEPRESS',
  lastUpdated: true,
  cleanUrls: true,
  outDir: 'REPLACE_ME_DOCUMENTER_VITEPRESS', // This is required for MarkdownVitepress to work correctly...
  head: [
    ['link', { rel: 'icon', href: 'REPLACE_ME_DOCUMENTER_VITEPRESS_FAVICON' }],
    ['script', {src: `${getBaseRepository(baseTemp.base)}versions.js`}],
    // ['script', {src: '/versions.js'], for custom domains, I guess if deploy_url is available.
    ['script', {src: `${baseTemp.base}siteinfo.js`}],
    ['script', {src: 'https://cdn.jsdelivr.net/npm/vega@5'}],
    ['script', {src: 'https://cdn.jsdelivr.net/npm/vega-lite@5'}],
    ['script', {src: 'https://cdn.jsdelivr.net/npm/vega-embed@6'}],
    // HTMX runtime — for inlining live AoV gallery fragments via
    // `<div hx-get="…" hx-trigger="load">` placeholders. HTMX requests
    // carry HX-Request: true automatically, so AoV's routes return the
    // bare body fragment that drops directly into the docs page.
    ['script', {src: 'https://cdn.jsdelivr.net/npm/htmx.org@2.0.8/dist/htmx.min.js'}],
    // Map HTMXObjects' --htmxo-* theme variables to VitePress's
    // brand/state tokens so embedded gallery components match the docs
    // theme automatically. HTMXO defaults remain as fallback.
    ['style', {}, `
:root {
    --htmxo-accent:  var(--vp-c-brand-1, #4a90d9);
    --htmxo-success: var(--vp-c-success-1, #2a9d8f);
    --htmxo-warning: var(--vp-c-warning-1, #e9a23b);
    --htmxo-error:   var(--vp-c-danger-1, #e76f51);
    --htmxo-border:  var(--vp-c-divider, currentColor);
    --htmxo-muted:   var(--vp-c-text-3, color-mix(in srgb, currentColor 60%, transparent));
}
.htmxo-embed {
    border: 1px solid var(--vp-c-divider);
    border-radius: 8px;
    padding: 1rem;
    margin: 1rem 0;
    background: var(--vp-c-bg-soft);
}
    `]
  ],
  
  markdown: {
    config(md) {
      md.use(tabsMarkdownPlugin);
      md.use(footnote);
      mathjax.markdownConfig(md);
    },
    theme: {
      light: "github-light",
      dark: "github-dark"
    },
  },
  vite: {
    plugins: [
      mathjax.vitePlugin,
    ],
    define: {
      __DEPLOY_ABSPATH__: JSON.stringify('REPLACE_ME_DOCUMENTER_VITEPRESS_DEPLOY_ABSPATH'),
    },
    server: {
      proxy: {
        // Live AoV gallery embedding (dev only). `<div hx-get="/live-aov/…">`
        // forwards to the running AoV web app on :8092 so the docs page
        // shows live state. In production, point the same path at
        // recordings produced by `record!` — same markdown source.
        // Override the target via `AOV_DEV_TARGET=http://host:port` env.
        '/live-aov': {
          target: process.env.AOV_DEV_TARGET || 'http://localhost:8092',
          changeOrigin: true,
          rewrite: (path) => path.replace(/^\/live-aov/, ''),
        }
      }
    },
    resolve: {
      alias: {
        '@': path.resolve(__dirname, '../components')
      }
    },
    optimizeDeps: {
      exclude: [ 
        '@nolebase/vitepress-plugin-enhanced-readabilities/client',
        'vitepress',
        '@nolebase/ui',
      ], 
    }, 
    ssr: { 
      noExternal: [ 
        // If there are other packages that need to be processed by Vite, you can add them here.
        '@nolebase/vitepress-plugin-enhanced-readabilities',
        '@nolebase/ui',
      ], 
    },
  },
  themeConfig: {
    outline: 'deep',
    logo: 'REPLACE_ME_DOCUMENTER_VITEPRESS',
    search: {
      provider: 'local',
      options: {
        detailedView: true
      }
    },
    nav,
    sidebar: 'REPLACE_ME_DOCUMENTER_VITEPRESS',
    editLink: 'REPLACE_ME_DOCUMENTER_VITEPRESS',
    socialLinks: [
      { icon: 'github', link: 'REPLACE_ME_DOCUMENTER_VITEPRESS' }
    ],
    footer: {
      message: 'Made with <a href="https://luxdl.github.io/DocumenterVitepress.jl/dev/" target="_blank"><strong>DocumenterVitepress.jl</strong></a><br>',
      copyright: `© Copyright ${new Date().getUTCFullYear()}.`
    }
  }
})
