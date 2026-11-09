// town-link: sends what Claude Code does to the agent-town app.
//
// Every hook only observes: it passes the event on unchanged, never awaits the
// network or a model call, and swallows its own errors. Events are queued and
// sent in one POST about every 250 ms to the loopback endpoint the app writes
// to ~/Library/Application Support/agent-town/endpoint.json. See
// docs/protocol.md and docs/architecture.md in the agent-town repository.

import type { Register } from 'claude-code'
import { Town, projectIdentity, type ClassifyJob, type Ev } from './core'

const PROTOCOL = 1
const FLUSH_MS = 250
const HEARTBEAT_MS = 30_000
const ENDPOINT_RETRY_MS = 2_000
const MAX_QUEUE = 500

// On a failure in our own code before next(e), pass the event on as if we were not here.
// eslint-disable-next-line @typescript-eslint/no-explicit-any
const passOn = ($: any, e: any, next: any) => next(e)

function safe(f: () => void) {
  try {
    f()
  } catch {
    // never affect the session
  }
}

type Endpoint = { port: number; token: string }

let town = new Town()
let sessionId = ''
let projectId = ''
let seq = 0
let queue: Ev[] = []
let endpoint: Endpoint | undefined
let endpointCheckedAt = 0
let sending = false
let enabled = true
let refused = false // the app answered 426
let endpointPath = ''

function envelope(ev: Ev): Ev {
  return { ...ev, sessionId, seq: ++seq, ts: Date.now(), projectId }
}

/** Move what the tracker emitted into the outbox. */
function collect() {
  for (const ev of town.drain()) {
    if (!enabled || refused) continue
    queue.push(envelope(ev))
  }
  if (queue.length > MAX_QUEUE) queue = queue.slice(-MAX_QUEUE)
}

// eslint-disable-next-line @typescript-eslint/no-explicit-any
function runJobs($: any) {
  for (const job of town.takeJobs()) classify($, job)
}

// eslint-disable-next-line @typescript-eslint/no-explicit-any
function classify($: any, job: ClassifyJob) {
  Promise.resolve()
    .then(() => $.model.classify(job.text, [...job.labels], { model: 'haiku' }))
    .then((label: unknown) => town.classified(job, typeof label === 'string' ? label : undefined))
    .catch(() => town.classified(job, undefined))
    .finally(() => collect())
}

async function hashId(identity: string): Promise<string> {
  const bytes = new TextEncoder().encode(identity)
  const digest = new Uint8Array(await crypto.subtle.digest('SHA-256', bytes))
  return Array.from(digest.slice(0, 8), b => b.toString(16).padStart(2, '0')).join('')
}

// eslint-disable-next-line @typescript-eslint/no-explicit-any
async function readEndpoint($: any): Promise<Endpoint | undefined> {
  try {
    if (!(await $.fs.exists(endpointPath))) return undefined
    const info = JSON.parse(String(await $.fs.read(endpointPath))) as { protocol?: number; port?: number; token?: string }
    if (info.protocol !== PROTOCOL || typeof info.port !== 'number' || typeof info.token !== 'string') return undefined
    return { port: info.port, token: info.token }
  } catch {
    return undefined
  }
}

// eslint-disable-next-line @typescript-eslint/no-explicit-any
async function flush($: any) {
  if (sending) return
  safe(() => town.tick(Date.now()))
  collect()
  if (queue.length === 0) return
  sending = true
  try {
    if (!endpoint) {
      if (Date.now() - endpointCheckedAt < ENDPOINT_RETRY_MS) return
      endpointCheckedAt = Date.now()
      endpoint = await readEndpoint($)
      if (!endpoint) {
        queue = [] // the app is not running: drop, never retry old events
        return
      }
    }
    const batch = queue
    queue = []
    const ep = endpoint
    const res = await $.http.fetch(`http://127.0.0.1:${ep.port}/v1/events`, {
      method: 'POST',
      headers: { Authorization: `Bearer ${ep.token}`, 'Content-Type': 'application/json' },
      body: JSON.stringify({ protocol: PROTOCOL, events: batch }),
    })
    if (res.status === 401) endpoint = undefined
    else if (res.status === 426) {
      refused = true
      queue = []
      $.ui.toast('agent-town: the app needs a newer town-link plugin.')
    }
  } catch {
    endpoint = undefined // connection refused or timeout: the batch is dropped
  } finally {
    sending = false
  }
}

const statusText = () =>
  [
    `town-link: sending is ${enabled ? 'on' : 'off'}.`,
    refused ? 'The agent-town app refused this protocol version; update town-link.' : endpoint ? 'Connected to the agent-town app.' : 'The agent-town app is not running.',
    'Use /town on or /town off to change sending for all sessions.',
  ].join('\n')

