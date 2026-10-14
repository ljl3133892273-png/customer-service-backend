<script setup>
import { computed, nextTick, onMounted, ref, watch } from 'vue'
import xiaoerAvatar from './assets/xiaoer.png'
import userProfileAvatar from './assets/userProfileAvatar.svg'
import DigitalHumanPanel from './components/DigitalHumanPanel.vue' // 数字人面板（聊天对话框左侧）
import { notifyDigitalHuman } from './digital-human' // 数字人播报通知

const senderId = ref('u1001')
const draftMessage = ref('')
const isSending = ref(false)
const errorMessage = ref('')
const messages = ref([])
const messagesContainer = ref(null)

const orders = ref([])
const products = ref([])
const isLoadingSidebar = ref(false)
const sidebarError = ref('')
const activeTab = ref('orders')

// TTS state
const ttsState = ref({})
let currentAudio = null

// Copy state
const copyState = ref({})


// 客服数字人配置
const customerService = {
  name: '老三',
  title: '瓷砖顾问',
  avatar: xiaoerAvatar,
  status: '在线'
}

// 用户配置
const userProfile = {
  name: '你',
  avatar: userProfileAvatar
}

// 将消息分组为 Turn 结构
const turns = computed(() => {
  const result = []
  let currentTurn = null
  let turnIndex = 0

  for (const message of messages.value) {
    if (message.type === 'divider') {
      if (currentTurn) {
        result.push(currentTurn)
        currentTurn = null
      }
      result.push({
        type: 'divider',
        text: message.text
      })
      continue
    }

    if (message.role === 'user') {
      // 如果有待处理的当前 turn，先保存
      if (currentTurn) {
        result.push(currentTurn)
      }
      // 创建新的 turn
      turnIndex++
      currentTurn = {
        type: 'turn',
        id: `turn-${turnIndex}`,
        index: turnIndex,
        userMessage: message,
        botMessages: []
      }
    } else if (message.role === 'bot') {
      if (!currentTurn) {
        // 如果没有当前 turn，创建一个（可能是因为历史消息）
        turnIndex++
        currentTurn = {
          type: 'turn',
          id: `turn-${turnIndex}`,
          index: turnIndex,
          userMessage: null,
          botMessages: []
        }
      }
      currentTurn.botMessages.push(message)
    }
  }

  if (currentTurn) {
    result.push(currentTurn)
  }

  return result
})

const chatEndpoint = computed(() => '/api/chat')
const chatHistoryEndpoint = computed(
  () => `/api/chat/history?sender_id=${encodeURIComponent(senderId.value.trim())}`
)
const commerceOrdersEndpoint = computed(
  () => `/commerce/users/${encodeURIComponent(senderId.value.trim())}/orders`
)
const commerceProductsEndpoint = computed(
  () => `/commerce/users/${encodeURIComponent(senderId.value.trim())}/products`
)

function createBaseMessage(role) {
  return {
    id: crypto.randomUUID(),
    role,
    buttons: [],
  }
}

function appendUserText(text) {
  messages.value.push({
    ...createBaseMessage('user'),
    type: 'text',
    text,
  })
}

function appendUserObject(objectType, payload) {
  messages.value.push({
    ...createBaseMessage('user'),
    type: 'object',
    objectType,
    payload,
  })
}

function appendBotMessages(botMessages) {
  for (const message of botMessages) {
    appendMessage('bot', message)
  }
}

function appendMessage(role, message) {
  if (role === 'divider') {
    messages.value.push({
      ...createBaseMessage('divider'),
      type: 'divider',
      text: message.text ?? '以上为历史消息',
    })
    return
  }

  if (message.object) {
    messages.value.push({
      ...createBaseMessage(role),
      type: 'object',
      objectType: message.object.type,
      payload: message.object,
    })
  } else {
    messages.value.push({
      ...createBaseMessage(role),
      type: 'text',
      text: message.text ?? '',
      suggestions: message.suggestions ?? null,
    })
  }
}

function setHistoryMessages(historyMessages) {
  messages.value = []
  for (const message of historyMessages) {
    const role = ['user', 'bot', 'divider'].includes(message.role) ? message.role : 'bot'
    appendMessage(role, message)
  }
}

async function scrollToBottom() {
  await nextTick()
  const container = messagesContainer.value
  if (!container) {
    return
  }
  container.scrollTop = container.scrollHeight
}

watch(
  () => messages.value.length,
  async () => {
    await scrollToBottom()
  }
)

function resetConversation() {
  messages.value = []
  errorMessage.value = ''
}

function formatAmount(amount) {
  const numericAmount = Number(amount)
  if (Number.isNaN(numericAmount)) {
    return '￥0.00'
  }
  return `￥${numericAmount.toFixed(2)}`
}

const ORDER_STATUS_CLASS = {
  '待发货': 'status-warning',
  '待揽收': 'status-warning',
  '运输中': 'status-info',
  '派送中': 'status-info',
  '已完成': 'status-success',
  '已签收': 'status-success',
  '已取消': 'status-muted',
  '退款中': 'status-danger',
  '已退款': 'status-muted',
}

function getStatusClass(status) {
  return ORDER_STATUS_CLASS[status] || 'status-muted'
}

function formatProductSummary(product) {
  if (product.description) {
    return product.description
  }
  if (product.attributes?.price) {
    return `商品价格：${formatAmount(product.attributes.price)}`
  }
  return '商品信息'
}

function getObjectTitle(message) {
  const payload = message.payload ?? {}
  if (payload.title) {
    return payload.title
  }
  return message.objectType === 'order' ? '订单对象' : '商品对象'
}

function getObjectIdentifier(message) {
  const payload = message.payload ?? {}
  const id = payload.order_id ?? payload.product_id ?? payload.id
  const label = message.objectType === 'order' ? '订单号' : '商品号'
  return id ? `${label}：${id}` : label
}

function getObjectSummary(message) {
  const payload = message.payload ?? {}
  if (message.objectType === 'order') {
    const status = payload.status ?? payload.attributes?.status
    return status ? `订单状态：${status}` : '订单'
  }
  return formatProductSummary(payload)
}

function getObjectAmount(message) {
  const payload = message.payload ?? {}
  const amount = message.objectType === 'order'
    ? payload.amount ?? payload.attributes?.amount
    : payload.price ?? payload.attributes?.price
  return formatAmount(amount)
}

async function fetchSidebarData() {
  const currentSenderId = senderId.value.trim()
  orders.value = []
  products.value = []
  sidebarError.value = ''

  if (!currentSenderId) {
    return
  }

  isLoadingSidebar.value = true
  try {
    const [ordersResponse, productsResponse] = await Promise.all([
      fetch(commerceOrdersEndpoint.value),
      fetch(commerceProductsEndpoint.value),
    ])

    const [ordersPayload, productsPayload] = await Promise.all([
      ordersResponse.json(),
      productsResponse.json(),
    ])

    if (!ordersResponse.ok) {
      throw new Error(ordersPayload.detail || '加载订单列表失败。')
    }
    if (!productsResponse.ok) {
      throw new Error(productsPayload.detail || '加载商品列表失败。')
    }

    orders.value = Array.isArray(ordersPayload?.data?.orders) ? ordersPayload.data.orders : []
    products.value = Array.isArray(productsPayload?.data?.products) ? productsPayload.data.products : []
  } catch (error) {
    sidebarError.value = error instanceof Error ? error.message : '加载右侧列表失败。'
  } finally {
    isLoadingSidebar.value = false
  }
}

async function fetchChatHistory() {
  const currentSenderId = senderId.value.trim()
  if (!currentSenderId) {
    messages.value = []
    return
  }

  try {
    const response = await fetch(chatHistoryEndpoint.value)
    const data = await response.json()
    if (!response.ok) {
      throw new Error(data.detail || '加载历史消息失败。')
    }
    if (currentSenderId === senderId.value.trim()) {
      setHistoryMessages(Array.isArray(data?.messages) ? data.messages : [])
    }
  } catch (error) {
    errorMessage.value = error instanceof Error ? error.message : '加载历史消息失败。'
  }
}

