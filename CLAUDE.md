# Clear Notes: instructions for Claude

## Privacy: no third-party requests (UK GDPR)

Apps and sites built here must not send users' data, or their IP address, to third parties.
An IP address is personal data under UK GDPR, so even a font request counts.

- **Fonts, icons, images, scripts and styles** are bundled with the app or self-hosted. Never load them from Google Fonts, a CDN (jsDelivr, unpkg, cdnjs and others), Font Awesome's kit or any other host.
- **No analytics, tracking, ads, crash reporting or session replay** from third-party SDKs or scripts. No embeds that call home, such as YouTube, maps, social buttons or chat widgets.
- **Models and other large assets** (ML models, speech or language packs, datasets) are bundled at build time. Never download them on users' devices from Hugging Face, GitHub, S3 or anyone else. Fetching them on the build machine is fine.
- **Only the user can start a third-party contact**, by tapping a clearly labelled button. The setting or button says who is contacted and what they see. Example: More accurate transcripts downloads from Hugging Face. Record every exception in the README's "What Clear Notes connects to" table, for the DPIA.
- **Platform services** (iOS speech and Apple Intelligence assets, TestFlight, App Store) are fine, but the README must list them.
- **Before adding any dependency**, check whether it contacts the network at run time (telemetry, model downloads, update checks). Turn that off or block it, as `ModelDownloads.blockByDefault()` does for FluidAudio.
- **Tests guard the rule** (`ClearNotesTests/PrivacyTests.swift`): models are built in and downloads are blocked from launch.

## Working on this repo

- Speech, speaker voices and meeting notes stay on the iPhone. Voiceprints are biometric data. The app is general-purpose and not for clinical use.
- Test data uses fictional names only (Priya Sharma, Tom Ellis, Sam Lee). Never copy real names, meeting titles or device logs from screenshots into the repo.
- Show options or mockups before changing the design.
- CI runs cost money. Add `[skip ci]` to commits that don't need a build, and `[testflight]` to upload to TestFlight.
- Never ask for secrets. They go only in GitHub Actions secrets and variables.
