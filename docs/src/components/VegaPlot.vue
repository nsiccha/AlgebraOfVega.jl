<script setup>
import { ref, onMounted, onBeforeUnmount, watch } from 'vue'
import { withBase } from 'vitepress'

const props = defineProps({
  src: { type: String, required: true },
  plotId: { type: String, required: true },
})
const error = ref('')
let abort
let generation = 0
let mountedId
async function render() {
  const current = ++generation
  abort?.abort()
  abort = new AbortController()
  error.value = ''
  try {
    const response = await fetch(withBase(props.src), { signal: abort.signal })
    if (!response.ok) throw new Error(`HTTP ${response.status}: ${props.src}`)
    const spec = await response.json()
    if (current !== generation) return
    if (!window.AoV || !window.vegaEmbed) throw new Error('Plot runtime did not load')
    if (mountedId && mountedId !== props.plotId) window.AoV.dispose(mountedId)
    mountedId = props.plotId
    await window.AoV.embed(props.plotId, spec, { actions: false })
  } catch (e) {
    if (e.name !== 'AbortError') {
      error.value = e.message
      console.error('VegaPlot:', e)
    }
  }
}
onMounted(render)
watch([() => props.src, () => props.plotId], render)
onBeforeUnmount(() => {
  ++generation
  abort?.abort()
  if (mountedId) window.AoV?.dispose(mountedId)
})
</script>

<template>
  <div class="docs-plot">
    <p v-if="error" role="alert">Figure unavailable: {{ error }}</p>
    <div :id="plotId" aria-label="Interactive figure"></div>
  </div>
</template>