async function sendPayload(payload) {
  if (isSending.value) {
    return
  }

  errorMessage.value = ''
  isSending.value = true

  try {
    const response = await fetch(chatEndpoint.value, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({
        sender_id: senderId.value.trim(),
        ...payload,
      }),
    })

    const data = await response.json()
    if (!response.ok) {
      throw new Error(data.detail || '请求失败。')
    }

    appendBotMessages(data.messages ?? [])
    // 数字人已连接时，解析本次响应内容并驱动数字人同步播报（未连接则静默跳过）
    notifyDigitalHuman(data.messages ?? [])
  } catch (error) {
    errorMessage.value = error instanceof Error ? error.message : '请求失败。'
  } finally {
    isSending.value = false
  }
}

async function sendSuggestion(text) {
  appendUserText(text)
  await sendPayload({ text })
}

async function sendQuickText(text) {
  draftMessage.value = text
  await sendTextMessage()
}
async function sendTextMessage() {
  const text = draftMessage.value.trim()
  const currentSenderId = senderId.value.trim()

  if (!currentSenderId) {
    errorMessage.value = '请先输入 sender_id。'
    return
  }
  if (!text) {
    return
  }

  draftMessage.value = ''
  appendUserText(text)
  await sendPayload({ text })
}

async function sendOrder(order) {
  const currentSenderId = senderId.value.trim()
  if (!currentSenderId) {
    errorMessage.value = '请先输入 sender_id。'
    return
  }

  appendUserObject('order', { ...order })
  await sendPayload({
    object: {
      type: 'order',
      id: order.order_id,
      title: order.title,
      attributes: {
        status: order.status,
        amount: order.amount,
        created_at: order.created_at,
        cover_url: order.cover_url,
      },
    },
  })
}

async function sendProduct(product) {
  const currentSenderId = senderId.value.trim()
  if (!currentSenderId) {
    errorMessage.value = '请先输入 sender_id。'
    return
  }

  appendUserObject('product', { ...product })
  await sendPayload({
    object: {
      type: 'product',
      id: product.product_id,
      title: product.title,
      attributes: {
        price: product.price,
        cover_url: product.cover_url,
        description: product.description,
      },
    },
  })
}

watch(
  () => senderId.value.trim(),
  async (value, previousValue) => {
    if (value === previousValue) {
      return
    }

    resetConversation()
    if (!value) {
      orders.value = []
      products.value = []
      return
    }
    await Promise.all([fetchSidebarData(), fetchChatHistory()])
  }
)

onMounted(async () => {
  await Promise.all([fetchSidebarData(), fetchChatHistory()])
})

async function playTts(botMsg) {
  const msgId = botMsg.id
  if (!botMsg.text || ttsState.value[msgId] === 'loading') return

  if (currentAudio) { currentAudio.pause(); currentAudio = null }
  for (const key of Object.keys(ttsState.value)) {
    if (ttsState.value[key] === 'playing') ttsState.value[key] = 'idle'
  }

  ttsState.value[msgId] = 'loading'
  try {
    const response = await fetch('/api/chat/tts', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ text: botMsg.text }),
    })
    if (!response.ok) throw new Error('TTS 请求失败')
    const blob = await response.blob()
    const url = URL.createObjectURL(blob)
    currentAudio = new Audio(url)
    ttsState.value[msgId] = 'playing'
    currentAudio.onended = () => { ttsState.value[msgId] = 'idle'; URL.revokeObjectURL(url); currentAudio = null }
    currentAudio.onerror = () => { ttsState.value[msgId] = 'idle'; URL.revokeObjectURL(url); currentAudio = null }
    await currentAudio.play()
  } catch (error) {
    ttsState.value[msgId] = 'idle'
    console.error('TTS error:', error)
  }
}

async function copyBotText(botMsg) {
  const msgId = botMsg.id
  try {
    await navigator.clipboard.writeText(botMsg.text)
    copyState.value[msgId] = true
    setTimeout(() => { copyState.value[msgId] = false }, 1800)
  } catch (error) {
    console.error('Copy failed:', error)
  }
}
</script>

