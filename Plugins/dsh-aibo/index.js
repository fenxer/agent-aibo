/**
 * Observe-only DeepSeek Harness plugin for aibo.
 *
 * Listens at documented interception points and forwards Codex-shaped JSON
 * to aibo's Unix socket. Waterfalls always call `next()`; emit/serial
 * listeners never throw. Fail-open: socket errors go to aibo's queue.
 *
 * @see https://deepseek-harness.github.io/deepseek-harness/reference/cookbook/extension-cookbook
 */
import { homedir } from 'node:os'
import { join } from 'node:path'
import { mkdirSync, readdirSync, statSync, unlinkSync, writeFileSync, existsSync } from 'node:fs'
import { createConnection } from 'node:net'
import { randomUUID } from 'node:crypto'

export const name = 'aibo-observer'

const AGENT = 'deepseek'
const SOCKET_NAME = 'aibo.sock'
const QUEUE_DIR_NAME = 'queue'
const MAX_QUEUE_FILES = 200
const MAX_QUEUE_BYTES = 5 * 1024 * 1024

const planBySession = new Map()

export function apply(ctx) {
  const support = join(homedir(), 'Library', 'Application Support', 'aibo')
  const socketPath = join(support, SOCKET_NAME)
  const queueDir = join(support, QUEUE_DIR_NAME)

  const emit = (eventName, extra) => {
    sendLine(socketPath, queueDir, {
      aibo_agent: AGENT,
      hook_event_name: eventName,
      ...extra,
    })
  }

  ctx.on('session/event', (session, event) => {
    try {
      if (event?.type !== 'plan/mode') return
      const id = sessionIdOf(session)
      if (!id) return
      if (event.data?.active === true) planBySession.set(id, true)
      else planBySession.delete(id)
    } catch {
      // Observing plan/mode must never affect the session log consumer.
    }
  })

  ctx.on('agent/session-start', ({ agent, source }) => {
    try {
      emit('SessionStart', {
        ...base(ctx, agent),
        source: source ?? 'unknown',
      })
    } catch {
      // SessionStart is emit-shaped; aibo is optional.
    }
  })

  ctx.on('agent/pre-step', async ({ agent, messages, turn }, next) => {
    try {
      const prompt = textFromMessages(messages)
      if (prompt.length > 0) {
        emit('UserPromptSubmit', {
          ...base(ctx, agent),
          turn_id: String(turn ?? ''),
          prompt,
        })
      }
    } catch {
      // Swallow and still delegate.
    }
    return next()
  })

  ctx.on('tools/pre-execute', async (exec, next) => {
    try {
      emit('PreToolUse', toolPayload(ctx, exec))
    } catch {
      // Swallow and still delegate.
    }
    return next()
  })

  ctx.on('tools/post-execute', async (exec, result, next) => {
    try {
      emit('PostToolUse', {
        ...toolPayload(ctx, exec),
        tool_response: textFromBlocks(result?.content),
      })
    } catch {
      // Swallow and still delegate.
    }
    return next()
  })

  ctx.on('agent/turn-stopping', async ({ agent, turn }) => {
    try {
      emit('Stop', {
        ...base(ctx, agent),
        turn_id: String(turn ?? ''),
        stop_hook_active: false,
      })
    } catch {
      // Serial observer; turn still stops.
    }
  })

  ctx.on('approval/request', async (req, next) => {
    try {
      emit('PermissionRequest', {
        ...base(ctx, req?.agent),
        tool_name: typeof req?.toolName === 'string' ? req.toolName : undefined,
        tool_use_id: req?.callId,
      })
    } catch {
      // Must not claim the approval slot.
    }
    return next()
  })

  ctx.on('subagent/start', (info) => {
    try {
      const id = stringId(info?.id)
      if (!id) return
      emit('SubagentStart', {
        session_id: id,
        cwd: undefined,
        model: '',
        permission_mode: 'default',
        transcript_path: null,
        agent_type: typeof info?.provider === 'string' ? info.provider : 'general-purpose',
      })
    } catch {
      // Observe-only lifecycle pair.
    }
  })

  ctx.on('subagent/end', (info) => {
    try {
      const id = stringId(info?.id)
      if (!id) return
      emit('SubagentStop', {
        session_id: id,
        cwd: undefined,
        model: '',
        permission_mode: 'default',
        transcript_path: null,
        status: typeof info?.stopReason === 'string' ? info.stopReason : 'completed',
      })
    } catch {
      // Observe-only lifecycle pair.
    }
  })
}

