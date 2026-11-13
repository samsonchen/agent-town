// Tests for the event mapping in hooks/core.ts. Run: claude plugin test plugin
//
// The notification and spawn shapes are copied from a live 2.1.318 session
// (docs/verification.md).

import { describe, expect, test } from 'claude-code/testing'
import { Town, cleanTitle, endpointFilePath, fileRole, DESK_MAX, TITLE_MAX, activityKind, parseNotifications, projectIdentity, shellRole, taskStatus, APPROVAL_DELAY_MS, HOLD_MS } from '../hooks/core'

const ids = () => {
  let n = 0
  return () => `t${++n}`
}
const types = (t: Town) => t.drain().map(e => e.type)

const NOTE = (id: string, status = 'completed') =>
  `<task-notification>\n<task-id>${id}</task-id>\n<tool-use-id>toolu_1</tool-use-id>\n<output-file>/tmp/x.output</output-file>\n<status>${status}</status>\n<summary>Background command "npm test" completed (exit code 0)</summary>\n</task-notification>`

describe('helpers', () => {
  test('activity kinds', async () => {
    expect(activityKind('Read')).toBe('read')
    expect(activityKind('Edit')).toBe('edit')
    expect(activityKind('Bash')).toBe('shell')
    expect(activityKind('WebFetch')).toBe('web')
    expect(activityKind('mcp__slack__send')).toBe('mcp')
    expect(activityKind('TodoWrite')).toBe('other')
  })

  test('shell roles match whole words in rule order', async () => {
    expect(shellRole('npm run build')).toBe('build-operator')
    expect(shellRole('xcodebuild -scheme App')).toBe('build-operator')
    expect(shellRole('pytest -q')).toBe('test-runner')
    expect(shellRole('npm run dev')).toBe('server-operator')
    expect(shellRole('pip install requests')).toBe('install-operator')
    expect(shellRole('./deploy.sh prod')).toBe('deploy-operator')
    // Windows commands.
    expect(shellRole('msbuild App.sln')).toBe('build-operator')
    expect(shellRole('dotnet build')).toBe('build-operator')
    expect(shellRole('dotnet test')).toBe('test-runner')
    expect(shellRole('winget install Git.Git')).toBe('install-operator')
    expect(shellRole('choco install nodejs')).toBe('install-operator')
    expect(shellRole('Invoke-WebRequest https://example.com/a.zip -OutFile a.zip')).toBe('install-operator')
    expect(shellRole('git log --latest')).toBe(undefined)
    expect(shellRole('sleep 3; echo done')).toBe(undefined)
  })

  test('notification parsing', async () => {
    expect(parseNotifications(NOTE('b3jzg042j'))).toEqual([{ taskId: 'b3jzg042j', status: 'completed' }])
    expect(parseNotifications(NOTE('a') + '\n' + NOTE('b', 'failed')).map(x => x.taskId)).toEqual(['a', 'b'])
    expect(parseNotifications('The person enabled mod hot-reloading')).toEqual([])
    expect(taskStatus('failed')).toBe('failed')
    expect(taskStatus('stopped')).toBe('killed')
    expect(taskStatus('completed')).toBe('completed')
  })

  test('project identity', async () => {
    expect(projectIdentity('https://github.com/samsonchen/agent-town-claude-code.git', '/x/y')).toEqual({ identity: 'github.com/samsonchen/agent-town-claude-code', name: 'agent-town-claude-code' })
    expect(projectIdentity('git@github.com:samsonchen/agent-town-claude-code.git', '/x')).toEqual({ identity: 'github.com/samsonchen/agent-town-claude-code', name: 'agent-town-claude-code' })
    expect(projectIdentity('https://user:secret@example.com/a/b/', '/x').identity).toBe('example.com/a/b')
    expect(projectIdentity(null, '/Users/me/work/site/')).toEqual({ identity: '/Users/me/work/site', name: 'site' })
  })

  test('project identity from a Windows root', () => {
    // No remote: only the folder name is the name, never the whole path.
    expect(projectIdentity(null, 'C:\\Users\\me\\code\\agent-town')).toEqual({ identity: 'c:/Users/me/code/agent-town', name: 'agent-town' })
    expect(projectIdentity(null, 'C:\\Users\\me\\code\\agent-town\\').name).toBe('agent-town')
    // The same folder from two surfaces is one project.
    expect(projectIdentity(null, 'C:\\Users\\me\\site').identity).toBe(projectIdentity(null, 'c:/Users/me/site').identity)
    expect(projectIdentity('https://github.com/me/site.git', 'C:\\Users\\me\\site').name).toBe('site')
  })

  test('endpoint file path', () => {
    expect(endpointFilePath('/Users/me', undefined)).toBe('/Users/me/Library/Application Support/agent-town-claude-code/endpoint.json')
    expect(endpointFilePath(undefined, 'C:\\Users\\me\\AppData\\Roaming')).toBe('C:\\Users\\me\\AppData\\Roaming\\agent-town-claude-code\\endpoint.json')
    expect(endpointFilePath('/c/Users/me', 'C:\\Users\\me\\AppData\\Roaming\\')).toBe('C:\\Users\\me\\AppData\\Roaming\\agent-town-claude-code\\endpoint.json')
  })
})