<template>
  <div class="app-shell">
    <!-- 顶部全局栏：品牌 / 客服状态 / 用户切换 / 新对话 -->
    <header class="topbar">
      <div class="topbar-brand">
        <span class="topbar-logo" aria-hidden="true"></span>
        <h1>正狮陶瓷 · 智能客服</h1>
      </div>

      <div class="topbar-service">
        <span class="topbar-service-avatar-wrapper">
          <img :src="customerService.avatar" class="topbar-service-avatar" :alt="customerService.name" />
          <span class="status-indicator"></span>
        </span>
        <span class="topbar-service-info">
          <span class="topbar-service-name">{{ customerService.name }} · {{ customerService.title }}</span>
          <span class="topbar-service-status">{{ customerService.status }}</span>
        </span>
      </div>

      <div class="topbar-controls">
        <label class="topbar-field">
          <span>sender_id</span>
          <input v-model="senderId" type="text" placeholder="u1001" />
        </label>
        <button
          type="button"
          class="secondary-button"
          :disabled="isLoadingSidebar"
          @click="fetchSidebarData"
        >
          {{ isLoadingSidebar ? '加载中...' : '刷新数据' }}
        </button>
      </div>

      <button type="button" class="clear-button" title="清空对话" @click="resetConversation">
        <span>🔄</span>
        <span>新对话</span>
      </button>
    </header>

    <div class="workspace">
      <!-- 数字人显示区域（聊天对话框左侧，默认未连接） -->
      <DigitalHumanPanel />
      <div class="chat-card">
        <header class="chat-subheader">
          <span class="chat-subheader-title">对话</span>
          <span class="chat-subheader-hint">切换用户自动加载历史消息</span>
        </header>

        <section ref="messagesContainer" class="messages">
          <div v-if="turns.length === 0" class="welcome">
            <div class="welcome-card">
              <div class="welcome-glow"></div>
              <div class="welcome-avatar-wrapper">
                <img :src="customerService.avatar" class="welcome-avatar" alt="老三" />
                <span class="welcome-status-pulse"></span>
              </div>
              <h2 class="welcome-greeting">Hi，我是 {{ customerService.name }}</h2>
              <p class="welcome-subtitle">正狮陶瓷 · 你的专属选砖顾问，随时为你服务</p>
              <div class="welcome-chips">
                <button
                  v-for="chip in ['查一下我的订单', '这批砖发到哪了', '砖有破损要退款', '瓷砖应该怎么选']"
                  :key="chip"
                  type="button"
                  class="welcome-chip"
                  :disabled="isSending"
                  @click="sendQuickText(chip)"
                >{{ chip }}</button>
              </div>
              <p class="welcome-features">
                <span>💬 文字对话</span>
                <span>🔊 语音播报</span>
                <span>📦 订单查询</span>
                <span>🧱 瓷砖花色</span>
              </p>
            </div>
          </div>

          <!-- Turn 结构展示 -->
          <template v-for="(item, index) in turns" :key="item.id || index">
            <!-- 分隔线 -->
            <div v-if="item.type === 'divider'" class="history-divider">
              <span>{{ item.text }}</span>
            </div>

            <!-- Turn 卡片 -->
            <div v-else class="turn-card" :class="{ 'has-user-message': item.userMessage }">
              <!-- Turn 标识 -->
              <div class="turn-header">
                <span class="turn-badge">Turn {{ item.index }}</span>
                <span class="turn-label">对话轮次</span>
              </div>

              <!-- 用户消息区域 -->
              <div v-if="item.userMessage" class="turn-section user-section">
                <div class="section-header">
                  <div class="avatar-wrapper user-avatar">
                    <img :src="userProfile.avatar" class="avatar" />
                  </div>
                  <div class="agent-info">
                    <span class="agent-name">{{ userProfile.name }}</span>
                    <span class="agent-label">用户</span>
                  </div>
                </div>
                <div class="turn-bubble user-bubble">
                  <template v-if="item.userMessage.type === 'object'">
                    <div class="object-card" :class="`object-card-${item.userMessage.objectType}`">
                      <div class="object-card-badge">
                        {{ item.userMessage.objectType === 'order' ? '订单对象' : '商品对象' }}
                      </div>
                      <img
                        v-if="item.userMessage.type === 'object' && item.userMessage.payload.cover_url"
                        :src="item.userMessage.payload.cover_url"
                        :alt="getObjectTitle(item.userMessage)"
                        class="object-card-image"
                        @error="$event.target.style.display='none'"
                      />
                      <div class="object-card-title">{{ getObjectTitle(item.userMessage) }}</div>
                      <div class="object-card-meta">{{ getObjectIdentifier(item.userMessage) }}</div>
                      <div class="object-card-meta">
                        <span v-if="item.userMessage.objectType === 'order' && item.userMessage.payload.status" class="status-badge" :class="getStatusClass(item.userMessage.payload.status)">{{ item.userMessage.payload.status }}</span>
                        <span v-else>{{ getObjectSummary(item.userMessage) }}</span>
                      </div>
                      <div class="object-card-price">{{ getObjectAmount(item.userMessage) }}</div>
                    </div>
                  </template>
                  <template v-else>
                    <p>{{ item.userMessage.text }}</p>
                  </template>
                </div>
              </div>

              <!-- 客服回复区域 -->
              <div v-if="item.botMessages.length > 0" class="turn-section bot-section">
                <div class="section-header">
                  <div class="avatar-wrapper service-avatar">
                    <img :src="customerService.avatar" class="avatar" />
                    <span class="status-dot"></span>
                  </div>
                  <div class="agent-info">
                    <span class="agent-name">{{ customerService.name }}</span>
                    <span class="agent-label">{{ customerService.title }}</span>
                  </div>
                </div>
                <div class="bot-messages">
                  <div
                    v-for="(botMsg, msgIndex) in item.botMessages"
                    :key="msgIndex"
                    class="turn-bubble bot-bubble"
                  >
                    <template v-if="botMsg.type === 'object'">
                      <div class="object-card" :class="`object-card-${botMsg.objectType}`">
                        <div class="object-card-badge">
                          {{ botMsg.objectType === 'order' ? '订单对象' : '商品对象' }}
                        </div>
                        <img
                          v-if="botMsg.type === 'object' && botMsg.payload.cover_url"
                          :src="botMsg.payload.cover_url"
                          :alt="getObjectTitle(botMsg)"
                          class="object-card-image"
                          @error="$event.target.style.display='none'"
                        />
                        <div class="object-card-title">{{ getObjectTitle(botMsg) }}</div>
                        <div class="object-card-meta">{{ getObjectIdentifier(botMsg) }}</div>
                        <div class="object-card-meta">
                          <span v-if="botMsg.objectType === 'order' && botMsg.payload.status" class="status-badge" :class="getStatusClass(botMsg.payload.status)">{{ botMsg.payload.status }}</span>
                          <span v-else>{{ getObjectSummary(botMsg) }}</span>
                        </div>
                        <div class="object-card-price">{{ getObjectAmount(botMsg) }}</div>
                      </div>
                    </template>
                    <template v-else>
                      <div class="bot-text-row">
                        <p>{{ botMsg.text }}</p>
                        <div class="bot-actions">
                          <button type="button" class="tts-button"
                            :class="{ 'tts-loading': ttsState[botMsg.id] === 'loading', 'tts-playing': ttsState[botMsg.id] === 'playing' }"
                            :disabled="ttsState[botMsg.id] === 'loading'"
                            :title="ttsState[botMsg.id] === 'playing' ? '正在播放...' : '语音播报'"
                            @click.stop="playTts(botMsg)">
                            <span v-if="ttsState[botMsg.id] === 'loading'" class="tts-spinner"></span>
                            <span v-else-if="ttsState[botMsg.id] === 'playing'" class="tts-bars">
                              <span></span><span></span><span></span>
                            </span>
                            <span v-else>🔈</span>
                          </button>
                          <button type="button" class="copy-button"
                            :class="{ 'copy-done': copyState[botMsg.id] }"
                            :title="copyState[botMsg.id] ? '已复制' : '复制文字'"
                            @click.stop="copyBotText(botMsg)">
                            <span v-if="copyState[botMsg.id]">✓</span>
                            <span v-else>📋</span>
                          </button>
                        </div>
                      </div>
                    </template>
                    <div v-if="botMsg.suggestions && botMsg.suggestions.length > 0" class="suggestion-chips">
                      <button
                        v-for="sug in botMsg.suggestions"
                        :key="sug"
                        type="button"
                        class="suggestion-chip"
                        :disabled="isSending"
                        @click.stop="sendSuggestion(sug)"
                      >{{ sug }}</button>
                    </div>
                  </div>
                </div>
              </div>
            </div>
          </template>
        </section>

        <div v-if="isSending" class="typing-indicator">
          <div class="typing-avatar">
            <img :src="customerService.avatar" class="avatar-small" alt="老三" />
          </div>
          <div class="typing-bubble">
            <span class="typing-dots">
              <span></span><span></span><span></span>
            </span>
            <span class="typing-label">老三正在输入...</span>
          </div>
        </div>

        <p v-if="errorMessage" class="error-message">
          {{ errorMessage }}
        </p>

        <form class="composer" @submit.prevent="sendTextMessage">
          <input
            v-model="draftMessage"
            type="text"
            placeholder="请输入咨询内容..."
            :disabled="isSending"
          />
          <button type="submit" :disabled="isSending || !draftMessage.trim()">
            {{ isSending ? '发送中...' : '发送' }}
          </button>
        </form>
      </div>

      <div class="right-column">
        <!-- 数据概览：取自现有订单/商品数据，无新增后端请求 -->
        <section class="stats-card">
          <h2 class="stats-title">数据概览</h2>
          <div class="stats-grid">
            <div class="stat-tile is-teal">
              <span class="stat-number">{{ isLoadingSidebar ? '…' : orders.length }}</span>
              <span class="stat-label">订单</span>
            </div>
            <div class="stat-tile is-warm">
              <span class="stat-number">{{ isLoadingSidebar ? '…' : products.length }}</span>
              <span class="stat-label">商品</span>
            </div>
          </div>
        </section>

        <aside class="sidebar">
        <div class="sidebar-header">
          <h2>业务对象</h2>
        </div>

        <div class="tabs">
          <button
            type="button"
            class="tab-button"
            :class="{ active: activeTab === 'orders' }"
            @click="activeTab = 'orders'"
          >
            订单
          </button>
          <button
            type="button"
            class="tab-button"
            :class="{ active: activeTab === 'products' }"
            @click="activeTab = 'products'"
          >
            商品
          </button>
        </div>

        <p v-if="sidebarError" class="sidebar-error">{{ sidebarError }}</p>

        <div v-if="activeTab === 'orders'" class="sidebar-list">
          <div v-if="!orders.length && !isLoadingSidebar" class="sidebar-empty">
            暂无订单数据
          </div>

          <article v-for="order in orders" :key="order.order_id" class="sidebar-card">
            <div class="card-image-wrapper">
              <img
                v-if="order.cover_url"
                :src="order.cover_url"
                :alt="order.title"
                class="card-image"
                @error="$event.target.style.display='none'"
              />
              <div v-else class="card-image-placeholder">📦</div>
            </div>
            <div class="card-top">
              <div class="card-title">{{ order.title }}</div>
              <div class="card-amount">{{ formatAmount(order.amount) }}</div>
            </div>
            <div class="card-meta">订单号：{{ order.order_id }}</div>
            <div class="card-meta">
              <span class="status-badge" :class="getStatusClass(order.status)">{{ order.status }}</span>
            </div>
            <button
              type="button"
              class="secondary-button full-width"
              :disabled="isSending"
              @click="sendOrder(order)"
            >
              发送订单
            </button>
          </article>
        </div>

        <div v-else class="sidebar-list">
          <div v-if="!products.length && !isLoadingSidebar" class="sidebar-empty">
            暂无商品数据
          </div>

          <article v-for="product in products" :key="product.product_id" class="sidebar-card">
            <div class="card-image-wrapper">
              <img
                v-if="product.cover_url"
                :src="product.cover_url"
                :alt="product.title"
                class="card-image"
                @error="$event.target.style.display='none'"
              />
              <div v-else class="card-image-placeholder">🛍️</div>
            </div>
            <div class="card-top">
              <div class="card-title">{{ product.title }}</div>
              <div class="card-amount">{{ formatAmount(product.price) }}</div>
            </div>
            <div class="card-meta">商品号：{{ product.product_id }}</div>
            <div class="card-meta">商品信息：最近浏览 / 购买商品</div>
            <button
              type="button"
              class="secondary-button full-width"
              :disabled="isSending"
              @click="sendProduct(product)"
            >
              发送商品
            </button>
          </article>
        </div>
      </aside>
      </div>
    </div>
  </div>
