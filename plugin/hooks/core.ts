// town-link core: turns Claude Code events into agent-town protocol events.
//
// Pure logic with no `$`: register.ts feeds it what the hooks see, and it
// pushes protocol events (without the envelope) into `out`. Timing comes from
// the `now` passed in, so tests can drive it. See docs/architecture.md
// ("Event mapping") and docs/verification.md for why each rule exists.

import {
  BACKGROUND_FALLBACK,
  BACKGROUND_ROLES,
  BACKGROUND_RULES,
  STAFF_FALLBACK,
  STAFF_ROLES,
  TASK_FALLBACK,
  TASK_TYPES,
} from './catalog'

export type Ev = { type: string; [field: string]: unknown }

/** A classification the caller should run in the background. */
export type ClassifyJob = {
  kind: 'task-type' | 'staff-role' | 'task-role' | 'task-title'
  /** ticketId, agentId or taskId */
  id: string
  text: string
  labels: readonly string[]
  fallback: string
}

export const TEXT_MAX = 200
/** How long to hold events from an agentId not yet seen in agent.spawn. */
export const HOLD_MS = 1000
/** How long an `ask` must stay unsettled before the app shows a wait. */
export const APPROVAL_DELAY_MS = 5000
/** A Stop-hook return and an auto-continuation this close are one return. */
const RETURN_DEDUP_MS = 5000

const cut = (s: unknown, n = TEXT_MAX) => (typeof s === 'string' ? s.slice(0, n) : '')

type Origin = 'user' | 'schedule' | 'task' | 'unknown'
type Ticket = { id: string; origin: Origin; startTs: number; returned: boolean; lastReturnTs?: number; text?: string; title?: string }
type Staff = { name?: string; hireTs: number }
type Task = { startTs: number; ticketId?: string }
type Approval = { tool: string; agentId?: string; askTs: number; waited: boolean; autoMode: boolean }

export type ToolOutcome = { ok: boolean; result: Record<string, unknown> }

// ---- Pure helpers -------------------------------------------------------

/** A hard cap only: Haiku is asked for 20 columns, and the app scrolls a wider title. */
export const TITLE_MAX = 60