describe('the desk worker', () => {
  const edit = (file: string) => ({ tool: 'Edit', input: { file_path: file } })

  test('the main loop\'s work goes to a desk worker by role, who reports before the ticket closes', () => {
    const t = new Town(ids())
    t.prompt({ text: 'fix the parser', kind: 'composer' }, 0)
    t.toolStart({ tool: 'Grep', input: { pattern: 'x' } }, 10)
    t.toolStart(edit('/r/src/parse.ts'), 20)
    t.turnComplete({ durationMs: 100, isAborted: false }, 100)
    expect(t.drain().slice(1)).toEqual([
      { type: 'staff.hire', agentId: 'desk-t1-1', subagentType: 'main-loop', description: 'fix the parser', teammate: false, background: false },
      { type: 'staff.role', agentId: 'desk-t1-1', role: 'generalist' },
      { type: 'activity', agentId: 'desk-t1-1', kind: 'read', tool: 'Grep' },
      // The first guess gives way to the file's role, on the same character.
      { type: 'staff.role', agentId: 'desk-t1-1', role: 'typescript-engineer' },
      { type: 'activity', agentId: 'desk-t1-1', kind: 'edit', tool: 'Edit' },
      { type: 'staff.done', agentId: 'desk-t1-1', status: 'completed', durationMs: 90 },
      { type: 'ticket.done', ticketId: 't1', durationMs: 100, aborted: false },
    ])
  })

  test('each role is its own person: the work moves, the others wait at their desks until the ticket ends', () => {
    const t = new Town(ids())
    t.prompt({ text: 'port it', kind: 'composer' }, 0)
    t.toolStart(edit('/r/a.ts'), 0)
    t.toolStart(edit('/r/b.swift'), 5000) // someone new for Swift; the TypeScript engineer stays
    t.toolStart({ tool: 'Read', input: { file_path: '/r/c.py' } }, 6000) // a read does not move the work
    t.toolStart(edit('/r/a.ts'), 7000) // back to TypeScript: the same person, no new call
    t.turnComplete({ durationMs: 9000, isAborted: false }, 9000)
    const evs = t.drain().filter(e => e.type.startsWith('staff.') || e.type === 'activity')
    expect(evs).toEqual([
      { type: 'staff.hire', agentId: 'desk-t1-1', subagentType: 'main-loop', description: 'port it', teammate: false, background: false },
      { type: 'staff.role', agentId: 'desk-t1-1', role: 'typescript-engineer' },
      { type: 'activity', agentId: 'desk-t1-1', kind: 'edit', tool: 'Edit' },
      { type: 'staff.hire', agentId: 'desk-t1-2', subagentType: 'main-loop', description: 'port it', teammate: false, background: false },
      { type: 'staff.role', agentId: 'desk-t1-2', role: 'swift-engineer' },
      { type: 'activity', agentId: 'desk-t1-2', kind: 'edit', tool: 'Edit' },
      { type: 'activity', agentId: 'desk-t1-2', kind: 'read', tool: 'Read' },
      { type: 'activity', agentId: 'desk-t1-1', kind: 'edit', tool: 'Edit' },
      { type: 'staff.done', agentId: 'desk-t1-1', status: 'completed', durationMs: 9000 },
      { type: 'staff.done', agentId: 'desk-t1-2', status: 'completed', durationMs: 4000 },
    ])
  })

  test('past the most desk workers, the one idle longest reports first', () => {
    const t = new Town(ids())
    t.prompt({ text: 'many', kind: 'composer' }, 0)
    const files = ['a.ts', 'b.py', 'c.go', 'd.rs', 'e.java', 'f.rb']
    files.forEach((f, i) => t.toolStart(edit('/r/' + f), i * 10))
    const evs = t.drain().filter(e => e.type === 'staff.done')
    expect(evs).toEqual([{ type: 'staff.done', agentId: 'desk-t1-1', status: 'completed', durationMs: 50 }])
    expect(DESK_MAX).toBe(5)
  })

  test('the task type names an unsure desk worker\'s role; a main-loop approval is theirs', () => {
    const t = new Town(ids())
    t.prompt({ text: 'write the release notes', kind: 'composer' }, 0)
    const job = t.takeJobs().find(j => j.kind === 'task-type')!
    t.toolStart({ tool: 'Bash', input: { command: 'git log' } }, 10)
    t.classified(job, 'docs')
    t.ask({ tool_use_id: 'u1', tool: 'Bash' }, 20)
    t.tick(20 + APPROVAL_DELAY_MS)
    const evs = t.drain()
    expect(evs).toContainEqual({ type: 'staff.role', agentId: 'desk-t1-1', role: 'technical-writer' })
    expect(evs).toContainEqual({ type: 'approval.wait', approvalId: 'u1', agentId: 'desk-t1-1', tool: 'Bash' })
  })

  test('file roles', () => {
    expect(fileRole('/a/App.swift')).toBe('swift-engineer')
    expect(fileRole('/a/Dockerfile')).toBe('devops-engineer')
    expect(fileRole('/a/data.json')).toBeUndefined()
  })

  test('file roles from Windows paths', () => {
    expect(fileRole('C:\\a\\App.swift')).toBe('swift-engineer')
    expect(fileRole('C:\\a\\Dockerfile')).toBe('devops-engineer')
    expect(fileRole('C:\\repo\\.github\\workflows\\ci.yml')).toBe('devops-engineer')
  })
})

