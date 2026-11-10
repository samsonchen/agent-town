/** What town-link keeps in the session's state, so a hot reload of its code loses nothing. */
export type TownSaved = {
  sessionId: string
  /** The last envelope sequence number sent. */
  seq: number
  /** Events not yet sent to the app. */
  queue: Record<string, unknown>[]
  /** The tracker's open tickets, staff, tasks and waits (Town.save). */
  town: Record<string, unknown>
}

declare module 'claude-code' {
  interface PluginState {
    'town-link': { saved: TownSaved }
  }
}
