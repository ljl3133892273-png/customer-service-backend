// ============================================================
// 魔珐星云数字人接入模块（独立文件，不侵入现有业务代码）
//
// 官方接入手册：https://xingyun3d.com/developers/52-183
// 核心流程：动态加载官方 SDK 脚本 → 创建 XmovAvatar 实例 →
//          init(初始化连接房间 + 资源下载) → speak(驱动数字人说话)
//
// 使用方式：
//   - 面板组件（DigitalHumanPanel.vue）调用 connectDigitalHuman / disconnectDigitalHuman
//   - App.vue 在收到客服后端响应后调用 notifyDigitalHuman(botMessages)
// ============================================================
import { reactive } from 'vue'

// 魔珐星云官方 SDK 脚本地址（保持 @latest 以获取最新特性，见官方手册"快速开始"）
const SDK_SCRIPT_URL =
  'https://media.xingyun3d.com/xingyun3d/general/litesdk/xmovAvatar@latest.js'

// 数字人服务网关（官方默认地址）
const GATEWAY_SERVER = 'https://nebula-agent.xingyun3d.com/user/v1/ttsa/session'

// 应用凭据：从前端目录 .env 读取（VITE_XMOV_APP_ID / VITE_XMOV_APP_SECRET）
const APP_ID = import.meta.env.VITE_XMOV_APP_ID ?? ''
const APP_SECRET = import.meta.env.VITE_XMOV_APP_SECRET ?? ''

// 数字人运行状态（供面板组件响应式展示）
export const digitalHumanState = reactive({
  status: 'idle', // idle: 未连接 | connecting: 连接中 | connected: 已连接 | error: 连接失败
  progress: 0, // 资源下载进度 0-100（由 SDK onDownloadProgress 回调驱动）
  error: '', // 连接失败的错误信息
  warning: '', // 连接后的运行期警告（如解码/资源错误），不中断连接
  speaking: false, // 数字人是否正在播报语音
})

let sdkInstance = null // XmovAvatar 实例（单例）
let sdkScriptPromise = null // SDK 脚本加载 Promise（防止重复注入 <script>）

// ── 动态加载官方 SDK 脚本 ──────────────────────────────────────
// 数字人"默认不连接"，因此 SDK 脚本也不预先加载，点击"连接数字人"后才加载
function loadSdkScript() {
  if (window.XmovAvatar) {
    return Promise.resolve()
  }
  if (!sdkScriptPromise) {
    sdkScriptPromise = new Promise((resolve, reject) => {
      const script = document.createElement('script')
      script.src = SDK_SCRIPT_URL
      script.onload = () => resolve()
      script.onerror = () => {
        sdkScriptPromise = null // 允许下次重试
        reject(new Error('数字人 SDK 脚本加载失败，请检查网络后重试。'))
      }
      document.head.appendChild(script)
    })
  }
  return sdkScriptPromise
}

// ── 连接并初始化数字人 ────────────────────────────────────────
// containerId: SDK 渲染容器元素 id（容器需具有明确的宽高，见官方注意事项）
export async function connectDigitalHuman(containerId) {
  if (digitalHumanState.status === 'connecting' || digitalHumanState.status === 'connected') {
    return
  }
  if (sdkInstance) {
    return
  }

  if (!APP_ID || !APP_SECRET) {
    digitalHumanState.status = 'error'
    digitalHumanState.error =
      '尚未配置数字人凭据：请在前端目录 .env 中填写 VITE_XMOV_APP_ID 与 VITE_XMOV_APP_SECRET，然后重启 dev server。'
    return
  }

  digitalHumanState.status = 'connecting'
  digitalHumanState.progress = 0
  digitalHumanState.error = ''
  digitalHumanState.speaking = false

  try {
    await loadSdkScript()

    sdkInstance = new window.XmovAvatar({
      containerId: `#${containerId}`, // 文档示例使用选择器形式
      appId: APP_ID,
      appSecret: APP_SECRET,
      gatewayServer: GATEWAY_SERVER,
      hardwareAcceleration: 'prefer-hardware', // 开启硬件加速
      enableLogger: false,
      onMessage(message) {
        console.warn('[digital-human] SDK message:', message)
        const code = message?.code
        // 10005: 超出房间并发限制（官方建议调用 destroy() 主动释放连接）
        if (code === 10005) {
          digitalHumanState.status = 'error'
          digitalHumanState.error =
            '数字人连接数已达上限，请先断开其他页面的数字人连接后重试。'
          try {
            sdkInstance?.destroy()
          } catch (_) {
            /* 忽略销毁异常 */
          }
          sdkInstance = null
          return
        }
        // 其他运行期错误（资源/解码/TTSA 等 1xxxx-4xxxx）：显示到面板，
        // 避免出现"状态在线但画面黑屏"却无任何提示的情况（网络类 5xxxx 为常规通知，不告警）
        if (typeof code === 'number' && code >= 10001 && code < 50001) {
          digitalHumanState.warning = `数字人异常 (${code})：${message?.message ?? '未知错误'}`
        }
      },
      onVoiceStateChange(state) {
        // voice_start: 开始讲话 / voice_end: 讲话结束
        digitalHumanState.speaking = state === 'start'
      },
      onStateChange(state) {
        console.log('[digital-human] state:', state)
      },
    })

    // init：初始化连接房间 + 下载数字人资源（进度范围 [0, 100]）
    await sdkInstance.init({
      onDownloadProgress: (progress) => {
        digitalHumanState.progress = Math.round(progress)
      },
      initModel: 'normal', // 正常初始化（非隐身模式）
    })

    digitalHumanState.status = 'connected'
    digitalHumanState.progress = 100
  } catch (error) {
    console.error('[digital-human] 连接失败:', error)
    // 清理半初始化的实例，保证"重新连接"可重试
    try {
      sdkInstance?.destroy?.()
    } catch (_) {
      /* 忽略清理异常 */
    }
    sdkInstance = null
    digitalHumanState.status = 'error'
    digitalHumanState.error =
      error instanceof Error ? error.message : '数字人连接失败，请重试。'
  }
}