describe('task titles', () => {
  test('a typed prompt asks for a title; the reply is cleaned and kept for a reopen', () => {
    const t = new Town(ids())
    t.open({ projectName: 'p', surface: 'terminal', ccVersion: '2' })
    t.prompt({ text: 'please fix the missing sound', kind: 'composer' }, 1000)
    t.drain()
    const job = t.takeJobs().find(j => j.kind === 'task-title')!
    expect(job.id).toBe('t1')
    t.classified(job, '"Title: Fix missing sound."\nmore')
    expect(t.drain()).toEqual([{ type: 'ticket.title', ticketId: 't1', title: 'Fix missing sound' }])
    t.reopen()
    expect(t.drain().filter(e => e.type === 'ticket.title')).toEqual([{ type: 'ticket.title', ticketId: 't1', title: 'Fix missing sound' }])
  })

  test('an empty or failed reply sends nothing; long titles are cut', () => {
    const t = new Town(ids())
    t.titled('t1', undefined)
    t.titled('t1', '  \n ')
    expect(t.drain()).toEqual([])
    expect(cleanTitle('「修正音效」')).toBe('修正音效')
    expect(cleanTitle('x'.repeat(80)).length).toBe(TITLE_MAX)
  })
})

describe('tickets', () => {
  test('a typed prompt opens a ticket, asks for a hat, and closes with Claude Code duration', async () => {
    const t = new Town(ids())
    t.prompt({ text: 'Add a settings screen', kind: 'composer' }, 1000)
    const [submit] = t.drain()
    expect(submit).toEqual({ type: 'ticket.submit', ticketId: 't1', text: 'Add a settings screen', origin: 'user' })
    const [job] = t.takeJobs()
    expect(job?.kind).toBe('task-type')
    t.classified(job!, 'coding')
    t.classified({ ...job!, id: 'zz' }, 'not-a-type')
    expect(t.drain()).toEqual([
      { type: 'chief.hat', ticketId: 't1', taskType: 'coding' },
      { type: 'chief.hat', ticketId: 'zz', taskType: 'general' },
    ])
    t.turnComplete({ durationMs: 4200, isAborted: false, model: 'claude-opus-5-5' }, 9000)
    expect(t.drain()).toEqual([
      { type: 'model.update', model: 'claude-opus-5-5' },
      { type: 'ticket.done', ticketId: 't1', durationMs: 4200, aborted: false },
    ])
  })

  test('a prompt delivered into a running turn adds to the open ticket', async () => {
    const t = new Town(ids())
    t.prompt({ text: 'first', kind: 'composer' }, 0)
    t.drain()
    t.prompt({ text: 'also this', kind: 'composer', turnId: 'turn-1' }, 10)
    t.prompt({ text: '<agent-message>…', kind: 'peer', turnId: 'turn-1', isMeta: true }, 20)
    expect(t.drain()).toEqual([])
  })

  test('the session model is not repeated as an update', async () => {
    const t = new Town(ids())
    t.open({ projectName: 'p', surface: 'terminal', ccVersion: '2.1.319', model: 'claude-opus-5-5' })
    t.prompt({ text: 'x', kind: 'composer' }, 0)
    t.turnComplete({ durationMs: 5, isAborted: false, model: 'claude-opus-5-5' }, 5)
    expect(types(t)).toEqual(['session.open', 'ticket.submit', 'ticket.done'])
  })

  test('a main-loop turn with no prompt (after a ! command) opens a ticket, and its end reports', async () => {
    const t = new Town(ids())
    t.turnStart({ text: '' }, 100)
    t.turnComplete({ durationMs: 900, isAborted: false }, 1000)
    const out = t.drain().map(e => e.type)
    expect(out).toEqual(['ticket.submit', 'ticket.done'])
  })

  test('turn.start adds no ticket after a prompt, or for a subagent', async () => {
    const t = new Town(ids())
    t.prompt({ text: 'fix it', kind: 'composer' }, 100)
    t.turnStart({ text: 'fix it' }, 110)
    t.turnStart({ text: 'look', agentId: 'a1' }, 120)
    expect(t.drain().filter(e => e.type === 'ticket.submit').length).toBe(1)
  })

  test('an auto-continuation returns the last ticket, and the next done covers all the work', async () => {
    const t = new Town(ids())
    t.prompt({ text: 'fix it', kind: 'composer' }, 1000)
    t.turnComplete({ durationMs: 3000, isAborted: false }, 4000)
    t.drain()
    t.prompt({ text: 'Tests still fail', kind: 'auto-continuation' }, 4100)
    t.turnComplete({ durationMs: 2000, isAborted: false }, 6100)
    expect(t.drain()).toEqual([
      { type: 'ticket.return', ticketId: 't1', reason: 'Tests still fail' },
      { type: 'ticket.done', ticketId: 't1', durationMs: 5100, aborted: false },
    ])
  })

  test('a Stop block and the auto-continuation that follows count as one return', async () => {
    const t = new Town(ids())
    t.prompt({ text: 'fix it', kind: 'composer' }, 0)
    t.stopBlocked('Tests still fail', 100)
    t.turnComplete({ durationMs: 100, isAborted: false }, 100)
    t.prompt({ text: 'Tests still fail', kind: 'auto-continuation' }, 150)
    expect(types(t).filter(x => x === 'ticket.return')).toEqual(['ticket.return'])
  })

  test('a system notice with no known task opens an unknown ticket', async () => {
    const t = new Town(ids())
    t.prompt({ text: '<task-notification>\nThe person enabled mod hot-reloading\n</task-notification>', kind: 'task-notification', isMeta: true }, 0)
    expect(t.drain()[0]).toMatchObject({ type: 'ticket.submit', origin: 'unknown' })
  })
})

