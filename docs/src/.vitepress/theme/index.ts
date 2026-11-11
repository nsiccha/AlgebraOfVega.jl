import DefaultTheme from 'vitepress/theme'
import type { Theme } from 'vitepress'
import VegaPlot from '../../components/VegaPlot.vue'
import './style.css'
import './docstrings.css'

export default {
  extends: DefaultTheme,
  enhanceApp({ app }) {
    app.component('VegaPlot', VegaPlot)
  },
} satisfies Theme