/** A model's title reply as one short line: no quotes, labels or end period. */
export function cleanTitle(reply: string | undefined): string {
  let s = (reply ?? '').split(/\r?\n/).map(l => l.trim()).find(Boolean) ?? ''
  const unquote = (x: string) => x.replace(/^["'“”「『*]+|["'“”」』*]+$/g, '').trim()
  s = unquote(unquote(s).replace(/^(title|標題)\s*[:：]\s*/i, '')).replace(/[.。]$/, '').trim()
  return s.length > TITLE_MAX ? s.slice(0, TITLE_MAX - 1) + '…' : s
}

/** Map a tool name to an activity kind. */
export function activityKind(tool: string): string {
  if (tool.startsWith('mcp__')) return 'mcp'
  if (['Read', 'Grep', 'Glob', 'LS', 'NotebookRead', 'LSP'].includes(tool)) return 'read'
  if (['Edit', 'Write', 'MultiEdit', 'NotebookEdit'].includes(tool)) return 'edit'
  if (['Bash', 'PowerShell', 'Monitor'].includes(tool)) return 'shell'
  if (['WebFetch', 'WebSearch'].includes(tool)) return 'web'
  return 'other'
}

function escapeRe(s: string) {
  return s.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')
}

/** The background role for a shell command by word rules, or undefined. */
export function shellRole(command: string): string | undefined {
  const text = command.toLowerCase()
  for (const [role, words] of BACKGROUND_RULES) {
    for (const w of words) {
      // Whole words only: "test" must not match "latest".
      if (new RegExp(`(^|[^a-z0-9])${escapeRe(w.toLowerCase())}($|[^a-z0-9])`).test(text)) return role
    }
  }
  return undefined
}

/** Finished tasks named in task-notification text. */
export function parseNotifications(text: string): { taskId: string; status: string }[] {
  const out: { taskId: string; status: string }[] = []
  const blocks = text.match(/<task-notification>[\s\S]*?<\/task-notification>/g) ?? []
  for (const b of blocks) {
    const id = /<task-id>([^<]+)<\/task-id>/.exec(b)?.[1]?.trim()
    const status = /<status>([^<]+)<\/status>/.exec(b)?.[1]?.trim() ?? 'completed'
    if (id) out.push({ taskId: id, status })
  }
  return out
}

/** Protocol task status from a notification status. */
export function taskStatus(s: string): 'completed' | 'failed' | 'killed' {
  const v = s.toLowerCase()
  if (v === 'failed' || v === 'error') return 'failed'
  if (v === 'killed' || v === 'stopped' || v === 'cancelled' || v === 'canceled') return 'killed'
  return 'completed'
}

/** The project identity: a normalized remote URL, else the root path. */
export function projectIdentity(remote: string | null | undefined, root: string): { identity: string; name: string } {
  if (remote) {
    let r = remote.trim()
    const scp = /^[^@/]+@([^:/]+):(.+)$/.exec(r) // git@host:owner/repo
    if (scp) r = `${scp[1]}/${scp[2]}`
    r = r.replace(/^[a-z+]+:\/\//i, '').replace(/^[^@/]+@/, '')
    r = r.replace(/\/+$/, '').replace(/\.git$/, '')
    const name = r.split('/').pop() || root.split('/').pop() || 'project'
    return { identity: r, name }
  }
  const clean = root.replace(/\/+$/, '')
  return { identity: clean, name: clean.split('/').pop() || 'project' }
}

// ---- The tracker --------------------------------------------------------

export class Town {
  readonly out: Ev[] = []
  readonly jobs: ClassifyJob[] = []

  private ticket: Ticket | undefined // open ticket
  private lastTicket: Ticket | undefined // most recently closed
  private chiefModel: string | undefined
  private staff = new Map<string, Staff>()
  private staffModels = new Map<string, string>()
  private held = new Map<string, { until: number; replay: (() => void)[] }>()
  private tasks = new Map<string, Task>()
  private schedules = new Map<string, { text: string; recurring: boolean }>()
  private approvals = new Map<string, Approval>()
  /** The session's permission mode, as the last classic hook reported it. */
  private permissionMode?: string
  private counter = 0
  private readonly newId: () => string

  constructor(newId?: () => string) {
    this.newId = newId ?? (() => `t${++this.counter}`)
  }

  private emit(ev: Ev) {
    this.out.push(ev)
  }

  /** Take what has been emitted so far. */
  drain(): Ev[] {
    return this.out.splice(0, this.out.length)
  }

  takeJobs(): ClassifyJob[] {
    return this.jobs.splice(0, this.jobs.length)
  }

  // -- session

  private openFields?: { projectName: string; surface: string; ccVersion: string; model?: string }

  open(fields: { projectName: string; surface: string; ccVersion: string; model?: string }) {
    this.openFields = fields
    this.chiefModel = fields.model
    this.emit({ type: 'session.open', ...fields })
  }

  /** The app appeared after this session opened: introduce the session again, with its latest
   *  model, its context and the ticket it is working on (picked up from the inbox, no call). */
  reopen() {
    if (!this.openFields) return
    const model = this.chiefModel ?? this.openFields.model
    this.emit({ type: 'session.open', ...this.openFields, ...(model ? { model } : {}) })
    if (this.lastContext) this.emit({ ...this.lastContext })
    if (this.ticket) this.emit({ type: 'ticket.submit', ticketId: this.ticket.id, text: this.ticket.text ?? '', origin: 'unknown' })
    if (this.ticket?.title) this.emit({ type: 'ticket.title', ticketId: this.ticket.id, title: this.ticket.title })
  }

  // -- context window

  private ctx: { tokens?: number; window?: number; percent?: number; effort?: string; lastTurnTokens?: number } = {}
  private lastContext?: Ev

  /** session.measure: the live context window's fill. */
  context(c: { tokens?: number; window?: number; percent?: number } | undefined) {
    if (!c) return
    const n = (v: unknown) => (typeof v === 'number' && Number.isFinite(v) && v >= 0 ? Math.round(v) : undefined)
    this.ctx = { ...this.ctx, tokens: n(c.tokens) ?? this.ctx.tokens, window: n(c.window) ?? this.ctx.window, percent: n(c.percent) ?? this.ctx.percent }
    this.emitContext()
  }

  /** turn.step on the main loop: the effort the request asks for. */
  effort(level: unknown) {
    if (typeof level !== 'string' || !['low', 'medium', 'high', 'xhigh', 'max'].includes(level)) return
    this.ctx = { ...this.ctx, effort: level }
    this.emitContext()
  }

  /** turn.complete on the main loop: the tokens the turn added (new input, cache writes, output); cache reads are left out. */
  turnTokens(u: { input_tokens?: number; output_tokens?: number; cache_read_input_tokens?: number; cache_creation_input_tokens?: number } | undefined) {
    if (!u) return
    const total = [u.input_tokens, u.output_tokens, u.cache_creation_input_tokens]
      .reduce<number>((a, v) => a + (typeof v === 'number' && Number.isFinite(v) && v > 0 ? v : 0), 0)
    if (total <= 0) return
    this.ctx = { ...this.ctx, lastTurnTokens: Math.round(total) }
    this.emitContext()
  }

  private emitContext() {
    const { tokens, window, percent, effort, lastTurnTokens } = this.ctx
    if (window === undefined && effort === undefined && lastTurnTokens === undefined) return
    const ev: Ev = {
      type: 'context.update',
      ...(tokens !== undefined ? { tokens } : {}),
      ...(window !== undefined ? { window } : {}),
      ...(percent !== undefined ? { percent } : {}),
      ...(effort ? { effort } : {}),
      ...(lastTurnTokens !== undefined ? { lastTurnTokens } : {}),
    }
    const last = this.lastContext
    // The fill moves by tokens every turn; a whole percent, a new window, effort or last-turn count is news.
    if (last && last.window === ev.window && last.percent === ev.percent && last.effort === ev.effort && last.lastTurnTokens === ev.lastTurnTokens) return
    this.lastContext = ev
    this.emit(ev)
  }

  close(reason: string) {
    const known = ['clear', 'resume', 'logout', 'prompt_input_exit']
    this.emit({ type: 'session.close', reason: known.includes(reason) ? reason : 'other' })
  }

  heartbeat() {
    this.emit({ type: 'heartbeat' })
  }

  // -- tickets

  /** prompt.submit. Returns nothing; emits ticket, task and schedule events. */
  prompt(e: { text: string; kind: string; turnId?: string; isMeta?: boolean }, now: number) {
    const text = e.text ?? ''

    if (e.kind === 'task-notification') {
      const finished = this.finishTasks(parseNotifications(text), now)
      if (e.turnId) return
      if (finished.length > 0) {
        const first = this.doneTasks.get(finished[0] ?? '')
        const start = Math.min(...finished.map(id => this.doneTasks.get(id)?.startTs ?? now))
        this.openTicket('task', text, start, {
          taskIds: finished,
          ...(first?.ticketId ? { parentTicketId: first.ticketId } : {}),
          text: cut(this.summaryOf(text) || 'Background task finished'),
        })
        return
      }
      this.openTicket('unknown', this.summaryOf(text) || text, now)
      return
    }

    if (e.turnId) return // delivered into a running turn: adds to the open ticket

    if (e.kind === 'auto-continuation') {
      this.returnTicket(text, now)
      return
    }

    if (e.kind === 'scheduled-trigger') {
      let scheduleId: string | undefined
      for (const [id, s] of this.schedules) {
        if (s.text && text.includes(s.text.slice(0, 60))) {
          scheduleId = id
          break
        }
      }
      this.openTicket('schedule', text, now, scheduleId ? { scheduleId } : {})
      if (scheduleId && this.schedules.get(scheduleId)?.recurring === false) {
        this.schedules.delete(scheduleId)
        this.emit({ type: 'schedule.delete', scheduleId })
      }
      return
    }

    if (e.kind === 'composer' || e.kind === 'sdk' || e.kind === 'bridge') {
      const t = this.openTicket('user', text, now)
      if (!e.isMeta && text.trim()) {
        this.jobs.push({ kind: 'task-type', id: t.id, text: text.slice(0, 600), labels: TASK_TYPES, fallback: TASK_FALLBACK })
        this.jobs.push({ kind: 'task-title', id: t.id, text: text.slice(0, 600), labels: [], fallback: '' })
      }
      return
    }

    this.openTicket('unknown', text, now)
  }

  private summaryOf(text: string): string {
    return /<summary>([^<]*)<\/summary>/.exec(text)?.[1]?.trim() ?? ''
  }

  private openTicket(origin: Origin, text: string, startTs: number, extra: Record<string, unknown> = {}): Ticket {
    const t: Ticket = { id: this.newId(), origin, startTs, returned: false, text: cut(text) }
    this.ticket = t
    this.emit({ type: 'ticket.submit', ticketId: t.id, text: cut(text), origin, ...extra })
    return t
  }

  private returnTicket(reason: string, now: number) {
    const t = this.ticket ?? this.lastTicket
    if (!t) return
    if (t.lastReturnTs !== undefined && now - t.lastReturnTs < RETURN_DEDUP_MS) {
      this.ticket = t
      return
    }
    t.returned = true
    t.lastReturnTs = now
    this.ticket = t
    this.emit({ type: 'ticket.return', ticketId: t.id, ...(reason ? { reason: cut(reason) } : {}) })
  }

  /** classic.Stop backup: the Stop hook chain blocked the end of the turn. */
  stopBlocked(reason: string | undefined, now: number) {
    this.returnTicket(reason ?? '', now)
  }

  /** turn.complete. */
  turnComplete(e: { agentId?: string; durationMs: number; isAborted: boolean; reason?: string; model?: string }, now: number) {
    if (e.agentId) {
      this.whenKnown(e.agentId, now, () => {
        const s = this.staff.get(e.agentId!)!
        this.modelChange(e.agentId, e.model)
        const status = e.isAborted ? 'aborted' : e.reason === 'error' ? 'failed' : 'completed'
        this.emit({ type: 'staff.done', agentId: e.agentId, status, durationMs: Math.max(0, now - s.hireTs) })
      })
      return
    }
    this.modelChange(undefined, e.model)
    const t = this.ticket
    if (!t) return
    const durationMs = t.origin === 'user' && !t.returned ? e.durationMs : Math.max(0, now - t.startTs)
    this.emit({ type: 'ticket.done', ticketId: t.id, durationMs: Math.round(durationMs), aborted: e.isAborted })
    this.lastTicket = t
    this.ticket = undefined
  }

  private modelChange(agentId: string | undefined, model: string | undefined) {
    if (!model) return
    const last = agentId ? this.staffModels.get(agentId) : this.chiefModel
    if (last === model) return
    if (agentId) this.staffModels.set(agentId, model)
    else this.chiefModel = model
    this.emit({ type: 'model.update', ...(agentId ? { agentId } : {}), model })
  }

  // -- staff

  /** agent.spawn, after next(e) resolved. */
  hire(
    e: { subagentType?: string; name?: string; description?: string; prompt?: string; parentAgentId?: string; background?: boolean },
    r: { agentId?: string; teammateId?: string; model?: string },
    now: number,
  ) {
    if (!r.agentId) return
    const agentId = r.agentId
    this.staff.set(agentId, { name: e.name, hireTs: now })
    if (r.model) this.staffModels.set(agentId, r.model)
    const parent = e.parentAgentId && this.staff.has(e.parentAgentId) ? e.parentAgentId : undefined
    this.emit({
      type: 'staff.hire',
      agentId,
      ...(parent ? { parentAgentId: parent } : {}),
      subagentType: e.subagentType || 'general-purpose',
      ...(e.name ? { name: e.name } : {}),
      description: cut(e.description || e.prompt),
      teammate: !!r.teammateId,
      background: !!e.background,
      ...(r.model ? { model: r.model } : {}),
    })
    const type = e.subagentType ?? ''
    if (STAFF_ROLES.includes(type)) {
      this.emit({ type: 'staff.role', agentId, role: type })
    } else {
      const text = [e.subagentType, e.name, e.description, (e.prompt ?? '').slice(0, 400)].filter(Boolean).join('\n')
      this.jobs.push({ kind: 'staff-role', id: agentId, text, labels: STAFF_ROLES, fallback: STAFF_FALLBACK })
    }
    // Events from this agent that arrived before its hire.
    const h = this.held.get(agentId)
    this.held.delete(agentId)
    h?.replay.forEach(f => f())
  }

  /** Run `f` now if the agent is known (or main), hold it briefly otherwise. */
  private whenKnown(agentId: string | undefined, now: number, f: () => void) {
    if (!agentId || this.staff.has(agentId)) return f()
    const h = this.held.get(agentId) ?? { until: now + HOLD_MS, replay: [] }
    if (h.replay.length < 50) h.replay.push(f)
    this.held.set(agentId, h)
  }

  // -- tools

  /** tool.call, before next(e). */
  toolStart(e: { tool: string; agentId?: string }, now: number) {
    if (e.tool === 'Agent' || e.tool === 'Task') return // the hire shows it
    this.whenKnown(e.agentId, now, () => {
      this.emit({ type: 'activity', ...(e.agentId ? { agentId: e.agentId } : {}), kind: activityKind(e.tool), tool: e.tool })
    })
  }

  /** tool.check returned `ask` for a person. */
  ask(e: { tool_use_id: string; tool: string; agentId?: string }, now: number) {
    if (e.agentId && !this.staff.has(e.agentId) && !this.held.has(e.agentId)) return
    this.approvals.set(e.tool_use_id, { tool: e.tool, agentId: e.agentId, askTs: now, waited: false, autoMode: this.permissionMode === 'auto' })
  }

  /** The permission mode from a classic hook's input. In auto mode a classifier answers asks. */
  setPermissionMode(mode: string | undefined) {
    if (mode) this.permissionMode = mode
  }

  /** tool.call, after next(e) settled. */
  toolEnd(
    e: { tool: string; tool_use_id: string; agentId?: string; input: Record<string, unknown> },
    o: ToolOutcome,
    now: number,
  ) {
    const a = this.approvals.get(e.tool_use_id)
    if (a) {
      this.approvals.delete(e.tool_use_id)
      if (a.waited) this.emit({ type: 'approval.end', approvalId: e.tool_use_id, outcome: o.ok ? 'allowed' : 'denied' })
    }
    if (!o.ok) return
    if (e.agentId && !this.staff.has(e.agentId)) return
    const r = o.result
    const inp = e.input
    const str = (v: unknown) => (typeof v === 'string' ? v : undefined)

    if (e.tool === 'Bash' && str(r.backgroundTaskId)) {
      const command = str(inp.command) ?? ''
      this.taskStart(str(r.backgroundTaskId)!, 'shell', e.agentId, str(inp.description) || command, shellRole(command), now)
    } else if (e.tool === 'Monitor' && str(r.taskId)) {
      this.taskStart(str(r.taskId)!, 'monitor', e.agentId, str(inp.description) || str(inp.command) || 'Monitor', 'log-monitor', now)
    } else if (e.tool === 'Workflow' && str(r.taskId)) {
      const desc = str(r.workflowName) || str(inp.name) || 'Workflow'
      this.taskStart(str(r.taskId)!, 'workflow', e.agentId, desc, 'workflow-coordinator', now)
    } else if (e.tool === 'CronCreate' && str(r.id)) {
      const id = str(r.id)!
      const recurring = typeof r.recurring === 'boolean' ? r.recurring : inp.recurring !== false
      const text = str(inp.prompt) ?? ''
      this.schedules.set(id, { text, recurring })
      const next = typeof r.nextFireAt === 'number' ? r.nextFireAt : Date.parse(str(r.nextFireAt) ?? '')
      this.emit({ type: 'schedule.create', scheduleId: id, text: cut(text), recurring, ...(Number.isFinite(next) ? { nextRunTs: next } : {}) })
    } else if (e.tool === 'CronDelete' && str(inp.id)) {
      const id = str(inp.id)!
      this.schedules.delete(id)
      this.emit({ type: 'schedule.delete', scheduleId: id })
    } else if (e.tool === 'ScheduleWakeup') {
      if (inp.stop === true) {
        for (const [id, s] of this.schedules) {
          if (!s.recurring) {
            this.schedules.delete(id)
            this.emit({ type: 'schedule.delete', scheduleId: id })
          }
        }
        return
      }
      const text = str(inp.prompt) ?? ''
      this.schedules.set(e.tool_use_id, { text, recurring: false })
      const at = r.scheduledFor
      const next = typeof at === 'number' ? at : Date.parse(str(at) ?? '')
      this.emit({
        type: 'schedule.create',
        scheduleId: e.tool_use_id,
        text: cut(text),
        recurring: false,
        ...(Number.isFinite(next) ? { nextRunTs: next } : {}),
      })
    }
  }

  // -- background tasks

  private doneTasks = new Map<string, Task>()

  private taskStart(taskId: string, kind: string, agentId: string | undefined, description: string, role: string | undefined, now: number) {
    this.tasks.set(taskId, { startTs: now, ticketId: this.ticket?.id })
    this.emit({
      type: 'task.start',
      taskId,
      kind,
      ...(agentId ? { agentId } : {}),
      ...(this.ticket ? { ticketId: this.ticket.id } : {}),
      description: cut(description),
      ...(role ? { role } : {}),
    })
    if (!role) {
      this.jobs.push({ kind: 'task-role', id: taskId, text: description.slice(0, 600), labels: BACKGROUND_ROLES, fallback: BACKGROUND_FALLBACK })
    }
  }

  /** End known tasks; returns the IDs that were known. */
  private finishTasks(items: { taskId: string; status: string }[], now: number): string[] {
    const ended: string[] = []
    for (const { taskId, status } of items) {
      const t = this.tasks.get(taskId)
      if (!t) continue
      this.tasks.delete(taskId)
      this.doneTasks.set(taskId, t)
      if (this.doneTasks.size > 200) this.doneTasks.delete(this.doneTasks.keys().next().value as string)
      ended.push(taskId)
      this.emit({ type: 'task.done', taskId, status: taskStatus(status), durationMs: Math.max(0, now - t.startTs) })
    }
    return ended
  }

  // -- messages

  /** session.send from the model. */
  message(e: { to: string; agentId?: string }, now: number) {
    this.whenKnown(e.agentId, now, () => {
      const to = e.to ?? ''
      const base: Ev = { type: 'message.send', ...(e.agentId ? { fromAgentId: e.agentId } : {}) }
      if (to === '*') return this.emit({ ...base, broadcast: true })
      if (this.staff.has(to)) return this.emit({ ...base, toAgentId: to })
      for (const [id, s] of this.staff) if (s.name && s.name === to) return this.emit({ ...base, toAgentId: id })
      this.emit({ ...base, toName: cut(to, 80) })
    })
  }

  // -- classification results

  classified(job: ClassifyJob, label: string | undefined) {
    if (job.kind === 'task-title') return this.titled(job.id, label)
    const value = label && job.labels.includes(label) ? label : job.fallback
    if (job.kind === 'task-type') this.emit({ type: 'chief.hat', ticketId: job.id, taskType: value })
    else if (job.kind === 'staff-role') this.emit({ type: 'staff.role', agentId: job.id, role: value })
    else this.emit({ type: 'task.role', taskId: job.id, role: value })
  }

  /** A small model's few words naming a ticket's task. Ignored when empty. */
  titled(ticketId: string, reply: string | undefined) {
    const title = cleanTitle(reply)
    if (!title) return
    for (const t of [this.ticket, this.lastTicket]) if (t?.id === ticketId) t.title = title
    this.emit({ type: 'ticket.title', ticketId, title })
  }

  // -- surviving a reload

  /** What a hot reload of the plugin would lose: open tickets, staff, tasks and waits. JSON data. */
  save(): Record<string, unknown> {
    return {
      v: 1,
      ticket: this.ticket,
      lastTicket: this.lastTicket,
      chiefModel: this.chiefModel,
      staff: [...this.staff],
      staffModels: [...this.staffModels],
      tasks: [...this.tasks],
      doneTasks: [...this.doneTasks],
      schedules: [...this.schedules],
      approvals: [...this.approvals],
      permissionMode: this.permissionMode,
      counter: this.counter,
      compacting: this.compacting,
      openFields: this.openFields,
      ctx: this.ctx,
      lastContext: this.lastContext,
    }
  }

  /** Takes back what `save` returned, after a reload. Anything malformed is left at its default. */
  restore(x: Record<string, unknown>) {
    if (!x || x.v !== 1) return
    // eslint-disable-next-line @typescript-eslint/no-explicit-any
    const map = (v: unknown) => new Map<string, any>(Array.isArray(v) ? (v as [string, unknown][]) : [])
    const obj = <T>(v: unknown) => (v && typeof v === 'object' ? (v as T) : undefined)
    this.ticket = obj<Ticket>(x.ticket)
    this.lastTicket = obj<Ticket>(x.lastTicket)
    this.chiefModel = typeof x.chiefModel === 'string' ? x.chiefModel : undefined
    this.staff = map(x.staff)
    this.staffModels = map(x.staffModels)
    this.tasks = map(x.tasks)
    this.doneTasks = map(x.doneTasks)
    this.schedules = map(x.schedules)
    this.approvals = map(x.approvals)
    this.permissionMode = typeof x.permissionMode === 'string' ? x.permissionMode : undefined
    this.counter = typeof x.counter === 'number' ? x.counter : 0
    this.compacting = x.compacting === true
    this.openFields = obj(x.openFields)
    this.ctx = obj(x.ctx) ?? {}
    this.lastContext = obj(x.lastContext)
  }

  // -- compaction

  private compacting = false

  /** session.compact, before it runs. Only the main conversation's compaction shows; a
   *  subagent's or a fork's (agentId) and a background precompute do not. */
  compactStart(e: { trigger?: string; agentId?: string }): boolean {
    if (e.agentId || e.trigger === 'precompute' || this.compacting) return false
    this.compacting = true
    const trigger = e.trigger === 'manual' || e.trigger === 'auto' ? e.trigger : 'other'
    this.emit({ type: 'compact.start', trigger })
    return true
  }

  /** session.compact, after it ran (r undefined: it threw). */
  compactEnd(r: { skip?: string; tokensBefore?: number; tokensAfter?: number } | undefined) {
    if (!this.compacting) return
    this.compacting = false
    const outcome = !r ? 'failed' : typeof r.skip === 'string' ? 'skipped' : 'done'
    const n = (v: unknown) => (typeof v === 'number' && Number.isFinite(v) && v >= 0 ? Math.round(v) : undefined)
    const before = outcome === 'done' ? n(r?.tokensBefore) : undefined
    const after = outcome === 'done' ? n(r?.tokensAfter) : undefined
    this.emit({
      type: 'compact.end',
      outcome,
      ...(before !== undefined ? { tokensBefore: before } : {}),
      ...(after !== undefined ? { tokensAfter: after } : {}),
    })
  }

  // -- timer

  /** Called by the outbox timer: expire held events, raise approval waits. */
  tick(now: number) {
    for (const [id, h] of this.held) if (now > h.until) this.held.delete(id)
    for (const [id, a] of this.approvals) {
      if (!a.waited && now - a.askTs >= APPROVAL_DELAY_MS) {
        a.waited = true
        this.emit({
          type: 'approval.wait',
          approvalId: id,
          ...(a.agentId ? { agentId: a.agentId } : {}),
          tool: a.tool,
          ...(a.autoMode ? { autoMode: true } : {}),
        })
      }
    }
  }
}