describe('background tasks and schedules', () => {
  test('a background shell task starts with a rule role and its notification opens a task ticket', async () => {
    const t = new Town(ids())
    t.prompt({ text: 'run the tests', kind: 'composer' }, 0)
    const call = { tool: 'Bash', tool_use_id: 'toolu_1', input: { command: 'npm test', run_in_background: true, description: 'Run tests' } }
    t.toolStart(call, 10)
    t.toolEnd(call, { ok: true, result: { backgroundTaskId: 'b1' } }, 20)
    t.turnComplete({ durationMs: 30, isAborted: false }, 30)
    expect(t.drain()).toEqual([
      { type: 'ticket.submit', ticketId: 't1', text: 'run the tests', origin: 'user' },
      { type: 'staff.hire', agentId: 'desk-t1-1', subagentType: 'main-loop', description: 'run the tests', teammate: false, background: false },
      { type: 'staff.role', agentId: 'desk-t1-1', role: 'generalist' },
      { type: 'activity', agentId: 'desk-t1-1', kind: 'shell', tool: 'Bash' },
      { type: 'task.start', taskId: 'b1', kind: 'shell', ticketId: 't1', description: 'Run tests', role: 'test-runner' },
      { type: 'staff.done', agentId: 'desk-t1-1', status: 'completed', durationMs: 20 },
      { type: 'ticket.done', ticketId: 't1', durationMs: 30, aborted: false },
    ])
    t.prompt({ text: NOTE('b1'), kind: 'task-notification' }, 5020)
    t.turnComplete({ durationMs: 1000, isAborted: false }, 6020)
    expect(t.drain()).toEqual([
      { type: 'task.done', taskId: 'b1', status: 'completed', durationMs: 5000 },
      { type: 'ticket.submit', ticketId: 't2', text: 'Background command "npm test" completed (exit code 0)', origin: 'task', taskIds: ['b1'], parentTicketId: 't1' },
      { type: 'ticket.done', ticketId: 't2', durationMs: 6000, aborted: false },
    ])
  })

  test('a task with no rule is classified among background roles', async () => {
    const t = new Town(ids())
    const call = { tool: 'Bash', tool_use_id: 'u', input: { command: 'sleep 3; echo done' } }
    t.toolEnd(call, { ok: true, result: { backgroundTaskId: 'b2' } }, 0)
    const [job] = t.takeJobs()
    expect(job?.kind).toBe('task-role')
    t.classified(job!, 'nonsense')
    expect(t.drain().at(-1)).toEqual({ type: 'task.role', taskId: 'b2', role: 'background-worker' })
  })

  test('a task a subagent started ends by its own notification, by TaskStop, or when the subagent is over', async () => {
    const t = new Town(ids())
    t.hire({ subagentType: 'general-purpose', description: 'Accounting', prompt: 'x', background: true }, { agentId: 'a1' }, 0)
    t.hire({ subagentType: 'general-purpose', description: 'Legal', prompt: 'x', background: true }, { agentId: 'a2' }, 0)
    const bg = (id: string, agentId: string) =>
      t.toolEnd({ tool: 'Bash', tool_use_id: `u-${id}`, agentId, input: { command: 'sleep 40', run_in_background: true } }, { ok: true, result: { backgroundTaskId: id } }, 0)
    bg('b1', 'a1')
    bg('b2', 'a1')
    bg('b3', 'a2')
    t.drain()
    expect(t.hasAgentTasks).toBe(true)

    t.subagentNotified(NOTE('b1'), 1000)
    t.toolEnd({ tool: 'TaskStop', tool_use_id: 'u9', agentId: 'a2', input: { task_id: 'b3' } }, { ok: true, result: {} }, 1500)
    expect(t.drain().map(e => [e.type, e.taskId, e.status])).toEqual([
      ['task.done', 'b1', 'completed'],
      ['task.done', 'b3', 'killed'],
    ])

    t.agentsSettled([{ id: 'a1', status: 'running' }], 2000)
    expect(t.drain()).toEqual([])
    t.agentsSettled([{ id: 'a1', status: 'completed' }], 3000)
    expect(t.drain()).toEqual([{ type: 'task.done', taskId: 'b2', status: 'completed', durationMs: 3000 }])
    expect(t.hasAgentTasks).toBe(false)
  })

  test('Monitor and Workflow get their roles by tool', async () => {
    const t = new Town(ids())
    t.toolEnd({ tool: 'Monitor', tool_use_id: 'u1', input: { description: 'watch logs' } }, { ok: true, result: { taskId: 'm1' } }, 0)
    t.toolEnd({ tool: 'Workflow', tool_use_id: 'u2', input: {} }, { ok: true, result: { taskId: 'w1', workflowName: 'review' } }, 0)
    expect(t.drain().map(e => [e.kind, e.role])).toEqual([
      ['monitor', 'log-monitor'],
      ['workflow', 'workflow-coordinator'],
    ])
  })

  test('cron and wakeup schedules, and a scheduled ticket', async () => {
    const t = new Town(ids())
    t.toolEnd(
      { tool: 'CronCreate', tool_use_id: 'u1', input: { cron: '0 9 * * *', prompt: 'Check the build status' } },
      { ok: true, result: { id: 'c1', recurring: true, nextFireAt: 1793990000000 } },
      0,
    )
    t.toolEnd(
      { tool: 'ScheduleWakeup', tool_use_id: 'u2', input: { delaySeconds: 600, prompt: 'Look at CI again' } },
      { ok: true, result: { scheduledFor: '2026-11-09T10:00:00Z' } },
      0,
    )
    expect(t.drain()).toEqual([
      { type: 'schedule.create', scheduleId: 'c1', text: 'Check the build status', recurring: true, nextRunTs: 1793990000000 },
      { type: 'schedule.create', scheduleId: 'u2', text: 'Look at CI again', recurring: false, nextRunTs: Date.parse('2026-11-09T10:00:00Z') },
    ])
    t.prompt({ text: 'Look at CI again', kind: 'scheduled-trigger' }, 100)
    expect(t.drain()).toEqual([
      { type: 'ticket.submit', ticketId: 't1', text: 'Look at CI again', origin: 'schedule', scheduleId: 'u2' },
      { type: 'schedule.delete', scheduleId: 'u2' },
    ])
    t.toolEnd({ tool: 'CronDelete', tool_use_id: 'u3', input: { id: 'c1' } }, { ok: true, result: {} }, 200)
    expect(t.drain()).toEqual([{ type: 'schedule.delete', scheduleId: 'c1' }])
  })

  test('a refused call starts nothing', async () => {
    const t = new Town(ids())
    t.toolEnd({ tool: 'Bash', tool_use_id: 'u', input: { command: 'npm test' } }, { ok: false, result: { backgroundTaskId: 'b9' } }, 0)
    expect(t.drain()).toEqual([])
  })
})

