<script setup>
// ============================================================
// 数字人面板组件 —— 位于聊天对话框左侧的数字人显示区域
//
// 职责：
//   1. 提供数字人渲染容器（SDK 要求容器具有明确宽高）
//   2. 默认显示"连接数字人"按钮（数字人默认不连接）
//   3. 连接中展示加载效果（spinner + 资源下载进度条）
//   4. 已连接后由 SDK 渲染 3D 数字人，支持断开
// 播报逻辑不在本组件内：App.vue 收到客服回复后调用 notifyDigitalHuman()
// ============================================================
import { computed, onUnmounted } from 'vue'
import {
  digitalHumanState,
  connectDigitalHuman,
  disconnectDigitalHuman,
} from '../digital-human'

const CONTAINER_ID = 'digital-human-container'

// 状态徽标文案
const STATUS_LABELS = {
  idle: '未连接',
  connecting: '连接中',
  connected: '在线',
  error: '连接失败',
}

// 连接中的加载提示文案（随进度切换）
const loadingTip = computed(() => {
  const progress = digitalHumanState.progress
  if (progress < 15) return '正在建立数字人连接…'
  if (progress < 50) return '正在加载数字人形象资源…'
  if (progress < 90) return '资源加载过半，即将完成…'
  return '渲染初始化，马上就好…'
})

function connect() {
  connectDigitalHuman(CONTAINER_ID)
}

// 页面卸载前销毁实例（官方最佳实践：destroy 清理所有资源并断开连接）
onUnmounted(() => {
  disconnectDigitalHuman()
})
</script>

<template>
  <section class="dh-panel">
    <header class="dh-header">
      <div class="dh-header-info">
        <h2>数字人客服</h2>
        <span class="dh-status-badge" :class="`is-${digitalHumanState.status}`">
          {{ STATUS_LABELS[digitalHumanState.status] }}
        </span>
      </div>
      <transition name="dh-fade">
        <span v-if="digitalHumanState.speaking" class="dh-speaking-badge">
          <span class="dh-speaking-dot"></span>
          播报中
        </span>
      </transition>
    </header>

    <div class="dh-body">
      <!-- SDK 渲染容器：始终存在于 DOM（SDK 初始化时要求容器已挂载且具有明确宽高） -->
      <div :id="CONTAINER_ID" class="dh-canvas-container"></div>

      <!-- 未连接：占位 + 连接按钮 -->
      <div v-if="digitalHumanState.status === 'idle'" class="dh-overlay">
        <div class="dh-placeholder">
          <div class="dh-placeholder-glow"></div>
          <div class="dh-placeholder-icon">
            <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.4">
              <rect x="4" y="7" width="16" height="12" rx="4" />
              <circle cx="9" cy="13" r="1.4" fill="currentColor" stroke="none" />
              <circle cx="15" cy="13" r="1.4" fill="currentColor" stroke="none" />
              <path d="M12 7V4M12 4h.01" stroke-linecap="round" />
              <path d="M2.5 13h1.5M20 13h1.5" stroke-linecap="round" />
            </svg>
          </div>
          <p class="dh-placeholder-title">3D 数字人待命中</p>
          <p class="dh-placeholder-text">连接后，客服的回复将由数字人为你语音播报</p>
          <button class="dh-connect-btn" @click="connect">连接数字人</button>
        </div>
      </div>

      <!-- 连接中：spinner + 进度条加载效果 -->
      <div v-else-if="digitalHumanState.status === 'connecting'" class="dh-overlay">
        <div class="dh-loading">
          <div class="dh-spinner"></div>
          <p class="dh-loading-text">{{ loadingTip }}</p>
          <div class="dh-progress-track">
            <div
              class="dh-progress-bar"
              :style="{ width: digitalHumanState.progress + '%' }"
            ></div>
          </div>
          <p class="dh-progress-text">{{ digitalHumanState.progress }}%</p>
        </div>
      </div>

      <!-- 连接失败：错误信息 + 重试 -->
      <div v-else-if="digitalHumanState.status === 'error'" class="dh-overlay">
        <div class="dh-error">
          <p class="dh-error-text">{{ digitalHumanState.error }}</p>
          <button class="dh-connect-btn" @click="connect">重新连接</button>
        </div>
      </div>
    </div>

    <footer class="dh-footer">
      <template v-if="digitalHumanState.status === 'connected'">
        <p v-if="digitalHumanState.warning" class="dh-footer-warning">{{ digitalHumanState.warning }}</p>
        <p v-else class="dh-footer-tip">
          {{ digitalHumanState.speaking ? '数字人正在播报客服回复…' : '客服回复将由数字人自动语音播报' }}
        </p>
        <button class="dh-disconnect-btn" @click="disconnectDigitalHuman">断开连接</button>
      </template>
      <p v-else class="dh-footer-tip is-muted">点击"连接数字人"开始 3D 语音服务</p>
    </footer>
  </section>
