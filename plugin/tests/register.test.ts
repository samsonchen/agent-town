// Tests for the hooks in hooks/register.ts: what reaches the app when /compact runs.
// Run: claude plugin test plugin

import { describe, expect, mock, test } from 'claude-code/testing'

type Posted = { type: string; [k: string]: unknown }

/** The engine and an app beneath the plugin; returns the events the app received. */
// eslint-disable-next-line @typescript-eslint/no-explicit-any
function world(on: any) {
  const clock = mock.clock(on, { now: 1_000_000 })
  mock.store(on)
  const posted: Posted[] = []
  on('session.id', () => ({ value: 'session-1' }))
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  on('env.get', (_: any, e: any) => ({ value: e.name === 'HOME' ? '/home/test' : undefined }))
  on('session.repo', () => ({ value: { root: '/work/town', remote: 'github.com/example/town' } }))
  on('session.root', () => ({ value: '/work/town' }))
  on('settings.read', () => ({ value: {} }))
  on('session.version', () => ({ value: { version: '2.1.319' } }))
  on('session.model', () => ({ value: 'claude-opus-5-5' }))
  on('session.usage', () => ({ value: undefined }))
  on('command.register', () => ({ value: { command: 'town' } }))
  on('fs.exists', () => ({ value: true }))
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  on('fs.read', (_: any, e: any) =>
    String(e.path).endsWith('.claude-plugin/plugin.json')
      ? { value: JSON.stringify({ name: 'town-link', version: '9.8.7' }) }
      : { value: JSON.stringify({ protocol: 1, port: 50000, token: 'test-token' }) })
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  on('http.fetch', (_: any, e: any) => {
    const body = JSON.parse(String(e.init?.body ?? e.body ?? '{}')) as { events?: Posted[] }
    posted.push(...(body.events ?? []))
    return { value: { status: 204, headers: {}, text: '' } }
  })
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  on('session.start', (_: any, e: any) => ({ cwd: e.cwd }))
  return { clock, posted }
}

const compactEvents = (posted: Posted[]) =>
  posted.filter(ev => ev.type.startsWith('compact.')).map(({ type, trigger, outcome, tokensBefore, tokensAfter }) => ({
    type,
    ...(trigger !== undefined ? { trigger } : {}),
    ...(outcome !== undefined ? { outcome } : {}),
    ...(tokensBefore !== undefined ? { tokensBefore } : {}),
    ...(tokensAfter !== undefined ? { tokensAfter } : {}),
  }))

describe('/compact', () => {
  test('shows even when no session.compact is raised inside the command', async ($, on) => {
    const { clock, posted } = world(on)
    // Another plugin (or a precomputed summary) compacts without raising session.compact.
    on('command.run', () => ({}))

    await $.session.start({ cwd: '/work/town', surface: 'terminal', isInteractive: true })
    await $.command.run({ command: 'compact', args: '' })
    await clock.advance(1_000)

    expect(compactEvents(posted)).toEqual([
      { type: 'compact.start', trigger: 'manual' },
      { type: 'compact.end', outcome: 'done' },
    ])
  })

  test('a failed /compact ends the scene', async ($, on) => {
    const { clock, posted } = world(on)
    on('command.run', () => {
      throw new Error('compaction failed')
    })

    await $.session.start({ cwd: '/work/town', surface: 'terminal', isInteractive: true })
    await $.command.run({ command: 'compact', args: '' }).catch(() => undefined)
    await clock.advance(1_000)

    expect(compactEvents(posted)).toEqual([
      { type: 'compact.start', trigger: 'manual' },
      { type: 'compact.end', outcome: 'failed' },
    ])
  })
})

describe('Stop hook', () => {
  test("a Stop block's reason reaches the app with the return", async ($, on) => {
    const { clock, posted } = world(on)
    on('classic.Stop', () => ({ block: 'Tests are failing' }))

    await $.session.start({ cwd: '/work/town', surface: 'terminal', isInteractive: true })
    // eslint-disable-next-line @typescript-eslint/no-explicit-any
    await ($.prompt as any).submit({ text: 'fix the login bug' }).catch(() => undefined)
    // eslint-disable-next-line @typescript-eslint/no-explicit-any
    await ($.classic as any).Stop({ session_id: 'session-1', transcript_path: '', cwd: '/work/town', hook_event_name: 'Stop', stop_hook_active: false })
    await clock.advance(1_000)

    const returns = posted.filter(ev => ev.type === 'ticket.return')
    expect(returns.map(ev => ev.reason)).toEqual(['Tests are failing'])
  })
})

describe('/town', () => {
  test('shows the plugin version from plugin.json', async ($, on) => {
    world(on)

    await $.session.start({ cwd: '/work/town', surface: 'terminal', isInteractive: true })
    // eslint-disable-next-line @typescript-eslint/no-explicit-any
    const result = (await $.command.run({ command: 'town', args: '' })) as any
    expect(String(result.text).split('\n')[0]).toBe('Version 9.8.7.')
  })
})