describe('staff', () => {
  const spawn = { subagentType: 'general-purpose', description: 'Tiny probe subagent', prompt: 'Reply ok', background: true }

  test('hire with the resolved model, then role by classification', async () => {
    const t = new Town(ids())
    t.hire(spawn, { agentId: 'a1', model: 'claude-haiku-5-5' }, 0)
    expect(t.drain()).toEqual([
      { type: 'staff.hire', agentId: 'a1', subagentType: 'general-purpose', description: 'Tiny probe subagent', teammate: false, background: true, model: 'claude-haiku-5-5' },
    ])
    const [job] = t.takeJobs()
    t.classified(job!, 'code-reviewer')
    expect(t.drain()).toEqual([{ type: 'staff.role', agentId: 'a1', role: 'code-reviewer' }])
  })

  test("a turn that starts with an agent's message says who it is from", async () => {
    const t = new Town(ids())
    t.hire(spawn, { agentId: 'a1' }, 0)
    t.drain()
    t.prompt({ text: '<agent-message from="a1">\n[Subagent hand-back] The text below is the final report…', kind: 'peer' }, 10)
    t.turnComplete({ durationMs: 5, isAborted: false }, 15)
    t.prompt({ text: '<agent-message from="zzz">\nhello', kind: 'peer' }, 20)
    expect(t.drain().filter(e => e.type === 'ticket.submit').map(e => [e.text, e.fromAgentId, e.messageKind])).toEqual([
      ['', 'a1', 'report'],
      ['', undefined, 'message'],
    ])
  })

  test('a resumed agent is hired again with the role it had, and no new classification', async () => {
    const t = new Town(ids())
    t.hire(spawn, { agentId: 'a1' }, 0)
    t.classified(t.takeJobs()[0]!, 'project-manager')
    t.turnComplete({ agentId: 'a1', durationMs: 10, isAborted: false }, 10)
    t.drain()
    t.hire({ ...spawn, parentAgentId: 'a2' }, { agentId: 'a1' }, 20)
    expect(t.takeJobs()).toEqual([])
    expect(t.drain().map(e => [e.type, e.role])).toEqual([
      ['staff.hire', undefined],
      ['staff.role', 'project-manager'],
    ])
  })

  test('a custom agent named after a role needs no classification', async () => {
    const t = new Town(ids())
    t.hire({ ...spawn, subagentType: 'security-engineer' }, { agentId: 'a1' }, 0)
    expect(types(t)).toEqual(['staff.hire', 'staff.role'])
    expect(t.takeJobs()).toEqual([])
  })

  test('events that beat the hire are held and replayed; strangers are dropped', async () => {
    const t = new Town(ids())
    t.toolStart({ tool: 'Read', agentId: 'a1' }, 0)
    t.toolStart({ tool: 'Read', agentId: 'fork-x' }, 0)
    expect(t.drain()).toEqual([])
    t.hire(spawn, { agentId: 'a1' }, 5)
    expect(types(t)).toEqual(['staff.hire', 'activity'])
    t.tick(HOLD_MS + 10)
    t.hire(spawn, { agentId: 'fork-x' }, HOLD_MS + 20)
    expect(types(t)).toEqual(['staff.hire'])
  })

  test('staff done carries status and the model change', async () => {
    const t = new Town(ids())
    t.hire(spawn, { agentId: 'a1', model: 'claude-haiku-5-5' }, 0)
    t.drain()
    t.turnComplete({ agentId: 'a1', durationMs: 5040, isAborted: false, reason: 'answer', model: 'claude-sonnet-5-5' }, 5040)
    expect(t.drain()).toEqual([
      { type: 'model.update', agentId: 'a1', model: 'claude-sonnet-5-5' },
      { type: 'staff.done', agentId: 'a1', status: 'completed', durationMs: 5040 },
    ])
  })

  test('messages resolve the receiver by ID or name', async () => {
    const t = new Town(ids())
    t.hire({ ...spawn, name: 'reviewer' }, { agentId: 'a1' }, 0)
    t.hire(spawn, { agentId: 'a2' }, 0)
    t.drain()
    t.message({ to: 'reviewer', agentId: 'a2' }, 1)
    t.message({ to: 'a2' }, 1)
    t.message({ to: '*', agentId: 'a1' }, 1)
    t.message({ to: 'team-lead', agentId: 'a1' }, 1)
    expect(t.drain()).toEqual([
      { type: 'message.send', fromAgentId: 'a2', toAgentId: 'a1' },
      { type: 'message.send', toAgentId: 'a2' },
      { type: 'message.send', fromAgentId: 'a1', broadcast: true },
      { type: 'message.send', fromAgentId: 'a1', toName: 'team-lead' },
    ])
  })
})

