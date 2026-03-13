<template>
  <div ref="el" style="margin: 1rem 0;">Loading plot...</div>
</template>

<script setup>
import { ref, onMounted, watch } from 'vue'
import { withBase, useRouter } from 'vitepress'

const props = defineProps({
  src: { type: String, required: true }
})

const el = ref(null)

function waitForVegaEmbed(timeout = 10000) {
  return new Promise((resolve, reject) => {
    if (typeof window !== 'undefined' && window.vegaEmbed) return resolve(window.vegaEmbed)
    const start = Date.now()
    const check = setInterval(() => {
      if (window.vegaEmbed) { clearInterval(check); resolve(window.vegaEmbed) }
      else if (Date.now() - start > timeout) { clearInterval(check); reject(new Error('vega-embed CDN not loaded after ' + timeout + 'ms')) }
    }, 100)
  })
}

async function render() {
  if (!el.value || typeof window === 'undefined') return
  try {
    const url = withBase(props.src)
    const [resp, vegaEmbed] = await Promise.all([
      fetch(url),
      waitForVegaEmbed(),
    ])
    if (!resp.ok) throw new Error(`HTTP ${resp.status} fetching ${url}`)
    const spec = await resp.json()
    el.value.textContent = ''
    await vegaEmbed(el.value, spec, {
      actions: { source: false, editor: false }
    })
  } catch (e) {
    console.error('VegaPlot error:', e)
    if (el.value) el.value.textContent = 'Failed to load plot: ' + e.message
  }
}

onMounted(render)
watch(() => props.src, render)
</script>
