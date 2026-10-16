import { defineConfig } from 'vite'
import vue from '@vitejs/plugin-vue'

export default defineConfig({
  plugins: [vue()],
  server: {
    host: '127.0.0.1',
    // 统一端口规划：原 5173
    port: 6015,
    proxy: {
      '/api': {
        // 客服后端：6004（原 18082）
        target: 'http://127.0.0.1:6004',
        changeOrigin: true,
      },
      '/commerce': {
        // 建材业务服务：6014（原 18081）
        target: 'http://127.0.0.1:6014',
        changeOrigin: true,
        rewrite: (path) => path.replace(/^\/commerce/, ''),
      },
      '/health': {
        // 客服后端：6004（原 18082）
        target: 'http://127.0.0.1:6004',
        changeOrigin: true,
      },
    },
  },
})
