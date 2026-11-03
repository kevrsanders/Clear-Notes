# Getting Clear Notes onto TestFlight

GitHub Actions builds the app on a Mac in the cloud, signs it with your Apple Developer account and uploads it to TestFlight. You don't need a Mac. The workflow is [.github/workflows/ios.yml](../.github/workflows/ios.yml).

Every push that changes the app also runs **Build and test**, so build errors show up in the **Actions** tab even before TestFlight is set up.

> Keep keys out of chats, emails and the repository. They only go into GitHub's encrypted **Secrets** (step 5).

## What you need

- A membership of the [Apple Developer Program](https://developer.apple.com/programs/) (the paid one). If you want to use an NHS organisation's account, check with your IT team first.
- Admin access to the GitHub repository.

## One-time setup (about 20 minutes)

### 1. Choose a bundle ID
This is the app's permanent, unique ID, in reverse-domain style, e.g. `com.yourname.clearnotes`. Use a domain you control and write it down.

### 2. Register the bundle ID
[developer.apple.com](https://developer.apple.com/account) → **Certificates, Identifiers & Profiles** → **Identifiers** → **+** → **App IDs** → **App**:
- Description: `Clear Notes`
- Bundle ID: **Explicit**, the ID from step 1
- Capabilities: none needed
- **Continue → Register**

The app also contains a Lock Screen extension (the recording timer and buttons) with the ID `<your bundle ID>.LiveActivity`. The upload registers it for you with the Admin API key from step 4. You only need to register it by hand, like this step, if an upload fails with a signing error that names it.

### 3. Create the app in App Store Connect
[appstoreconnect.apple.com](https://appstoreconnect.apple.com) → **Apps** → **+** → **New App**:
- Platform: **iOS**
- Name: `Clear Notes`. App names must be unique across the App Store, so if it's taken, try e.g. `Clear Notes – Meetings`. You can rename it later.
- Primary language: English (UK)
- Bundle ID: pick the one from step 2
- SKU: anything, e.g. `clearnotes`
- User access: Full access

Don't press **Add for Review** afterwards. That submits the app to the public App Store; TestFlight doesn't need it.

### 4. Create an App Store Connect API key
App Store Connect → **Users and Access** → **Integrations** → **App Store Connect API** → **Team Keys** → **+**:
- Name: `GitHub TestFlight`
- Access: **Admin**. GitHub needs this to create the signing certificate and profile for you.
- **Generate**, then **Download API Key**. You can only download it once, so keep the `.p8` file safe.
- Note the **Key ID** (shown in the list) and the **Issuer ID** (shown above the list).

Also find your **Team ID**: [developer.apple.com/account](https://developer.apple.com/account) → **Membership details** → Team ID (10 characters).

### 5. Add the secrets to GitHub
On GitHub: the repository → **Settings** → **Secrets and variables** → **Actions**.

> Use the **Actions** page. The **Agents**, **Codespaces** and **Dependabot** pages under the same menu look identical, but workflows can't read what's stored there.

On the **Secrets** tab → **New repository secret**, add four:

| Name | Value |
|---|---|
| `ASC_KEY_ID` | The Key ID from step 4 |
| `ASC_ISSUER_ID` | The Issuer ID from step 4 |
| `ASC_PRIVATE_KEY` | Open the `.p8` file in a text editor and paste **all** of it, including the `-----BEGIN PRIVATE KEY-----` and `-----END PRIVATE KEY-----` lines |
| `APPLE_TEAM_ID` | Your Team ID |

On the **Variables** tab → **New repository variable**, add one (adding it as a secret named the same also works):

| Name | Value |
|---|---|
| `CLEAR_NOTES_BUNDLE_ID` | The bundle ID from step 1 |

## Upload a build

Either:
- **From GitHub:** **Actions** → **iOS** → **Run workflow** → choose the branch → **Run workflow**. This button appears once the workflow is on the repository's default branch (`main`).
- **From Claude:** ask Claude to send a build to TestFlight. It pushes a commit whose message contains `[testflight]`, which triggers the upload on that branch.

The run takes roughly 15–25 minutes. Each upload uses the run number as its build number, so builds never clash. Apple then processes the build for 5–30 minutes.

## Install it on your iPhone

1. App Store Connect → your app → **TestFlight** → **Internal Testing** → **+** to create a group, then add yourself (and up to 100 people on your team).
2. Install **TestFlight** from the App Store on your iPhone, signed in with the same Apple ID.
3. Accept the invitation email, or open TestFlight. Clear Notes appears there, ready to install.

The app declares that it uses no non-exempt encryption (`ITSAppUsesNonExemptEncryption = NO`), so TestFlight won't ask the export compliance question for each build.

## If something goes wrong

| Problem | What to do |
|---|---|
| "Missing: …" in the **Check TestFlight settings** step | A secret or the variable from step 5 is missing, misspelled, or saved under **Agents** (or Codespaces/Dependabot) instead of **Actions** |
| "The job was not acquired by Runner…" or long queues | GitHub is short of Apple-silicon Macs. Re-run the failed job later, or add a repository variable `MACOS_RUNNER` set to `macos-26-intel` to use Intel Macs (slower, same Xcode) |
| "No profiles for '…' were found" / signing errors | Check the API key has **Admin** access, and that the bundle ID variable exactly matches step 2 |
| "No suitable application records were found" or "Error Downloading App Information" | The app wasn't created in App Store Connect (step 3), it uses a different bundle ID, or an agreement is waiting to be accepted in App Store Connect. Registering the identifier (step 2) doesn't create the app |
| "Your account already has an Apple Development signing certificate for this machine…" | Fixed in the workflow (archives are now unsigned and signed at upload). Optionally revoke stray **Apple Development** certificates created by GitHub runners under Certificates at developer.apple.com |
| Build or test failures | Open the failed run in **Actions** and share the error with Claude |
| Every job fails within seconds, with no log | The account's Actions minutes or spending limit is used up. The run page says so at the top. Add a budget for Actions under your GitHub **Settings → Billing and licensing**, or wait for the monthly allowance to reset, then press **Re-run all jobs** on the latest run |

## Cost

GitHub Actions bills Mac minutes at 10× the Linux rate on private repositories (the free plan includes 2,000 minutes a month, so about 200 Mac minutes). A test run takes about 10 minutes, a TestFlight run about 20. That's roughly seven TestFlight builds a month on the free allowance. Public repositories are free. To save minutes, the workflow cancels older runs on the same branch, doesn't run a second copy for the pull request, and skips Markdown-only changes.
