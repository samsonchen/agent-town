# Releasing the app

How to build `AgentTown.app` and `AgentTown-<version>.dmg`, signed with a Developer ID and notarized by Apple, so it opens on any Mac with macOS 15 or later without Xcode and without the "Open Anyway" block. The app is distributed through GitHub Releases, not the App Store.

Parts A to C are one-time setup on the Mac that makes releases. Parts D to F are for each release.

No secret goes into the repo. The certificate and the notarization login stay in the macOS keychain of the Mac that releases.

## What you need

- A Mac with Xcode installed.
- An Apple ID in the developer team (Apple Developer Program), with permission to create a Developer ID certificate. The team's Account Holder has it, and can give it to an Admin.
- The GitHub CLI (`gh`), signed in, for publishing.

## Part A: Create the certificate in Xcode

No project needs to be open.

1. In Xcode, choose **Xcode → Settings…** (⌘,) → **Accounts**.
2. Click **+** at the bottom left → **Apple Account** → **Continue**, and sign in with the Apple ID in the developer team.
3. Select the Apple ID, find the team on the right, and click **Manage Certificates…**.
4. Click the **+** menu at the bottom left → **Developer ID Application**. A new row appears after a few seconds. Click **Done**.
   - If the **+** menu lists only Apple Development, Apple Distribution and Mac Installer Distribution, your role does not allow Developer ID certificates. Use "If you are not the Account Holder" below instead. Apple also blocks new certificates until the Account Holder has accepted the latest Program License Agreement on the developer website.
5. Back up the certificate. Its private key exists only on this Mac.
   - Open Keychain Access → **login** keychain → **My Certificates**.
   - Right-click "Developer ID Application: …" → **Export…** → save a `.p12` file with a strong password.
   - Keep it in a password manager or another safe place, never in the repo. A team can have only a few Developer ID certificates.
6. Check it in Terminal:
   ```
   security find-identity -v -p codesigning
   ```
   You should see one line like `"Developer ID Application: <Team name> (ABCDE12345)"`. The 10 characters in parentheses are the Team ID, used in Part C.

### If you are not the Account Holder

You make the private key on your Mac; the Account Holder only issues the certificate for it. Nothing secret is sent.

1. In Keychain Access, choose **Keychain Access → Certificate Assistant → Request a Certificate From a Certificate Authority…**. Enter your Apple ID email and a name such as `Developer ID`, leave the CA email empty, and select **Saved to disk**. This saves a `.certSigningRequest` file and creates the private key in your keychain.
2. Send the `.certSigningRequest` file to the Account Holder.
3. The Account Holder goes to developer.apple.com → **Certificates, Identifiers & Profiles** → **Certificates** → **+** → **Developer ID Application** (G2 Sub-CA if asked), uploads the file, and downloads the `.cer`.
4. Double-click the `.cer` they send back. It pairs with your private key. Then continue with step 5 above.

## Part B: Create an app-specific password

1. Sign in at account.apple.com with the same Apple ID.
2. Choose **Sign-In and Security** → **App-Specific Passwords** → **+**.
3. Name it `agent-town notary` → **Create**, and copy the password (`xxxx-xxxx-xxxx-xxxx`). It is shown only once.

## Part C: Save the notarization login in the keychain

```
xcrun notarytool store-credentials agent-town-notary --apple-id "<Apple ID email>" --team-id "<Team ID>"
```

- Paste the app-specific password when asked. Nothing shows while you paste.
- Expected: `Credentials saved to Keychain`.
- To check it: `xcrun notarytool history --keychain-profile agent-town-notary` lists past submissions, or none, without an error.

You can delete the copied password afterwards.

## Part D: Build a signed release

Commit your changes first. Then, from the repo's root folder:

```
app/macos/scripts/release.sh
```

What happens:

- It prints `Signing as: Developer ID Application: …`, then builds a universal app (Apple silicon and Intel).
- macOS may ask "codesign wants to access key … in your keychain". Enter your Mac login password and click **Always Allow**, or it asks again at each signing step.
- Apple notarizes the app, then the `.dmg`. Each usually takes a few minutes and ends with `status: Accepted`.
- Then `The staple and validate action worked!` and `accepted … source=Notarized Developer ID`.
- The app and `AgentTown-<version>.dmg` are in `app/macos/build/release/`.

The version comes from the town-link plugin (`plugin/.claude-plugin/plugin.json`), so the app and the plugin share one version number. Raise it there before a new release.

If notarization fails (`status: Invalid`), read Apple's reason with the submission ID it printed:

```
xcrun notarytool log <submission ID> --keychain-profile agent-town-notary
```

Other options of the script, and its settings (version, bundle ID, signing identity), are listed at the top of `app/macos/scripts/release.sh`. `--unsigned` makes a test build with no certificate; it opens on the Mac that built it, but is blocked on other Macs.

## Part E: Test it as a downloaded app

macOS checks only files that came from the internet. Mark the `.dmg` as downloaded, then open it:

```
cd app/macos/build/release
xattr -w com.apple.quarantine "0081;$(printf %x $(date +%s));Safari;" AgentTown-<version>.dmg
open AgentTown-<version>.dmg
```

- Quit any other copy of agent-town first; only one should run.
- Drag AgentTown into Applications and open it from there. You should see at most "downloaded from the Internet… Open?", and no "Open Anyway" block.
- The app appears in the menu bar, with no Dock icon.

## Part F: Publish

```
app/macos/scripts/release.sh --publish
```

- It builds and notarizes again, then creates a draft GitHub release `v<version>` with the `.dmg` attached, tagged on the commit you built from.
- It refuses to run with uncommitted changes.
- Check the draft on GitHub → Releases, then click **Publish**.
- While the repo is private, only people with access to it can download the release.

## Unsigned pre-releases (until the Developer ID exists)

```
app/macos/scripts/release.sh --unsigned --publish
```

- Builds the app without signing or notarization, and publishes GitHub release `v<version>` at once, marked Pre-release, with the `.dmg` attached. A signed release is made as a draft instead, for review.
- macOS blocks an unsigned app the first time it opens; users click Open Anyway in System Settings → Privacy & Security once. The README and the cask's message say so.

## Homebrew

The cask is `Casks/agent-town.rb` in this repo, so the repo is also a Homebrew tap:

```
brew tap samsonchen/agent-town https://github.com/samsonchen/agent-town
brew install --cask samsonchen/agent-town/agent-town
```

- `release.sh --publish` writes the new version and the `.dmg`'s checksum into the cask. Commit and push that change after each release; `brew upgrade` sees a new version only then.
- Homebrew downloads only from a published release (not a draft) in a public repo.
- Once the app is signed and notarized, remove the "not signed yet" message from the cask's `caveats`. A signed app could also be submitted to the official Homebrew casks, which accept only signed and notarized apps.