describe('reconnecting', () => {
  test('reopen introduces the session again with its latest model', async () => {
    const t = new Town(ids())
    t.open({ projectName: 'demo', surface: 'terminal', ccVersion: '2.1.319', model: 'claude-opus-5-5' })
    t.drain()
    t.reopen()
    expect(t.drain()).toEqual([
      { type: 'session.open', projectName: 'demo', surface: 'terminal', ccVersion: '2.1.319', model: 'claude-opus-5-5' },
    ])
  })
})

describe('plugin version', () => {
  test('session.open carries town-link\'s version, again when reopened', async () => {
    const t = new Town(ids())
    t.open({ projectName: 'demo', surface: 'terminal', ccVersion: '2.1.319', pluginVersion: '1.0.3' })
    expect(t.drain()).toEqual([{ type: 'session.open', projectName: 'demo', surface: 'terminal', ccVersion: '2.1.319', pluginVersion: '1.0.3' }])
    t.reopen()
    expect(t.drain()).toEqual([{ type: 'session.open', projectName: 'demo', surface: 'terminal', ccVersion: '2.1.319', pluginVersion: '1.0.3' }])
  })
})

describe('approvals', () => {
  test('a wait in auto mode is marked so the app stays quiet', async () => {
    const t = new Town(ids())
    t.setPermissionMode('auto')
    t.ask({ tool_use_id: 'u1', tool: 'Bash' }, 0)
    t.tick(APPROVAL_DELAY_MS)
    expect(t.drain()).toEqual([{ type: 'approval.wait', approvalId: 'u1', tool: 'Bash', autoMode: true }])
  })

  test('auto mode reported after the ask still marks the wait', async () => {
    const t = new Town(ids())
    t.ask({ tool_use_id: 'u1', tool: 'Bash' }, 0)
    t.setPermissionMode('auto')
    t.tick(APPROVAL_DELAY_MS)
    expect(t.drain()).toEqual([{ type: 'approval.wait', approvalId: 'u1', tool: 'Bash', autoMode: true }])
  })

  test('an ask settled quickly by auto mode shows nothing', async () => {
    const t = new Town(ids())
    t.ask({ tool_use_id: 'u1', tool: 'Bash' }, 0)
    t.tick(1500)
    t.toolEnd({ tool: 'Bash', tool_use_id: 'u1', input: {} }, { ok: true, result: {} }, 1500)
    expect(t.drain()).toEqual([])
  })

  test('an ask still open after the delay waits, then ends', async () => {
    const t = new Town(ids())
    t.ask({ tool_use_id: 'u1', tool: 'Bash' }, 0)
    t.tick(APPROVAL_DELAY_MS)
    t.tick(APPROVAL_DELAY_MS + 250)
    t.toolEnd({ tool: 'Bash', tool_use_id: 'u1', input: {} }, { ok: false, result: {} }, 9000)
    expect(t.drain()).toEqual([
      { type: 'approval.wait', approvalId: 'u1', tool: 'Bash' },
      { type: 'approval.end', approvalId: 'u1', outcome: 'denied' },
    ])
  })
})

