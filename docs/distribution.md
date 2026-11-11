# Distribution

Users install two things: the macOS app and the Claude Code plugin. Neither should require building from source.

## The plugin: this repo is the marketplace

The repo root holds `.claude-plugin/marketplace.json`, which lists one plugin, `town-link`, with its source at `./plugin`. The plugin links Claude Code to the town app. Plugin names cannot start with `claude-`, which Claude Code reserves. The app and the repository are named agent-town. Users install it in a Claude Code session:

```
/plugin marketplace add samsonchen/agent-town
/plugin install town-link@agent-town
```

Or from the shell:

```bash
claude plugin marketplace add samsonchen/agent-town
claude plugin install town-link@agent-town
```

The marketplace name (`agent-town`, after the `@`; it avoids the reserved `claude-` prefix too) is set in `marketplace.json`. Updates arrive through Claude Code's normal plugin update flow.

Requirements to state in the README:

- Claude Code v2.1.287 or later in the terminal, or a Desktop app version that runs mods (v2.1.286 or later in the Code tab).
- Mods must not be turned off by the user's settings (`disableAllHooks`) or by an organization policy (`allowManagedModsOnly`, `allowManagedHooksOnly`).
- Role and task-type classification uses the user's own plan or API key.

Before each release, run `claude plugin validate ./plugin` and `claude plugin test ./plugin`. The validate output lists every event the mod handles and every API call it makes. Put that list in the README so users can see what the mod does before they install it.

To check: whether Anthropic offers a public plugin directory that accepts community submissions, as a second way to find the plugin.

## The app: signed DMG, Homebrew cask, in-app updates

| Channel | Command or location |
|---|---|
| GitHub Releases | `agent-town-<version>.dmg` on the repo's Releases page |
| Homebrew | `brew tap samsonchen/agent-town https://github.com/samsonchen/agent-town`, then `brew install --cask samsonchen/agent-town/agent-town` (the cask is `Casks/agent-town.rb` in this repo) |
| Updates | Sparkle, with the appcast published on GitHub Pages or in the Releases |

Code signing and notarization:

- Sign with a Developer ID certificate and notarize with Apple, so Gatekeeper opens the app without an "unidentified developer" warning. This needs an Apple Developer Program membership.
- Do the signing and notarization in GitHub Actions. Keep the certificate, its password, and the App Store Connect API key in GitHub Actions secrets, never in the repo.

## Connecting the two

| Step | How |
|---|---|
| Pairing | The app writes `endpoint.json` (port and token). The mod reads it. The user does nothing. See [protocol.md](protocol.md). |
| App missing | The mod shows one toast per session with the download link, then stays silent. |
| Plugin missing | The app's first-run screen checks for the `claude` CLI and offers an "Install Claude Code plugin" button that runs the two `claude plugin` commands above. If the CLI is not found, it shows the commands to copy. |
| Status | The app shows which sessions are connected. `/town` in Claude Code shows whether the app is reachable. |

## Licenses

- Code: Apache-2.0 (already in the repo).
- Font: 俐方體11號 (Cubic 11), SIL Open Font License. Bundle the license file. Do not sell the font on its own.
- Models and sounds: CC0 (Kenney Mini Characters and Furniture Kit are used now) or original work contributed under a license that allows redistribution. Paid asset packs whose terms forbid redistributing the raw files cannot go in this public repo.
- `assets/LICENSES.md` lists every asset, its source, and its license.
- `CONTRIBUTING.md` explains how to add a role (catalog row, labels for every locale, department color and prop) and how to add a language.
