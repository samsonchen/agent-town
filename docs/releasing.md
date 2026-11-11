# Releasing the app

How to build `AgentTown.app` and `AgentTown-<version>.dmg`, signed with a Developer ID and notarized by Apple, so it opens on any Mac with macOS 15 or later without Xcode and without the "Open Anyway" block. The app is distributed through GitHub Releases, not the App Store.

Parts A to C are one-time setup on the Mac that makes releases. Parts D to F are for each release.

No secret goes into the repo. The certificate and the notarization login stay in the macOS keychain of the Mac that releases.

## What you need

- A Mac with Xcode installed, to build the app (Part D). It is not needed to create the certificate.
- An Apple ID in the developer team (Apple Developer Program), with access to the developer website. Creating a Developer ID certificate needs the Account Holder, or an Admin the Account Holder has given the permission; otherwise the Account Holder issues it from your request (Part A).
- The GitHub CLI (`gh`), signed in, for publishing.

## Part A: Create the certificate on the developer website

Xcode is not needed for this step. You make a certificate request on the Mac that will release, the developer website issues the certificate, and you install it on the same Mac.

1. Create a certificate signing request. In Keychain Access, choose **Keychain Access → Certificate Assistant → Request a Certificate From a Certificate Authority…**. Enter your Apple ID email and a name such as `Developer ID`, leave the CA email empty, and select **Saved to disk**. This saves a `.certSigningRequest` file and creates the private key in your **login** keychain. The private key exists only on this Mac.
2. Issue the certificate:
   - If you are the Account Holder: go to developer.apple.com/account → **Certificates, Identifiers & Profiles** → **Certificates** → **+**. Under Software, choose **Developer ID Application** and click Continue. If asked for a profile type, choose **G2 Sub-CA**. Upload the `.certSigningRequest` file and download the `.cer`.
   - If you are not the Account Holder: send the `.certSigningRequest` file to the Account Holder, who does the same and sends you the `.cer`. Nothing secret is sent. Only the Account Holder, or an Admin the Account Holder has given the permission, can create Developer ID certificates.
   - Apple blocks new certificates until the Account Holder has accepted the latest Program License Agreement on the developer website.
3. Import the `.cer` into the **login** keychain on the same Mac that made the request, so it pairs with the private key from step 1. Do it on another Mac and signing will not work.
   - Drag the `.cer` onto **login** in the Keychain Access sidebar, or run `security import <file>.cer -k ~/Library/Keychains/login.keychain-db`.
   - Double-clicking the `.cer` may put it in the **System** keychain instead. There it has no private key: it is missing from **My Certificates** and cannot be exported as `.p12`. If that happened, delete it from System and import it into login.
4. Back up the certificate. Its private key exists only on this Mac.
   - Open Keychain Access → **login** keychain → **My Certificates**.
   - Right-click "Developer ID Application: …" → **Export…** → save a `.p12` file with a strong password.
   - Keep it in a password manager or another safe place, never in the repo. A team can have only a few Developer ID certificates.
5. Check it in Terminal:
   ```
   security find-identity -v -p codesigning
   ```
   You should see one line like `"Developer ID Application: <Team name> (ABCDE12345)"`. The 10 characters in parentheses are the Team ID, used in Part C.

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

- It builds and notarizes again, then publishes GitHub release `v<version>` with the `.dmg` attached, tagged on the commit you built from.
- It then downloads the uploaded `.dmg`, checks that its checksum matches, and commits and pushes the Homebrew cask with the new version (see [Homebrew](#homebrew)). After that, `brew update && brew upgrade --cask agent-town` installs the new version.
- It refuses to run with uncommitted changes, from a branch other than `main`, or when `main` differs from `origin/main`.
- To review the release on GitHub first, add `--draft`: the release is made as a draft, and the cask is updated but not committed. Publish the draft on GitHub → Releases, then commit and push `Casks/agent-town.rb` yourself.

## Unsigned pre-releases (until the Developer ID exists)

```
app/macos/scripts/release.sh --unsigned --publish
```

- Builds the app without signing or notarization, and publishes GitHub release `v<version>` marked Pre-release, with the `.dmg` attached, then pushes the cask as for a signed release.
- macOS blocks an unsigned app the first time it opens; users click Open Anyway in System Settings → Privacy & Security once. The README and the cask's message say so.

## Homebrew

The cask is `Casks/agent-town.rb` in this repo, so the repo is also a Homebrew tap:

```
brew tap samsonchen/agent-town https://github.com/samsonchen/agent-town
brew install --cask samsonchen/agent-town/agent-town
```

- Homebrew reads the cask from this repo's `main` branch, not from the Releases page. A published release alone changes nothing for `brew upgrade`; the cask with the new version and checksum has to be pushed too. `release.sh --publish` does both (with `--draft`, push the cask yourself after publishing).
- Homebrew downloads only from a published release (not a draft) in a public repo.
- Once the app is signed and notarized, remove the "not signed yet" message from the cask's `caveats`. A signed app could also be submitted to the official Homebrew casks, which accept only signed and notarized apps.
