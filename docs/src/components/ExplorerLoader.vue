<template><span></span></template>

<script setup>
import { onMounted } from 'vue'
import { withBase } from 'vitepress'

onMounted(() => {
  if (typeof window === 'undefined') return
  const s = document.createElement('script')
  s.src = withBase('/explorer.js')
  document.body.appendChild(s)
})
</script>