describe('compaction', () => {
  test('the main conversation compacting shows, with the sizes', async () => {
    const t = new Town(ids())
    expect(t.compactStart({ trigger: 'manual' })).toBe(true)
    t.compactEnd({ tokensBefore: 152_340, tokensAfter: 20_110 })
    expect(t.drain()).toEqual([
      { type: 'compact.start', trigger: 'manual' },
      { type: 'compact.end', outcome: 'done', tokensBefore: 152_340, tokensAfter: 20_110 },
    ])
  })

  test('a subagent, a fork or a precompute compacting shows nothing', async () => {
    const t = new Town(ids())
    expect(t.compactStart({ trigger: 'auto', agentId: 'a1' })).toBe(false)
    expect(t.compactStart({ trigger: 'precompute' })).toBe(false)
    t.compactEnd({ tokensBefore: 1, tokensAfter: 1 })
    expect(t.drain()).toEqual([])
  })

  test('a skipped or failed compaction ends without sizes', async () => {
    const t = new Town(ids())
    t.compactStart({ trigger: 'auto' })
    t.compactEnd({ skip: 'blocked by a hook' })
    t.compactStart({ trigger: 'auto' })
    t.compactEnd(undefined)
    expect(t.drain()).toEqual([
      { type: 'compact.start', trigger: 'auto' },
      { type: 'compact.end', outcome: 'skipped' },
      { type: 'compact.start', trigger: 'auto' },
      { type: 'compact.end', outcome: 'failed' },
    ])
  })
})

