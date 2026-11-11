import { defineConfig } from 'vitepress'

const baseTemp = { base: 'REPLACE_ME_DOCUMENTER_VITEPRESS' }
export default defineConfig({
  base: 'REPLACE_ME_DOCUMENTER_VITEPRESS',
  title: 'REPLACE_ME_DOCUMENTER_VITEPRESS',
  description: 'Browser figures from AlgebraOfGraphics expressions.',
  lastUpdated: true,
  cleanUrls: true,
  outDir: 'REPLACE_ME_DOCUMENTER_VITEPRESS',
  head: [
    ['link', { rel: 'icon', href: 'REPLACE_ME_DOCUMENTER_VITEPRESS_FAVICON' }],
    ['link', { rel: 'stylesheet', href: `${baseTemp.base}vendor/aov.css` }],
    ...['vega.min.js', 'vega-lite.min.js', 'vega-embed.min.js', 'aov-runtime.js']
      .map(file => ['script', { src: `${baseTemp.base}vendor/${file}` }]),
  ],
  markdown: { theme: { light: 'github-light', dark: 'github-dark' } },
  vite: { define: { __DEPLOY_ABSPATH__: JSON.stringify('REPLACE_ME_DOCUMENTER_VITEPRESS_DEPLOY_ABSPATH') } },
  themeConfig: {
    outline: [2, 3],
    logo: 'REPLACE_ME_DOCUMENTER_VITEPRESS',
    search: { provider: 'local' },
    nav: 'REPLACE_ME_DOCUMENTER_VITEPRESS',
    sidebar: 'REPLACE_ME_DOCUMENTER_VITEPRESS',
    editLink: 'REPLACE_ME_DOCUMENTER_VITEPRESS',
    socialLinks: [{ icon: 'github', link: 'REPLACE_ME_DOCUMENTER_VITEPRESS' }],
  },
})