// ── 断开并销毁数字人 ──────────────────────────────────────────
export function disconnectDigitalHuman() {
  if (sdkInstance) {
    try {
      sdkInstance.destroy()
    } catch (_) {
      /* 忽略 */
    }
    sdkInstance = null
  }
  digitalHumanState.status = 'idle'
  digitalHumanState.progress = 0
  digitalHumanState.error = ''
  digitalHumanState.warning = ''
  digitalHumanState.speaking = false
}

export function isDigitalHumanConnected() {
  return digitalHumanState.status === 'connected' && sdkInstance !== null
}

// ── 解析客服后端响应的消息结构 → 数字人播报文本 ────────────────
// 客服后端消息结构（与 App.vue 中 appendMessage 的解析一致）：
//   文本消息: { text: string, suggestions?: [...] }
//   对象消息: { object: { type: 'order'|'product', title?, order_id?, product_id?,
//                        status?, amount?, price?, description?, attributes?: {...} } }
function parseOrderSpeakText(object) {
  const status = object.status ?? object.attributes?.status
  const amount = object.amount ?? object.attributes?.amount
  const parts = []
  if (object.order_id ?? object.id) parts.push(`订单${object.order_id ?? object.id}`)
  if (status) parts.push(`当前状态：${status}`)
  if (amount != null) parts.push(`金额：${amount}`)
  return parts.length ? parts.join('，') : object.title ?? ''
}

function parseProductSpeakText(object) {
  const price = object.price ?? object.attributes?.price
  const parts = []
  if (object.title) parts.push(object.title)
  if (object.product_id ?? object.id) parts.push(`商品号${object.product_id ?? object.id}`)
  if (price != null) parts.push(`价格：${price}`)
  else if (object.description) parts.push(object.description)
  return parts.join('，')
}

export function extractSpeakableText(botMessages) {
  if (!Array.isArray(botMessages)) {
    return ''
  }
  const parts = []
  for (const message of botMessages) {
    if (!message) continue
    if (typeof message.text === 'string' && message.text.trim()) {
      parts.push(message.text.trim())
    } else if (message.object) {
      const object = message.object
      let text = ''
      if (object.type === 'order') text = parseOrderSpeakText(object)
      else if (object.type === 'product') text = parseProductSpeakText(object)
      else if (object.title) text = object.title
      if (text) parts.push(text)
    }
  }
  return parts.join('。')
}

// ── 通知数字人播报客服回复（App.vue 在收到响应后调用）──────────
// 数字人未连接时静默跳过，完全不影响现有对话流程
export function notifyDigitalHuman(botMessages) {
  if (!isDigitalHumanConnected()) {
    return
  }
  const text = extractSpeakableText(botMessages)
  if (!text) {
    return
  }
  try {
    // 官方说明：speak 不允许连续多次调用（前一次 is_end=true 之后直接接续 speak），
    // 建议中间用 interactive_idle 做一次状态切换。
    // 因此若数字人正在播报（用户连续发消息的场景），先打断回待机再播报。
    if (digitalHumanState.speaking) {
      sdkInstance.interactiveidle()
    }
    // 非流式一次性播报整段内容：speak(text, is_start=true, is_end=true)
    sdkInstance.speak(text, true, true)
  } catch (error) {
    console.error('[digital-human] speak 调用失败:', error)
  }
}