describe('surviving a reload', () => {
  test('a ticket open before a reload is reported after it', async () => {
    const before = new Town(ids())
    before.prompt({ text: 'fix it', kind: 'user' }, 1000)
    before.hire({ subagentType: 'Explore', description: 'look' }, { agentId: 'a1' }, 1500)
    before.drain()
    const saved = JSON.parse(JSON.stringify(before.save()))

    const after = new Town(ids())
    after.restore(saved)
    after.turnComplete({ agentId: 'a1', durationMs: 0, isAborted: false }, 5000)
    after.turnComplete({ durationMs: 9000, isAborted: false }, 10_000)
    const out = after.drain()
    expect(out.map(e => e.type)).toEqual(['staff.done', 'ticket.done'])
    expect(out[1]).toMatchObject({ ticketId: 't1', durationMs: 9000, aborted: false })
  })

  test('something that is not a saved tracker is ignored', async () => {
    const t = new Town(ids())
    t.restore({ v: 99, ticket: { id: 'x' } })
    t.turnComplete({ durationMs: 1, isAborted: false }, 1)
    expect(t.drain()).toEqual([])
  })
})

describe('context window', () => {
  test('the last turn\'s new tokens, without cache reads, are sent with the context', () => {
    const t = new Town(ids())
    t.context({ tokens: 84000, window: 200000, percent: 42 })
    t.drain()
    t.turnTokens({ input_tokens: 500, output_tokens: 2000, cache_read_input_tokens: 130000, cache_creation_input_tokens: 5000 })
    expect(t.drain()).toEqual([{ type: 'context.update', tokens: 84000, window: 200000, percent: 42, lastTurnTokens: 7500 }])
    t.turnTokens({ input_tokens: 0, output_tokens: 0, cache_read_input_tokens: 0, cache_creation_input_tokens: 0 })
    t.turnTokens(undefined)
    expect(t.drain()).toEqual([])
  })

  test('the fill, the window and the effort are sent when a whole percent moves', async () => {
    const t = new Town(ids())
    t.context({ window: 200_000 })
    t.effort('high')
    t.context({ tokens: 84_100, window: 200_000, percent: 42 })
    t.context({ tokens: 84_900, window: 200_000, percent: 42 })
    t.effort(7) // a number budget is not shown
    expect(t.drain()).toEqual([
      { type: 'context.update', window: 200_000 },
      { type: 'context.update', window: 200_000, effort: 'high' },
      { type: 'context.update', tokens: 84_100, window: 200_000, percent: 42, effort: 'high' },
    ])
  })

  test('the app starting late hears the context and the open ticket again', async () => {
    const t = new Town(ids())
    t.open({ projectName: 'p', surface: 'terminal', ccVersion: '2' })
    t.context({ tokens: 10, window: 100, percent: 10 })
    t.prompt({ text: 'fix it', kind: 'user' }, 0)
    t.drain()
    t.reopen()
    expect(t.drain().map(e => e.type)).toEqual(['session.open', 'context.update', 'ticket.submit'])
  })
})