</template>

<style scoped>
/* 面板占位：宽度由 App.vue 的 .workspace 网格列控制（330px），此处铺满即可 */
/* 高度对齐 App.vue：视口高 - 上下留白 48px - 顶栏 64px - 顶栏下间距 20px */
.dh-panel {
  display: flex;
  flex-direction: column;
  min-height: calc(100vh - 132px);
  height: calc(100vh - 132px);
  background: var(--color-surface);
  backdrop-filter: blur(24px) saturate(1.15);
  -webkit-backdrop-filter: blur(24px) saturate(1.15);
  border: 1px solid var(--color-border);
  border-radius: var(--radius-lg);
  box-shadow: var(--shadow-md), var(--shadow-inner-glow);
  overflow: hidden;
}

/* ── 头部 ── */
.dh-header {
  display: flex;
  align-items: center;
  justify-content: space-between;
  gap: 10px;
  padding: 18px 20px;
  border-bottom: 1px solid var(--color-border-light);
}

.dh-header-info {
  display: flex;
  align-items: center;
  gap: 10px;
  min-width: 0;
}

.dh-header h2 {
  margin: 0;
  font-size: 15px;
  font-weight: 600;
  letter-spacing: 0.02em;
  color: var(--color-text-primary);
  white-space: nowrap;
}

.dh-status-badge {
  flex-shrink: 0;
  padding: 3px 10px;
  border-radius: var(--radius-full);
  font-size: 11px;
  line-height: 1.4;
  border: 1px solid transparent;
}

.dh-status-badge.is-idle {
  color: var(--color-text-secondary);
  background: var(--color-surface-raised);
  border-color: var(--color-border);
}

.dh-status-badge.is-connecting {
  color: var(--color-warm);
  background: var(--color-warm-soft);
  border-color: var(--color-warm-glow);
}

.dh-status-badge.is-connected {
  color: var(--color-success);
  background: var(--color-success-soft);
}

.dh-status-badge.is-error {
  color: var(--color-danger);
  background: var(--color-danger-soft);
}

.dh-speaking-badge {
  display: inline-flex;
  align-items: center;
  gap: 6px;
  flex-shrink: 0;
  padding: 3px 10px;
  border-radius: var(--radius-full);
  font-size: 11px;
  color: var(--color-accent);
  background: var(--color-accent-soft);
}

.dh-speaking-dot {
  width: 6px;
  height: 6px;
  border-radius: 50%;
  background: var(--color-accent);
  animation: dh-pulse 1s ease-in-out infinite;
}

@keyframes dh-pulse {
  0%, 100% { opacity: 1; transform: scale(1); }
  50% { opacity: 0.35; transform: scale(0.75); }
}

.dh-fade-enter-active,
.dh-fade-leave-active {
  transition: opacity var(--duration-fast) ease;
}

.dh-fade-enter-from,
.dh-fade-leave-to {
  opacity: 0;
}

/* ── 主体（渲染容器 + 覆盖层）── */
.dh-body {
  position: relative;
  flex: 1;
  min-height: 0;
  /* 用 flex 让渲染容器拉伸填满：
     SDK 初始化时会向容器写入内联样式 position:relative（覆盖样式表的 position:absolute），
     若容器靠 absolute/inset 撑高会塌缩为 0 高度，导致 SDK 计算出的画布高度为 0（黑屏）；
     作为 flex 子项则不受该内联样式影响，始终有明确宽高（官方要求） */
  display: flex;
  flex-direction: column;
  background:
    radial-gradient(ellipse 80% 55% at 50% 30%, var(--color-accent-soft-bg), transparent 70%),
    var(--color-bg-surface);
}

/* SDK 画布容器：flex 拉伸填满主体区域，保证明确的宽高 */
.dh-canvas-container {
  flex: 1;
  min-height: 0;
  width: 100%;
}

.dh-overlay {
  position: absolute;
  inset: 0;
  display: flex;
  align-items: center;
  justify-content: center;
  padding: 24px;
  background: var(--color-bg-surface);
  /* SDK 画布内联 zIndex 为 100，覆盖层需更高才能在连接中/失败时盖住画布 */
  z-index: 200;
}

/* ── 未连接占位 ── */
.dh-placeholder {
  position: relative;
  display: flex;
  flex-direction: column;
  align-items: center;
  text-align: center;
}

.dh-placeholder-glow {
  position: absolute;
  top: -36px;
  width: 150px;
  height: 150px;
  border-radius: 50%;
  background: radial-gradient(circle, var(--color-accent-glow), transparent 70%);
  animation: dh-breathe 3.2s var(--ease-in-out) infinite;
  pointer-events: none;
}

