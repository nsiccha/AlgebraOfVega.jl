// .vitepress/theme/index.ts
import { h } from 'vue'
import DefaultTheme from 'vitepress/theme'
import type { Theme as ThemeConfig } from 'vitepress'
import 'virtual:mathjax-styles.css';

import { 
  NolebaseEnhancedReadabilitiesMenu, 
  NolebaseEnhancedReadabilitiesScreenMenu, 
} from '@nolebase/vitepress-plugin-enhanced-readabilities/client'

import VersionPicker from "@/VersionPicker.vue"
import AuthorBadge from '@/AuthorBadge.vue'
import Authors from '@/Authors.vue'
import Banner from '@/Banner.vue'
import VegaPlot from '@/VegaPlot.vue'
import ExplorerLoader from '@/ExplorerLoader.vue'

import { enhanceAppWithTabs } from 'vitepress-plugin-tabs/client'

import '@nolebase/vitepress-plugin-enhanced-readabilities/client/style.css'
import './style.css' // You could setup your own, or else a default will be copied.
import './docstrings.css' // You could setup your own, or else a default will be copied.

export const Theme: ThemeConfig = {
  extends: DefaultTheme,
  Layout() {
    return h(DefaultTheme.Layout, null, {
      'layout-bottom': () => h(Banner),
      'nav-bar-content-after': () => [
        h(NolebaseEnhancedReadabilitiesMenu), // Enhanced Readabilities menu
      ],
      // A enhanced readabilities menu for narrower screens (usually smaller than iPad Mini)
      'nav-screen-content-after': () => h(NolebaseEnhancedReadabilitiesScreenMenu),
    })
  },
  enhanceApp({ app, router, siteData }) {
    enhanceAppWithTabs(app);
    app.component('VersionPicker', VersionPicker);
    app.component('AuthorBadge', AuthorBadge)
    app.component('Authors', Authors)
    app.component('VegaPlot', VegaPlot)
    app.component('ExplorerLoader', ExplorerLoader)
    // VitePress is an SPA: `<div hx-trigger="load">` placeholders only
    // fire on initial mount. After client-side navigation, new HTMX
    // placeholders need a manual `htmx.process(document.body)` to be
    // picked up. Hook the after-route-change event for that.
    if (typeof window !== 'undefined' && router) {
      router.onAfterRouteChanged = () => {
        // @ts-ignore - htmx loaded via head <script>; no types.
        if (window.htmx) window.htmx.process(document.body);
      };

      // Embedded HTMXO fragments contain root-absolute links like
      // `<a href="/standalone/foo">` that point at the AoV server's
      // own paths. Without rewriting they resolve against VitePress's
      // origin and 404. Rewrite root-absolute hrefs and hx-* URLs
      // inside `.htmxo-embed` containers to go through the
      // `/live-aov` proxy. Same for `/live-htmxo` (HTMXObjects docs).
      const rewritePrefix = (
        document.querySelector('meta[name="htmxo-embed-prefix"]')?.getAttribute('content')
        ?? '/live-aov'
      );
      const rewriteRootRefs = (root: HTMLElement) => {
        const fix = (el: Element, attr: string) => {
          const v = el.getAttribute(attr);
          if (v && v.startsWith('/') && !v.startsWith('//') && !v.startsWith(rewritePrefix)) {
            el.setAttribute(attr, rewritePrefix + v);
          }
        };
        root.querySelectorAll('[href]').forEach((el) => fix(el, 'href'));
        root.querySelectorAll('[hx-get]').forEach((el) => fix(el, 'hx-get'));
        root.querySelectorAll('[hx-post]').forEach((el) => fix(el, 'hx-post'));
        root.querySelectorAll('[hx-put]').forEach((el) => fix(el, 'hx-put'));
        root.querySelectorAll('[hx-patch]').forEach((el) => fix(el, 'hx-patch'));
        root.querySelectorAll('[hx-delete]').forEach((el) => fix(el, 'hx-delete'));
      };
      document.body.addEventListener('htmx:afterSwap', (e: any) => {
        const tgt = e?.detail?.target as HTMLElement | undefined;
        if (!tgt) return;
        // Walk up to find an enclosing `.htmxo-embed`; if none, no rewrite.
        const embed = tgt.closest('.htmxo-embed');
        if (!embed) return;
        rewriteRootRefs(embed as HTMLElement);
      });
    }
  }
}
export default Theme