</template>

<style scoped>
:global(*) {
  box-sizing: border-box;
}

:global(:root) {
  /* ── Palette（清透浅色） ── */
  --color-bg-deep: #f2f6f7;
  --color-bg-mid: #ffffff;
  --color-bg-surface: #f2f6f7;
  /* Light frosted glass — 半透明白面板，浮于浅色背景之上 */
  --color-surface: rgba(255, 255, 255, 0.86);
  --color-surface-hover: rgba(255, 255, 255, 0.97);
  --color-surface-dim: rgba(250, 252, 252, 0.72);
  --color-surface-raised: rgba(244, 248, 248, 0.92);
  --color-surface-field: #ffffff;
  /* Dark text on light surfaces */
  --color-text-primary: #14302e;
  --color-text-secondary: #5c7270;
  --color-text-muted: #8fa3a1;
  --color-text-inverse: #ffffff;
  /* Accent — teal */
  --color-accent: #0d9488;
  --color-accent-strong: #0f766e;
  --color-accent-soft: rgba(13, 148, 136, 0.12);
  --color-accent-glow: rgba(13, 148, 136, 0.18);
  --color-accent-soft-bg: rgba(13, 148, 136, 0.06);
  /* Warm — amber（货币色） */
  --color-warm: #d97706;
  --color-warm-strong: #b45309;
  --color-warm-soft: rgba(217, 119, 6, 0.12);
  --color-warm-glow: rgba(217, 119, 6, 0.16);
  --color-warm-soft-bg: rgba(217, 119, 6, 0.06);
  /* Semantic */
  --color-success: #16a34a;
  --color-success-soft: rgba(22, 163, 74, 0.12);
  --color-info: #0284c7;
  --color-info-soft: rgba(2, 132, 199, 0.10);
  --color-danger: #e11d48;
  --color-danger-soft: rgba(225, 29, 72, 0.10);
  /* Borders — subtle ink lines on white glass */
  --color-border: rgba(20, 48, 46, 0.10);
  --color-border-light: rgba(20, 48, 46, 0.06);
  --color-border-strong: rgba(20, 48, 46, 0.16);
  /* ── Radii ── */
  --radius-sm: 10px;
  --radius-md: 16px;
  --radius-lg: 24px;
  --radius-xl: 28px;
  --radius-full: 9999px;
  /* ── Shadows（浅色主题用柔和灰影 + 极淡主色辉光） ── */
  --shadow-xs: 0 1px 2px rgba(20, 48, 46, 0.05);
  --shadow-sm: 0 2px 8px rgba(20, 48, 46, 0.06);
  --shadow-md: 0 8px 24px rgba(20, 48, 46, 0.08);
  --shadow-lg: 0 16px 40px rgba(20, 48, 46, 0.10);
  --shadow-glow-teal: 0 8px 32px rgba(13, 148, 136, 0.08), 0 2px 8px rgba(13, 148, 136, 0.04);
  --shadow-glow-amber: 0 8px 32px rgba(217, 119, 6, 0.07), 0 2px 8px rgba(217, 119, 6, 0.03);
  --shadow-inner-glow: inset 0 1px 0 rgba(255, 255, 255, 0.9);
  /* ── Transitions ── */
  --ease-out-expo: cubic-bezier(0.16, 1, 0.3, 1);
  --ease-out-back: cubic-bezier(0.34, 1.56, 0.64, 1);
  --ease-in-out: cubic-bezier(0.65, 0, 0.35, 1);
  --duration-fast: 150ms;
  --duration-base: 250ms;
  --duration-slow: 400ms;
}

:global(body) {
  margin: 0;
  font-family: system-ui, -apple-system, "Segoe UI", "PingFang SC", "HarmonyOS Sans SC", "MiSans", "Microsoft YaHei", sans-serif;
  background: var(--color-bg-deep);
  color: var(--color-text-primary);
  -webkit-font-smoothing: antialiased;
  -moz-osx-font-smoothing: grayscale;
}

:global(button),
:global(input) {
  font: inherit;
}

:global(#app) {
  min-height: 100vh;
}