@keyframes dh-breathe {
  0%, 100% { opacity: 0.5; transform: scale(0.9); }
  50% { opacity: 1; transform: scale(1.08); }
}

.dh-placeholder-icon {
  width: 76px;
  height: 76px;
  display: flex;
  align-items: center;
  justify-content: center;
  border-radius: 24px;
  color: var(--color-accent);
  background: var(--color-accent-soft);
  border: 1px solid var(--color-accent-glow);
  box-shadow: var(--shadow-glow-teal);
}

.dh-placeholder-icon svg {
  width: 42px;
  height: 42px;
}

.dh-placeholder-title {
  margin: 18px 0 6px;
  font-size: 15px;
  font-weight: 600;
  color: var(--color-text-primary);
}

.dh-placeholder-text {
  margin: 0 0 22px;
  font-size: 12.5px;
  line-height: 1.7;
  color: var(--color-text-secondary);
  max-width: 220px;
}

.dh-connect-btn {
  padding: 11px 30px;
  border: none;
  border-radius: var(--radius-full);
  font-size: 14px;
  font-weight: 600;
  letter-spacing: 0.03em;
  color: var(--color-text-inverse);
  background: linear-gradient(135deg, var(--color-accent), var(--color-accent-strong));
  box-shadow: 0 6px 22px var(--color-accent-glow);
  cursor: pointer;
  transition: transform var(--duration-fast) var(--ease-out-expo),
    box-shadow var(--duration-fast) ease;
}

.dh-connect-btn:hover {
  transform: translateY(-2px);
  box-shadow: 0 10px 28px var(--color-accent-glow);
}

.dh-connect-btn:active {
  transform: translateY(0);
}

/* ── 连接中加载效果 ── */
.dh-loading {
  display: flex;
  flex-direction: column;
  align-items: center;
  width: 100%;
  max-width: 230px;
  text-align: center;
}

.dh-spinner {
  width: 46px;
  height: 46px;
  border-radius: 50%;
  border: 3px solid var(--color-accent-soft);
  border-top-color: var(--color-accent);
  animation: dh-spin 0.9s linear infinite;
  margin-bottom: 18px;
}

@keyframes dh-spin {
  to { transform: rotate(360deg); }
}

.dh-loading-text {
  margin: 0 0 14px;
  font-size: 13px;
  color: var(--color-text-primary);
}

.dh-progress-track {
  width: 100%;
  height: 6px;
  border-radius: var(--radius-full);
  background: var(--color-surface-raised);
  overflow: hidden;
  border: 1px solid var(--color-border-light);
}

.dh-progress-bar {
  height: 100%;
  border-radius: var(--radius-full);
  background: linear-gradient(90deg, var(--color-accent-strong), var(--color-accent));
  box-shadow: 0 0 10px var(--color-accent-glow);
  transition: width 0.25s var(--ease-out-expo);
}

.dh-progress-text {
  margin: 10px 0 0;
  font-size: 11.5px;
  font-variant-numeric: tabular-nums;
  color: var(--color-text-muted);
}

/* ── 连接失败 ── */
.dh-error {
  display: flex;
  flex-direction: column;
  align-items: center;
  gap: 18px;
  text-align: center;
}

.dh-error-text {
  margin: 0;
  font-size: 13px;
  line-height: 1.7;
  color: var(--color-danger);
  max-width: 230px;
  word-break: break-all;
}

/* ── 底部 ── */
.dh-footer {
  display: flex;
  flex-direction: column;
  align-items: center;
  gap: 10px;
  padding: 14px 20px 16px;
  border-top: 1px solid var(--color-border-light);
}

.dh-footer-tip {
  margin: 0;
  font-size: 11.5px;
  line-height: 1.5;
  text-align: center;
  color: var(--color-text-secondary);
}

.dh-footer-tip.is-muted {
  color: var(--color-text-muted);
}

.dh-footer-warning {
  margin: 0;
  font-size: 11.5px;
  line-height: 1.5;
  text-align: center;
  color: var(--color-warm);
}

.dh-disconnect-btn {
  padding: 7px 18px;
  border-radius: var(--radius-full);
  font-size: 12px;
  color: var(--color-text-secondary);
  background: transparent;
  border: 1px solid var(--color-border);
  cursor: pointer;
  transition: color var(--duration-fast) ease, border-color var(--duration-fast) ease,
    background var(--duration-fast) ease;
}

.dh-disconnect-btn:hover {
  color: var(--color-danger);
  border-color: var(--color-danger);
  background: var(--color-danger-soft);
}

/* ── 窄屏：与 App.vue 的 1180px 断点保持一致，单列布局下隐藏数字人面板 ── */
@media (max-width: 1180px) {
  .dh-panel {
    display: none;
  }
}
</style>