function base(ctx, agent) {
  const header = agent?.session?.header
  const id = sessionIdOf(agent?.session) || stringId(header?.id)
  const cwd = typeof header?.cwd === 'string' ? header.cwd : undefined
  let transcriptPath = null
  try {
    transcriptPath = ctx.get?.('sessionPersistence')?.locate?.(header)?.path ?? null
  } catch {
    transcriptPath = null
  }
  return {
    session_id: id || '',
    transcript_path: transcriptPath,
    cwd,
    model: modelOf(header),
    permission_mode: id && planBySession.get(id) ? 'plan' : 'default',
  }
}

function toolPayload(ctx, exec) {
  const args = exec?.arguments
  return {
    ...base(ctx, exec?.agent),
    tool_name: typeof exec?.name === 'string' ? exec.name : 'tool',
    tool_input: args && typeof args === 'object' ? args : {},
    tool_use_id: exec?.callId,
  }
}

function sessionIdOf(session) {
  return stringId(session?.header?.id) || stringId(session?.id)
}

function stringId(value) {
  if (typeof value === 'string' && value.length > 0) return value
  if (value != null && typeof value === 'object' && typeof value.toString === 'function') {
    const text = value.toString()
    if (text && text !== '[object Object]') return text
  }
  return ''
}

function modelOf(header) {
  for (const key of ['model', 'model_id', 'modelId']) {
    const value = header?.[key]
    if (typeof value === 'string' && value.trim()) return value
  }
  return ''
}

function textFromMessages(messages) {
  if (!Array.isArray(messages)) return ''
  return messages.map((message) => textFromBlocks(message?.content)).join('')
}

function textFromBlocks(content) {
  if (!Array.isArray(content)) return ''
  return content
    .filter((block) => block && block.type === 'text' && typeof block.text === 'string')
    .map((block) => block.text)
    .join('')
}

function sendLine(socketPath, queueDir, payload) {
  const line = `${JSON.stringify(payload)}\n`
  const buffer = Buffer.from(line)
  const socket = createConnection(socketPath)
  let settled = false
  const fail = () => {
    if (settled) return
    settled = true
    socket.destroy()
    enqueue(queueDir, buffer)
  }
  socket.setTimeout(250)
  socket.once('connect', () => {
    socket.write(buffer, (error) => {
      if (error) {
        fail()
        return
      }
      settled = true
      socket.end()
    })
  })
  socket.once('error', fail)
  socket.once('timeout', fail)
}

function enqueue(queueDir, buffer) {
  try {
    const support = join(queueDir, '..')
    if (!existsSync(support)) mkdirSync(support, { recursive: true })
    if (!existsSync(queueDir)) mkdirSync(queueDir, { recursive: true })
    trimQueue(queueDir)
    const name = `${(Date.now() / 1000).toFixed(6)}-${randomUUID()}.json`
    writeFileSync(join(queueDir, name), buffer)
  } catch {
    // Queue is best-effort; dropping an event is better than throwing into the loop.
  }
}

function trimQueue(queueDir) {
  let files
  try {
    files = readdirSync(queueDir)
      .filter((name) => name.endsWith('.json'))
      .sort()
      .map((name) => join(queueDir, name))
  } catch {
    return
  }
  let total = 0
  const sizes = new Map()
  for (const path of files) {
    let size = 0
    try {
      size = statSync(path).size
    } catch {
      size = 0
    }
    sizes.set(path, size)
    total += size
  }
  while (files.length > MAX_QUEUE_FILES || total > MAX_QUEUE_BYTES) {
    const oldest = files.shift()
    if (!oldest) break
    total -= sizes.get(oldest) ?? 0
    try {
      unlinkSync(oldest)
    } catch {
      // Ignore a file that vanished between readdir and unlink.
    }
  }
}
