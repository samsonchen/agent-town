// agent-town Phase 0 recorder.
//
// Observes the Claude Code events agent-town uses and appends one JSON line per
// event to ~/Library/Application Support/agent-town-claude-code/recorder/<session>.jsonl.
// Every hook passes the event on unchanged. It also runs two probes once per
// session: a POST to the agent-town endpoint (Phase 0 item 1) and a Haiku
// classification over the role catalog (item 6).

import type { Register } from 'claude-code'

// On a failure in our own code, pass the event on as if we were not here.
// eslint-disable-next-line @typescript-eslint/no-explicit-any
const passOn = ($: any, e: any, next: any) => next(e)

const MAX_LINES = 5000
const MAX_STR = 400

let lines: string[] = []
let dirty = false
let outPath: string | undefined
let started = Date.now()
let classified = false

// A small, safe snapshot: long strings cut, depth and array length limited.
function snap(v: unknown, depth = 0): unknown {
  if (v === null || v === undefined) return v
  if (typeof v === 'string') return v.length > MAX_STR ? v.slice(0, MAX_STR) + `…(${v.length})` : v
  if (typeof v !== 'object') return v
  if (depth >= 4) return '…'
  if (Array.isArray(v)) return v.slice(0, 12).map(x => snap(x, depth + 1))
  const out: Record<string, unknown> = {}
  for (const [k, x] of Object.entries(v as Record<string, unknown>)) {
    if (typeof x === 'function') continue
    out[k] = snap(x, depth + 1)
  }
  return out
}

function rec(ev: string, data: Record<string, unknown>) {
  try {
    lines.push(JSON.stringify({ t: Date.now(), dt: Date.now() - started, ev, ...data }))
    if (lines.length > MAX_LINES) lines = lines.slice(-MAX_LINES)
    dirty = true
  } catch {
    // never affect the session
  }
}

export const register: Register = on => {
  on('session.start', async ($, e, next) => {
    try {
      started = Date.now()
      const home = await $.env.get('HOME')
      const sid = await $.session.id()
      outPath = `${home}/Library/Application Support/agent-town-claude-code/recorder/${sid}.jsonl`
      rec('session.start', {
        e: snap(e),
        sessionId: sid,
        model: await $.session.model(),
        repo: snap(await $.session.repo()),
        root: await $.session.root(),
      })
      $.clock.every(1000, () => {
        if (!dirty || !outPath) return
        dirty = false
        $.fs.write(outPath, lines.join('\n') + '\n').catch(err => {
          $.ui.status(`town-recorder: write failed: ${String(err).slice(0, 80)}`)
        })
      })
      // Probe 1: POST to the endpoint, if the app or the debug receiver runs.
      const ep = `${home}/Library/Application Support/agent-town-claude-code/endpoint.json`
      if (await $.fs.exists(ep)) {
        const info = JSON.parse(String(await $.fs.read(ep))) as { port: number; token: string }
        const t0 = Date.now()
        $.http
          .fetch(`http://127.0.0.1:${info.port}/v1/events`, {
            method: 'POST',
            headers: { Authorization: `Bearer ${info.token}`, 'Content-Type': 'application/json' },
            body: JSON.stringify({
              protocol: 1,
              // A session ID of its own (town-link sends this session's), closed at once, so the
              // probe never puts a block or a Chief of Staff in the app.
              events: [
                { type: 'heartbeat', sessionId: `recorder-probe-${sid}`, seq: 1, ts: Date.now(), projectId: 'recorder-probe' },
                { type: 'session.close', sessionId: `recorder-probe-${sid}`, seq: 2, ts: Date.now(), projectId: 'recorder-probe', reason: 'other' },
              ],
            }),
          })
          .then(r => rec('probe.http', { status: r.status, ok: r.ok, ms: Date.now() - t0 }))
          .catch(err => rec('probe.http', { error: String(err), ms: Date.now() - t0 }))
      } else {
        rec('probe.http', { skipped: 'no endpoint file; start tools/debug-receiver.py first' })
      }
    } catch (err) {
      rec('recorder.error', { at: 'session.start', error: String(err) })
    }
    return next(e)
  }).catch(passOn)

  on('session.end', async ($, e, next) => {
    rec('session.end', { e: snap(e) })
    if (outPath) {
      try {
        await $.fs.write(outPath, lines.join('\n') + '\n')
      } catch {
        // ignore
      }
    }
    return next(e)
  }).catch(passOn)

  on('prompt.submit', async ($, e, next) => {
    rec('prompt.submit', { e: snap(e) })
    // Probe 6: classification delay with the full role list, once per session.
    if (!classified && e.origin?.kind === 'composer' && !e.command) {
      classified = true
      void (async () => {
        try {
          const root = await $.session.root()
          const path = `${root}/catalog/roles.json`
          if (!(await $.fs.exists(path))) return rec('probe.classify', { skipped: 'no catalog/roles.json in this project' })
          const cat = JSON.parse(String(await $.fs.read(path))) as { roles: { id: string; background?: boolean }[] }
          const labels = cat.roles.filter(r => !r.background).map(r => r.id)
          const t0 = Date.now()
          const got = await $.model.classify(e.text.slice(0, 600), labels, { model: 'haiku' })
          rec('probe.classify', { labels: labels.length, result: got ?? null, ms: Date.now() - t0 })
        } catch (err) {
          rec('probe.classify', { error: String(err) })
        }
      })()
    }
    return next(e)
  }).catch(passOn)

  on('turn.start', ($, e, next) => {
    rec('turn.start', { e: snap(e) })
    return next(e)
  }).catch(passOn)

  on('turn.complete', ($, e, next) => {
    rec('turn.complete', { e: snap(e) })
    return next(e)
  }).catch(passOn)

  on('agent.spawn', async ($, e, next) => {
    rec('agent.spawn', { e: snap(e) })
    const r = await next(e)
    rec('agent.spawn.result', { tool_use_id: e.tool_use_id, r: snap(r) })
    return r
  }).catch(passOn)

  on('tool.check', async ($, e, next) => {
    const r = await next(e)
    rec('tool.check', { e: snap(e), r: snap(r) })
    return r
  }).catch(passOn)

  on('tool.call', async ($, e, next) => {
    const t0 = Date.now()
    rec('tool.call', { e: snap(e) })
    const r = await next(e)
    rec('tool.call.result', { tool: e.tool, tool_use_id: e.tool_use_id, ms: Date.now() - t0, r: snap(r) })
    return r
  }).catch(passOn)

  on('session.send', ($, e, next) => {
    rec('session.send', { e: snap(e) })
    return next(e)
  }).catch(passOn)

  on('session.receive', ($, e, next) => {
    rec('session.receive', { e: snap(e) })
    return next(e)
  }).catch(passOn)

  on('classic.Stop', async ($, e, next) => {
    const r = await next(e)
    rec('classic.Stop', { e: snap(e), r: snap(r) })
    return r
  }).catch(passOn)

  on('classic.SubagentStop', async ($, e, next) => {
    const r = await next(e)
    rec('classic.SubagentStop', { e: snap(e), r: snap(r) })
    return r
  }).catch(passOn)
}