export const register: Register = on => {
  on('session.start', async ($, e, next) => {
    try {
      town = new Town(() => crypto.randomUUID())
      seq = 0
      queue = []
      endpoint = undefined
      refused = false
      sessionId = await $.session.id()
      const home = await $.env.get('HOME')
      endpointPath = `${home}/Library/Application Support/agent-town/endpoint.json`
      const stored = await $.store.get('enabled')
      enabled = stored !== false

      const repo = await $.session.repo()
      const root = repo?.root ?? (await $.session.root())
      const { identity, name } = projectIdentity(repo?.remote, root)
      projectId = await hashId(identity)

      const version = await $.session.version()
      const model = await $.session.model()
      town.open({
        projectName: name,
        surface: e.isInteractive === false ? 'headless' : (e.surface ?? 'terminal'),
        ccVersion: version.version,
        ...(model ? { model } : {}),
      })
      collect()

      await $.command.register({
        name: 'town',
        description: 'agent-town: show status, or turn sending on or off',
        argumentHint: '[on|off]',
        immediate: true,
      })
      $.clock.every(FLUSH_MS, () => void flush($))
      $.clock.every(HEARTBEAT_MS, () => {
        safe(() => town.heartbeat())
        collect()
      })
    } catch {
      // the session goes on without the town
    }
    return next(e)
  }).catch(passOn)

  on('command.run', { command: 'town' }, async ($, e, next) => {
    const arg = (e.args ?? '').trim().toLowerCase()
    if (arg === 'on' || arg === 'off') {
      enabled = arg === 'on'
      await $.store.set('enabled', enabled)
      if (!enabled) queue = []
    }
    return { text: statusText(), isTextDisplayOnly: true as const }
  }).catch(passOn)

  on('session.end', async ($, e, next) => {
    safe(() => town.close(String(e.reason ?? 'other')))
    void flush($)
    return next(e)
  }).catch(passOn)

  on('prompt.submit', async ($, e, next) => {
    safe(() => town.prompt({ text: e.text, kind: e.origin?.kind ?? 'unclassified', turnId: e.turnId, isMeta: e.isMeta }, Date.now()))
    collect()
    runJobs($)
    return next(e)
  }).catch(passOn)

  on('turn.complete', ($, e, next) => {
    safe(() =>
      town.turnComplete(
        { agentId: e.agentId, durationMs: e.durationMs, isAborted: e.isAborted, reason: e.reason, model: e.usage?.model },
        Date.now(),
      ),
    )
    collect()
    return next(e)
  }).catch(passOn)

  on('agent.spawn', async ($, e, next) => {
    const r = await next(e)
    safe(() =>
      town.hire(
        {
          subagentType: e.subagentType,
          name: e.name,
          description: e.description,
          prompt: e.prompt,
          parentAgentId: e.parentAgentId,
          background: e.background,
        },
        { agentId: r?.agentId, teammateId: r?.teammateId, model: r?.model },
        Date.now(),
      ),
    )
    collect()
    runJobs($)
    return r
  }).catch(passOn)

  on('tool.check', async ($, e, next) => {
    const r = await next(e)
    safe(() => {
      if (r?.decision === 'ask' && e.approver === 'person' && e.tool_use_id) {
        town.ask({ tool_use_id: e.tool_use_id, tool: e.tool, agentId: e.agentId }, Date.now())
      }
    })
    return r
  }).catch(passOn)

  on('tool.call', async ($, e, next) => {
    // eslint-disable-next-line @typescript-eslint/no-explicit-any
    const call = e as any
    safe(() => town.toolStart({ tool: call.tool, agentId: call.agentId }, Date.now()))
    collect()
    const r = await next(e)
    safe(() => {
      // eslint-disable-next-line @typescript-eslint/no-explicit-any
      const res = r as any
      const ok = !!res && !res.deny && !res.isError && res.result !== undefined
      const result = res?.result && typeof res.result === 'object' ? res.result : {}
      town.toolEnd({ tool: call.tool, tool_use_id: call.tool_use_id, agentId: call.agentId, input: call }, { ok, result }, Date.now())
    })
    collect()
    runJobs($)
    return r
  }).catch(passOn)

  on('session.send', ($, e, next) => {
    safe(() => {
      if (e.origin?.kind === 'model') town.message({ to: e.to, agentId: e.agentId }, Date.now())
    })
    collect()
    return next(e)
  }).catch(passOn)

  on('classic.Stop', async ($, e, next) => {
    const r = await next(e)
    safe(() => {
      // eslint-disable-next-line @typescript-eslint/no-explicit-any
      const res = r as any
      if (res?.block) town.stopBlocked(typeof res.reason === 'string' ? res.reason : undefined, Date.now())
    })
    collect()
    return r
  }).catch(passOn)
}