.app-shell {
  min-height: 100vh;
  padding: 24px;
  position: relative;
  overflow: hidden;
  background: linear-gradient(180deg, #f8fbfb 0%, #eef4f5 45%, #f4f8f8 100%);
}

/* ── 柔光斑背景：三团缓慢流动的低对比光晕，替代原粒子系统 ── */
/* 柔光斑 A — 青绿，左上 */
.app-shell::before {
  content: "";
  position: absolute;
  z-index: 0;
  pointer-events: none;
  width: 900px;
  height: 900px;
  top: -380px;
  left: -300px;
  border-radius: 50%;
  background: radial-gradient(circle, rgba(13, 148, 136, 0.16) 0%, rgba(45, 212, 191, 0.07) 40%, transparent 72%);
  animation: orb1 26s var(--ease-in-out) infinite;
}

/* 柔光斑 B — 天青，右下 */
.app-shell::after {
  content: "";
  position: absolute;
  z-index: 0;
  pointer-events: none;
  width: 760px;
  height: 760px;
  bottom: -320px;
  right: -240px;
  border-radius: 50%;
  background: radial-gradient(circle, rgba(2, 132, 199, 0.10) 0%, rgba(56, 189, 248, 0.05) 42%, transparent 72%);
  animation: orb2 30s var(--ease-in-out) infinite;
}

/* 柔光斑 C — 暖琥珀，中部偏右，极淡（呼应货币色） */
.workspace::before {
  content: "";
  position: fixed;
  z-index: -1;
  pointer-events: none;
  width: 620px;
  height: 620px;
  top: 32%;
  right: -180px;
  border-radius: 50%;
  background: radial-gradient(circle, rgba(217, 119, 6, 0.08) 0%, rgba(245, 158, 11, 0.04) 45%, transparent 72%);
  animation: orb1 34s var(--ease-in-out) infinite reverse;
}

@keyframes orb1 {
  0%, 100% { transform: translate(0, 0) scale(1); opacity: 0.9; }
  50% { transform: translate(70px, 50px) scale(1.12); opacity: 1; }
}
@keyframes orb2 {
  0%, 100% { transform: translate(0, 0) scale(1); opacity: 0.85; }
  50% { transform: translate(-60px, -40px) scale(1.1); opacity: 1; }
}

.workspace {
  width: min(1760px, 100%);
  margin: 0 auto;
  display: grid;
  grid-template-columns: 330px minmax(0, 1fr) 350px;
  gap: 20px;
  align-items: start;
  position: relative;
  z-index: 1;
}

.chat-card,
.sidebar,
.stats-card {
  background: var(--color-surface);
  backdrop-filter: blur(24px) saturate(1.15);
  -webkit-backdrop-filter: blur(24px) saturate(1.15);
  border: 1px solid var(--color-border);
  border-radius: var(--radius-lg);
  overflow: hidden;
  transition: border-color var(--duration-slow) var(--ease-in-out), box-shadow var(--duration-slow) var(--ease-in-out);
}
.chat-card {
  display: flex;
  flex-direction: column;
  min-height: calc(100vh - 132px);
  height: calc(100vh - 132px);
  box-shadow: var(--shadow-glow-teal), var(--shadow-lg), var(--shadow-inner-glow);
}
.chat-card:hover {
  border-color: rgba(13, 148, 136, 0.22);
}

/* ── 右列：数据概览 + 业务对象（锁定视口高度，列表内部滚动） ── */
.right-column {
  display: flex;
  flex-direction: column;
  gap: 20px;
  height: calc(100vh - 132px);
  min-height: 0;
}
.stats-card {
  flex-shrink: 0;
  padding: 16px 20px 18px;
  box-shadow: var(--shadow-lg), var(--shadow-inner-glow);
}
.stats-grid {
  display: grid;
  grid-template-columns: 1fr 1fr;
  gap: 12px;
  margin-top: 12px;
}
.stat-tile {
  display: flex;
  flex-direction: column;
  gap: 2px;
  padding: 12px 14px;
  border-radius: var(--radius-md);
  background: var(--color-surface-field);
  border: 1px solid var(--color-border-light);
}
.stat-number {
  font-size: 22px;
  font-weight: 700;
  line-height: 1.2;
  font-variant-numeric: tabular-nums;
}
.stat-tile.is-teal .stat-number {
  color: var(--color-accent-strong);
}
.stat-tile.is-warm .stat-number {
  color: var(--color-warm-strong);
}
.stat-label {
  font-size: 12px;
  color: var(--color-text-muted);
}
.sidebar {
  flex: 1;
  min-height: 0;
  display: flex;
  flex-direction: column;
  overflow: hidden;
  box-shadow: var(--shadow-lg), var(--shadow-inner-glow);
}
.sidebar:hover {
  border-color: var(--color-border-strong);
}

/* ── 顶部全局栏 ─────────────────────────────────────────── */
.topbar {
  position: relative;
  z-index: 1;
  display: flex;
  align-items: center;
  gap: 18px;
  width: min(1760px, 100%);
  height: 64px;
  margin: 0 auto 20px;
  padding: 0 20px;
  background: var(--color-surface);
  backdrop-filter: blur(24px) saturate(1.15);
  -webkit-backdrop-filter: blur(24px) saturate(1.15);
  border: 1px solid var(--color-border);
  border-radius: var(--radius-lg);
  box-shadow: var(--shadow-md), var(--shadow-inner-glow);
}

.topbar-brand {
  display: flex;
  align-items: center;
  gap: 12px;
  flex-shrink: 0;
}

.topbar-logo {
  position: relative;
  width: 34px;
  height: 34px;
  border-radius: 12px;
  background: linear-gradient(135deg, var(--color-accent), var(--color-accent-strong));
  box-shadow: 0 4px 14px var(--color-accent-glow);
}

.topbar-logo::after {
  content: "";
  position: absolute;
  inset: 11px;
  border-radius: 50%;
  background: #eafffb;
}

.topbar-brand h1 {
  margin: 0;
  font-size: 18px;
  line-height: 1.2;
  letter-spacing: -0.02em;
  white-space: nowrap;
  background: linear-gradient(135deg, #14302e 0%, var(--color-accent) 100%);
  -webkit-background-clip: text;
  -webkit-text-fill-color: transparent;
  background-clip: text;
}

.topbar-service {
  display: flex;
  align-items: center;
  gap: 10px;
  padding: 5px 14px 5px 6px;
  background: var(--color-surface-raised);
  border: 1px solid var(--color-border);
  border-radius: var(--radius-md);
}

.topbar-service-avatar-wrapper {
  position: relative;
  flex-shrink: 0;
}

.topbar-service-avatar {
  display: block;
  width: 36px;
  height: 36px;
  border-radius: 50%;
  object-fit: cover;
  padding: 2px;
  background: conic-gradient(var(--color-accent), #0d9488, #5eead4, var(--color-accent));
}

.status-indicator {
  position: absolute;
  bottom: 0;
  right: 0;
  width: 11px;
  height: 11px;
  background: var(--color-success);
  border: 2px solid var(--color-bg-mid);
  border-radius: 50%;
  animation: pulse 2s infinite;
}

.topbar-service-info {
  display: flex;
  flex-direction: column;
  line-height: 1.35;
}

.topbar-service-name {
  font-size: 13px;
  font-weight: 600;
  color: var(--color-text-primary);
  white-space: nowrap;
}

.topbar-service-status {
  display: flex;
  align-items: center;
  gap: 4px;
  font-size: 11.5px;
  color: var(--color-success);
}

.topbar-service-status::before {
  content: '';
  width: 6px;
  height: 6px;
  background: var(--color-success);
  border-radius: 50%;
}

.topbar-controls {
  display: flex;
  align-items: center;
  gap: 10px;
  margin-left: auto;
}

.topbar-field {
  display: flex;
  align-items: center;
  gap: 8px;
}

.topbar-field span {
  font-size: 12px;
  color: var(--color-text-muted);
  white-space: nowrap;
}

.topbar-field input {
  width: 132px;
  min-height: 38px;
  padding: 8px 12px;
  border: 1px solid var(--color-border-strong);
  border-radius: var(--radius-md);
  background: var(--color-surface-field);
  color: var(--color-text-primary);
  font-size: 13.5px;
  line-height: 1.4;
  transition: border-color var(--duration-fast) var(--ease-in-out), box-shadow var(--duration-fast) var(--ease-in-out);
}

.topbar-field input::placeholder {
  color: var(--color-text-muted);
}

.topbar-field input:focus {
  outline: none;
  border-color: var(--color-accent);
  box-shadow: 0 0 0 3px var(--color-accent-soft);
}

.topbar .secondary-button {
  min-height: 38px;
  padding: 7px 14px;
  font-size: 13px;
}

.topbar .clear-button {
  flex-shrink: 0;
}

/* ── 面板标题（业务对象 / 数据概览） ── */
.sidebar-header {
  padding: 24px 24px 16px;
  border-bottom: 1px solid var(--color-border-light);
}

.sidebar-header h2,
.stats-title {
  margin: 0;
  font-size: 16px;
  line-height: 1.3;
  letter-spacing: 0.02em;
  color: var(--color-text-primary);
}

/* 客服信息（Turn 卡片中 bot 头像容器仍使用 .service-avatar） */
.service-avatar {
  width: 48px;
  height: 48px;
  border-radius: 50%;
  object-fit: cover;
  padding: 3px;
  background: conic-gradient(var(--color-accent), #0d9488, #5eead4, var(--color-accent));
  animation: avatarSpin 6s linear infinite;
  box-shadow: 0 0 20px var(--color-accent-glow), 0 4px 12px var(--color-success-soft);
}
@keyframes avatarSpin {
  to { transform: rotate(360deg); }
}

.clear-button {
  display: inline-flex;
  align-items: center;
  gap: 6px;
  padding: 8px 16px;
  border: 1px solid var(--color-border);
  border-radius: var(--radius-md);
  background: var(--color-surface-raised);
  color: var(--color-text-secondary);
  font-size: 13px;
  font-weight: 500;
  cursor: pointer;
  transition: all var(--duration-base) var(--ease-out-expo);
  white-space: nowrap;
}
.clear-button:hover {
  background: rgba(225, 29, 72, 0.08);
  border-color: var(--color-danger);
  color: var(--color-danger);
  transform: translateY(-1px);
  box-shadow: 0 4px 18px var(--color-danger-soft);
}

.composer input {
  width: 100%;
  min-width: 0;
  min-height: 46px;
  padding: 11px 14px;
  border: 1px solid var(--color-border-strong);
  border-radius: var(--radius-md);
  background: var(--color-surface-field);
  color: var(--color-text-primary);
  font-size: 15px;
  line-height: 1.4;
  transition: border-color var(--duration-fast) var(--ease-in-out), box-shadow var(--duration-fast) var(--ease-in-out);
}
.composer input::placeholder {
  color: var(--color-text-muted);
}
.composer input:focus {
  outline: none;
  border-color: var(--color-accent);
  box-shadow: 0 0 0 3px var(--color-accent-soft);
}

/* ── 聊天卡片区头（轻量） ── */
.chat-subheader {
  display: flex;
  align-items: center;
  justify-content: space-between;
  gap: 12px;
  flex-shrink: 0;
  padding: 14px 24px;
  border-bottom: 1px solid var(--color-border-light);
  background: var(--color-surface-dim);
}

.chat-subheader-title {
  font-size: 14px;
  font-weight: 600;
  letter-spacing: 0.02em;
  color: var(--color-text-primary);
}

.chat-subheader-hint {
  font-size: 12px;
  color: var(--color-text-muted);
}

.messages {
  flex: 1;
  min-height: 0;
  overflow-y: auto;
  scrollbar-gutter: stable;
  overscroll-behavior: contain;
  padding: 20px;
  display: flex;
  flex-direction: column;
  gap: 20px;
}

/* ── 滚动区域：细窄滚动条，悬停转为青绿 ── */
.messages,
.sidebar-list {
  scrollbar-width: thin;
  scrollbar-color: rgba(20, 48, 46, 0.18) transparent;
}
.messages::-webkit-scrollbar,
.sidebar-list::-webkit-scrollbar {
  width: 8px;
}
.messages::-webkit-scrollbar-track,
.sidebar-list::-webkit-scrollbar-track {
  background: transparent;
}
.messages::-webkit-scrollbar-thumb,
.sidebar-list::-webkit-scrollbar-thumb {
  background: rgba(20, 48, 46, 0.16);
  border-radius: var(--radius-full);
  border: 2px solid transparent;
  background-clip: content-box;
}
.messages::-webkit-scrollbar-thumb:hover,
.sidebar-list::-webkit-scrollbar-thumb:hover {
  background: rgba(13, 148, 136, 0.42);
  background-clip: content-box;
}

/* Turn 卡片样式 */
.turn-card {
  flex-shrink: 0;
  display: flex;
  flex-direction: column;
  gap: 16px;
  padding: 20px 24px;
  background: var(--color-surface-raised);
  border: 1px solid var(--color-border);
  border-radius: var(--radius-lg);
  transition: all var(--duration-base) var(--ease-out-expo);
  position: relative;
  overflow: hidden;
  animation: msgEnter 0.4s var(--ease-out-back) both;
}
@keyframes msgEnter {
  from { opacity: 0; transform: translateY(24px) scale(0.98); }
  to { opacity: 1; transform: translateY(0) scale(1); }
}
.turn-card::before {
  content: "";
  position: absolute;
  top: 0; left: -100%;
  width: 100%; height: 100%;
  background: linear-gradient(105deg, transparent 40%, rgba(13, 148, 136, 0.05) 50%, transparent 60%);
  transition: left 0.5s ease;
  pointer-events: none;
  z-index: 2;
}
.turn-card:hover::before {
  left: 100%;
}
.turn-card:hover {
  background: var(--color-surface-hover);
  border-color: var(--color-border-strong);
  box-shadow: var(--shadow-md), 0 0 32px rgba(13, 148, 136, 0.10);
  transform: translateY(-2px);
}

.turn-header {
  display: flex;
  align-items: center;
  gap: 10px;
  padding-bottom: 12px;
  border-bottom: 1px dashed var(--color-border);
}

.turn-badge {
  display: inline-flex;
  align-items: center;
  padding: 4px 12px;
  background: linear-gradient(135deg, var(--color-accent), #0d9488);
  color: #ffffff;
  font-size: 12px;
  font-weight: 600;
  border-radius: var(--radius-sm);
  box-shadow: 0 2px 12px var(--color-accent-glow);
}

.turn-label {
  font-size: 12px;
  color: var(--color-text-muted);
  font-weight: 500;
}

.turn-section {
  display: flex;
  flex-direction: column;
  gap: 10px;
}

.section-header {
  display: flex;
  align-items: center;
  gap: 12px;
  font-size: 13px;
  font-weight: 600;
}

/* 头像样式 */
.avatar-wrapper {
  position: relative;
  flex-shrink: 0;
}

.avatar {
  width: 42px;
  height: 42px;
  border-radius: 50%;
  object-fit: cover;
  border: 2px solid #e5e7eb;
  background: #f3f4f6;
  transition: all var(--duration-base) var(--ease-out-expo);
}

.user-avatar .avatar {
  border: 3px solid transparent;
  background: linear-gradient(#ffffff, #ffffff) padding-box,
              linear-gradient(135deg, var(--color-accent), #0d9488) border-box;
  box-shadow: 0 2px 14px var(--color-accent-soft);
}

.service-avatar .avatar {
  border-color: var(--color-success);
  box-shadow: 0 2px 10px var(--color-success-soft);
}

.status-dot {
  position: absolute;
  bottom: 2px;
  right: 2px;
  width: 12px;
  height: 12px;
  background: var(--color-success);
  border: 2px solid #ffffff;
  border-radius: 50%;
  animation: pulse 2s infinite;
}

@keyframes pulse {
  0%, 100% {
    opacity: 1;
    transform: scale(1);
  }
  50% {
    opacity: 0.65;
    transform: scale(1.12);
  }
}

.agent-info {
  display: flex;
  flex-direction: column;
  gap: 2px;
}

.agent-name {
  font-size: 15px;
  font-weight: 600;
  color: var(--color-text-primary);
}

.agent-label {
  font-size: 12px;
  color: var(--color-text-muted);
  font-weight: 500;
}

.user-section .agent-name {
  color: var(--color-accent);
}

.bot-section .agent-name {
  color: var(--color-success);
}

.turn-bubble {
  padding: 14px 18px;
  border-radius: var(--radius-md);
  max-width: 100%;
}

.user-bubble {
  background: linear-gradient(135deg, var(--color-accent), var(--color-accent-strong));
  border: 1px solid transparent;
  color: #ffffff;
  box-shadow: 0 4px 18px var(--color-accent-glow);
  margin-left: auto;
  max-width: 85%;
}

.bot-bubble {
  background: #f6fafa;
  border: 1px solid var(--color-border);
  color: var(--color-text-primary);
  box-shadow: var(--shadow-xs);
}

.bot-messages {
  display: flex;
  flex-direction: column;
  gap: 10px;
}

.turn-bubble p {
  margin: 0;
  font-size: 15px;
  line-height: 1.7;
  white-space: pre-wrap;
  word-break: break-word;
}

.user-bubble p {
  color: #ffffff;
}

/* 历史消息分隔线 */
.history-divider {
  flex-shrink: 0;
  display: flex;
  align-items: center;
  gap: 14px;
  color: var(--color-text-muted);
  font-size: 13px;
  padding: 8px 0;
}

.history-divider::before,
.history-divider::after {
  content: "";
  flex: 1;
  height: 1px;
  background: var(--color-border-strong);
}

.history-divider span {
  padding: 6px 14px;
  border-radius: var(--radius-full);
  background: var(--color-surface-raised);
  border: 1px solid var(--color-border);
  font-size: 12px;
}

.welcome {
  flex-shrink: 0;
  flex: 1;
  display: flex;
  align-items: center;
  justify-content: center;
  padding: 20px;
}
.welcome-card {
  position: relative;
  max-width: 480px;
  width: 100%;
  padding: 44px 40px;
  background: var(--color-surface-raised);
  border: 1px solid var(--color-border);
  border-radius: var(--radius-lg);
  text-align: center;
  box-shadow: var(--shadow-glow-teal), var(--shadow-lg);
  overflow: hidden;
  animation: welcomeFloat 0.6s var(--ease-out-back);
}
@keyframes welcomeFloat {
  from { opacity: 0; transform: translateY(36px) scale(0.94); }
  to { opacity: 1; transform: translateY(0) scale(1); }
}
.welcome-glow {
  position: absolute;
  top: -100px; left: 50%; transform: translateX(-50%);
  width: 350px; height: 350px;
  background: radial-gradient(circle, rgba(45,212,191,0.08) 0%, rgba(45,212,191,0.02) 45%, transparent 70%);
  pointer-events: none;
}
.welcome-avatar-wrapper {
  position: relative;
  display: inline-block;
  margin-bottom: 20px;
}
.welcome-avatar {
  width: 88px; height: 88px;
  border-radius: 50%;
  padding: 4px;
  background: conic-gradient(var(--color-accent), #0d9488, #5eead4, var(--color-accent));
  animation: avatarSpin 6s linear infinite;
  box-shadow: 0 0 36px var(--color-accent-glow);
}
.welcome-status-pulse {
  position: absolute;
  bottom: 6px; right: 6px;
  width: 18px; height: 18px;
  background: var(--color-success);
  border: 3px solid var(--color-bg-mid);
  border-radius: 50%;
  animation: pulse 2s infinite;
  box-shadow: 0 0 16px rgba(22, 163, 74, 0.35);
}
.welcome-greeting {
  margin: 0 0 8px;
  font-size: 26px;
  font-weight: 700;
  background: linear-gradient(135deg, #14302e, var(--color-accent));
  -webkit-background-clip: text;
  -webkit-text-fill-color: transparent;
  background-clip: text;
}
.welcome-subtitle {
  margin: 0 0 28px;
  color: var(--color-text-secondary);
  font-size: 15px;
}
.welcome-chips {
  display: flex;
  flex-wrap: wrap;
  gap: 10px;
  justify-content: center;
  margin-bottom: 28px;
}
.welcome-chip {
  padding: 10px 20px;
  border: 1px solid rgba(13, 148, 136, 0.22);
  border-radius: var(--radius-full);
  background: var(--color-accent-soft-bg);
  color: var(--color-accent);
  font-size: 14px;
  font-weight: 500;
  cursor: pointer;
  transition: all var(--duration-base) var(--ease-out-expo);
}
.welcome-chip:hover:not(:disabled) {
  background: var(--color-accent-soft);
  border-color: var(--color-accent);
  transform: translateY(-2px);
  box-shadow: 0 6px 18px var(--color-accent-glow);
}
.welcome-chip:disabled {
  opacity: 0.4;
  cursor: not-allowed;
}
.welcome-features {
  display: flex;
  flex-wrap: wrap;
  gap: 12px;
  justify-content: center;
  margin: 0;
  color: var(--color-text-muted);
  font-size: 13px;
}

.sidebar-empty {
  margin: auto;
  max-width: 420px;
  color: var(--color-text-muted);
  text-align: center;
  line-height: 1.7;
}

.typing-indicator {
  flex-shrink: 0;
  display: flex;
  align-items: flex-end;
  gap: 10px;
  padding: 0 20px;
  animation: msgEnter 0.3s var(--ease-out-expo);
}
.avatar-small {
  width: 34px; height: 34px;
  border-radius: 50%;
  object-fit: cover;
  border: 2px solid var(--color-success);
  box-shadow: 0 0 12px rgba(22, 163, 74, 0.22);
}
.typing-bubble {
  display: flex;
  align-items: center;
  gap: 8px;
  padding: 12px 18px;
  background: var(--color-surface-raised);
  border: 1px solid var(--color-border);
  border-radius: 20px 20px 20px 6px;
  box-shadow: var(--shadow-sm);
}
.typing-dots {
  display: flex;
  gap: 4px;
  align-items: center;
}
.typing-dots span {
  width: 8px; height: 8px;
  border-radius: 50%;
  background: var(--color-accent);
  animation: dotBounce 1.2s ease-in-out infinite;
}
.typing-dots span:nth-child(1) { animation-delay: 0s; }
.typing-dots span:nth-child(2) { animation-delay: 0.2s; }
.typing-dots span:nth-child(3) { animation-delay: 0.4s; }
@keyframes dotBounce {
  0%, 60%, 100% { transform: translateY(0); opacity: 0.3; }
  30% { transform: translateY(-8px); opacity: 1; }
}
.typing-label {
  font-size: 13px;
  color: var(--color-text-muted);
}

/* ── 对象卡片（聊天区订单/商品卡片） ─────────────────────── */
.object-card {
  display: flex;
  flex-direction: column;
  gap: 6px;
  padding: 12px;
  min-width: 220px;
  max-width: 340px;
  border: 1px solid var(--color-border);
  border-radius: var(--radius-md);
  background: var(--color-surface-field);
}
.object-card-badge {
  align-self: flex-start;
  padding: 2px 10px;
  border-radius: var(--radius-full);
  font-size: 11px;
  font-weight: 600;
  letter-spacing: 0.02em;
  background: var(--color-accent-soft);
  border: 1px solid rgba(13, 148, 136, 0.28);
  color: var(--color-accent);
}
.object-card-title {
  font-size: 14px;
  font-weight: 600;
  line-height: 1.5;
  color: var(--color-text-primary);
}
.object-card-meta {
  font-size: 12.5px;
  line-height: 1.6;
  color: var(--color-text-secondary);
}
.object-card-price {
  font-size: 15px;
  font-weight: 700;
  color: var(--color-warm-strong);
}

/* 用户气泡中的对象卡片：半透明白浮于青绿气泡上 */
.user-bubble .object-card {
  background: rgba(255, 255, 255, 0.12);
  border-color: rgba(255, 255, 255, 0.22);
}
.user-bubble .object-card-title {
  color: #ffffff;
}
.user-bubble .object-card-meta {
  color: rgba(255, 255, 255, 0.78);
}
.user-bubble .object-card-price {
  color: #fde68a;
}
.user-bubble .object-card-badge {
  background: rgba(255, 255, 255, 0.2);
  border-color: rgba(255, 255, 255, 0.3);
  color: #ffffff;
}

/* ── 状态徽章 ────────────────────────────────────────────── */
.status-badge {
  display: inline-flex;
  align-items: center;
  padding: 3px 12px;
  border-radius: var(--radius-full);
  font-size: 12px;
  font-weight: 600;
  letter-spacing: 0.02em;
}
.status-warning {
  background: var(--color-warm-soft);
  color: var(--color-warm-strong);
  border: 1px solid rgba(217, 119, 6, 0.28);
}
.status-info {
  background: var(--color-info-soft);
  color: var(--color-info);
  border: 1px solid rgba(2, 132, 199, 0.25);
}
.status-success {
  background: var(--color-success-soft);
  color: var(--color-success);
  border: 1px solid rgba(22, 163, 74, 0.25);
}
.status-muted {
  background: rgba(20, 48, 46, 0.06);
  color: var(--color-text-muted);
  border: 1px solid rgba(20, 48, 46, 0.14);
}
.status-danger {
  background: var(--color-danger-soft);
  color: var(--color-danger);
  border: 1px solid rgba(225, 29, 72, 0.25);
}

/* ── 商品图片（侧边栏） ────────────────────────────────────── */
.card-image-wrapper {
  width: 100%;
  height: 140px;
  border-radius: var(--radius-sm);
  overflow: hidden;
  background: var(--color-surface-field);
  border: 1px solid var(--color-border-light);
  display: flex;
  align-items: center;
  justify-content: center;
}
.card-image {
  width: 100%;
  height: 100%;
  object-fit: cover;
  transition: transform var(--duration-base) var(--ease-out-expo);
}
.sidebar-card:hover .card-image {
  transform: scale(1.05);
}
.card-image-placeholder {
  font-size: 40px;
  opacity: 0.5;
}

/* ── 对象卡片图片（聊天区） ─────────────────────────────────── */
.object-card-image {
  width: 100%;
  height: 150px;
  object-fit: cover;
  border-radius: var(--radius-sm);
  margin-bottom: 8px;
  border: 1px solid var(--color-border-light);
  background: var(--color-surface-field);
}

.composer button,
.secondary-button,
.tab-button {
  min-height: 42px;
  padding: 9px 16px;
  border: 1px solid var(--color-border);
  border-radius: var(--radius-md);
  background: var(--color-surface);
  color: var(--color-text-primary);
  cursor: pointer;
  font-size: 14px;
  font-weight: 600;
  line-height: 1.2;
  transition:
    transform var(--duration-fast) var(--ease-out-expo),
    box-shadow var(--duration-fast) var(--ease-out-expo),
    background var(--duration-fast) var(--ease-in-out),
    border-color var(--duration-fast) var(--ease-in-out);
}

.composer button:hover:not(:disabled),
.secondary-button:hover:not(:disabled),
.tab-button:hover:not(:disabled) {
  transform: translateY(-1px);
  box-shadow: var(--shadow-sm);
}

.composer button:active:not(:disabled),
.secondary-button:active:not(:disabled),
.tab-button:active:not(:disabled) {
  transform: translateY(0);
}

.composer button:disabled,
.secondary-button:disabled {
  opacity: 0.55;
  cursor: not-allowed;
  transform: none;
  box-shadow: none;
}

.error-message,
.sidebar-error {
  margin: 0;
  padding: 0 24px 14px;
  color: var(--color-danger);
  font-size: 13px;
  font-weight: 500;
}

.composer {
  flex-shrink: 0;
  display: flex;
  align-items: stretch;
  gap: 12px;
  padding: 20px 24px;
  border-top: 1px solid var(--color-border-light);
  background: var(--color-surface-dim);
}

.composer button {
  min-width: 96px;
  padding-inline: 20px;
  background: linear-gradient(135deg, var(--color-accent), var(--color-accent-strong));
  border-color: transparent;
  color: #f0fdfa;
  box-shadow: 0 6px 18px var(--color-accent-glow);
}
.composer button:hover:not(:disabled) {
  box-shadow: 0 10px 26px var(--color-accent-glow);
  transform: translateY(-2px);
}

.tabs {
  display: flex;
  gap: 8px;
  padding: 16px 24px 12px;
  border-bottom: 1px solid var(--color-border-light);
}

.tab-button {
  min-width: 80px;
}

.tab-button.active {
  background: linear-gradient(135deg, var(--color-accent-strong), var(--color-accent));
  border-color: transparent;
  color: #f0fdfa;
  box-shadow: 0 4px 14px var(--color-accent-glow);
}

.sidebar-list {
  flex: 1;
  min-height: 0;
  overflow-y: auto;
  overscroll-behavior: contain;
  padding: 16px 24px 24px;
  display: flex;
  flex-direction: column;
  gap: 14px;
}

.sidebar-card {
  padding: 16px;
  border: 1px solid var(--color-border);
  border-radius: var(--radius-md);
  background: var(--color-surface-raised);
  display: flex;
  flex-direction: column;
  gap: 12px;
  transition: all var(--duration-base) var(--ease-out-expo);
}
.sidebar-card:hover {
  background: var(--color-surface-hover);
  border-color: rgba(13, 148, 136, 0.22);
  transform: translateY(-3px);
  box-shadow: var(--shadow-md);
}

.card-top {
  display: flex;
  gap: 12px;
  justify-content: space-between;
  align-items: flex-start;
}

.card-title {
  font-size: 15px;
  line-height: 1.5;
  color: var(--color-text-primary);
  font-weight: 600;
}

.card-amount {
  flex-shrink: 0;
  color: var(--color-warm-strong);
  font-weight: 700;
}

.card-meta {
  font-size: 14px;
  color: var(--color-text-secondary);
}

.bot-text-row { display: flex; align-items: flex-start; gap: 8px; }
.bot-text-row p { flex: 1; margin: 0; }
.bot-actions {
  display: flex; gap: 6px; flex-shrink: 0; align-items: center;
}
.tts-button, .copy-button {
  flex-shrink: 0; width: 32px; height: 32px; padding: 0;
  border: 1px solid var(--color-border-light); border-radius: 8px;
  background: var(--color-surface); cursor: pointer;
  font-size: 14px; display: inline-flex; align-items: center; justify-content: center;
  transition: all var(--duration-base) var(--ease-out-expo); color: var(--color-text-muted);
}
.tts-button:hover:not(:disabled), .copy-button:hover:not(:disabled) {
  background: var(--color-accent-soft); border-color: var(--color-accent); color: var(--color-accent-strong);
  transform: scale(1.1);
}
.tts-button:disabled, .copy-button:disabled { cursor: not-allowed; opacity: 0.65; }
.tts-button.tts-playing { background: var(--color-accent-soft); border-color: var(--color-accent); color: var(--color-accent-strong); }
.tts-bars {
  display: inline-flex; align-items: flex-end; gap: 3px; height: 16px;
}
.tts-bars span {
  width: 3px;
  background: var(--color-accent);
  border-radius: 2px;
  animation: barBounce 0.6s ease-in-out infinite;
}
.tts-bars span:nth-child(1) { height: 8px; animation-delay: 0s; }
.tts-bars span:nth-child(2) { height: 14px; animation-delay: 0.15s; }
.tts-bars span:nth-child(3) { height: 10px; animation-delay: 0.3s; }
@keyframes barBounce {
  0%, 100% { transform: scaleY(0.5); }
  50% { transform: scaleY(1); }
}
.tts-spinner {
  width: 14px; height: 14px;
  border: 2px solid var(--color-accent-soft); border-top-color: var(--color-accent);
  border-radius: 50%; animation: tts-spin 0.6s linear infinite;
}
@keyframes tts-spin { to { transform: rotate(360deg); } }
.copy-button.copy-done {
  background: var(--color-success-soft);
  border-color: var(--color-success);
  color: var(--color-success);
}

.suggestion-chips {
  display: flex;
  flex-wrap: wrap;
  gap: 8px;
  margin-top: 10px;
  padding-top: 10px;
  border-top: 1px solid var(--color-border-light);
}
.suggestion-chip {
  padding: 6px 14px;
  border: 1px solid rgba(13, 148, 136, 0.20);
  border-radius: var(--radius-full);
  background: var(--color-accent-soft-bg);
  color: var(--color-accent);
  font-size: 13px;
  font-weight: 500;
  cursor: pointer;
  transition: all var(--duration-base) var(--ease-out-expo);
}
.suggestion-chip:hover:not(:disabled) {
  background: var(--color-accent-soft);
  border-color: var(--color-accent);
  transform: translateY(-1px);
}
.suggestion-chip:disabled {
  opacity: 0.4;
  cursor: not-allowed;
}

.full-width {
  width: 100%;
}

.sidebar .secondary-button.full-width {
  min-height: 42px;
}

@media (max-width: 1180px) {
  .workspace {
    grid-template-columns: 1fr;
  }

  .topbar {
    height: auto;
    min-height: 0;
    flex-wrap: wrap;
    padding: 12px 16px;
    gap: 12px;
  }

  .topbar-controls {
    margin-left: 0;
    flex: 1;
  }

  .topbar-field {
    flex: 1;
  }

  .topbar-field input {
    width: 100%;
    flex: 1;
  }

  .chat-card,
  .right-column {
    min-height: auto;
    height: auto;
  }

  .sidebar {
    min-height: auto;
    height: auto;
  }
}

@media (max-width: 720px) {
  .app-shell {
    padding: 0;
  }

  .workspace {
    gap: 0;
  }

  .topbar {
    margin: 0 0 12px;
    border-radius: 0;
    border-left: none;
    border-right: none;
  }

  .chat-card,
  .sidebar,
  .stats-card,
  .right-column {
    min-height: auto;
    height: auto;
    border-radius: 0;
    border-left: none;
    border-right: none;
  }

  .right-column {
    gap: 12px;
    padding: 12px;
  }

  .chat-card {
    min-height: 100vh;
  }

  .composer {
    flex-direction: column;
    align-items: stretch;
  }
}
</style>
