VoiceRelay Mobile (React Native)

Minimal React Native app that displays “Hello World.” This lives under `apps/VoiceRelay` in this repo and will later capture microphone audio, transcribe via Groq, and forward transcripts to the relay server and workstation. See the repo root `agents.md` for the larger plan.

Getting Started

- Prereqs: complete the official “Set Up Your Environment” guide for React Native. Summary for macOS:
  - Node.js v20.19.4+ (or Node 22 LTS): `node -v` should print ≥ 20.19.4
  - Watchman: `brew install watchman`
  - Xcode (iOS Simulator) + Command Line Tools (open Xcode once to finish setup)
  - CocoaPods: EITHER `brew install cocoapods` (simplest), OR use Bundler with a modern Ruby (≥3.1) as shown below
  - Android Studio (SDK, Platform Tools, Emulator). Install one API level (e.g., Android 14), and create a virtual device (AVD).
  - Java 17 (Temurin recommended): `brew install --cask temurin@17`
  - ANDROID_HOME: usually `export ANDROID_HOME=$HOME/Library/Android/sdk` and add `$ANDROID_HOME/platform-tools` to PATH

Project Setup

1) Install JS deps

   cd apps/VoiceRelay
   npm install

2) iOS pods (first run on each machine, or after native deps change)

   cd ios
   # Option A (fastest): Homebrew CocoaPods
   # Avoids macOS system Ruby issues
   brew install cocoapods
   pod install

   # Option B: Bundler (Ruby-managed, requires Ruby ≥3.1)
   # Use rbenv or asdf to install a modern Ruby (system Ruby 2.6 will fail)
   # Example with rbenv:
   #   brew install rbenv ruby-build
   #   rbenv install 3.3.4 && rbenv local 3.3.4
   #   gem install bundler
   bundle install
   bundle exec pod install
   cd ..

3) Start Metro (JS bundler)

   npm start

Run on iOS Simulator (no cable needed)

- With Metro running in one terminal, in another terminal from `apps/VoiceRelay`:

  npm run ios

- Tips:
  - List available simulators: `xcrun simctl list devices | head -n 20`
  - If a specific simulator is needed: `npm run ios -- --simulator="iPhone 16 Pro"`
  - If you see a Pods error, ensure `pod install` in the `ios/` folder completed successfully.
  - Open `ios/VoiceRelay.xcworkspace` in Xcode to select simulators or manage signing if needed.

Run on Android Emulator

1) Open Android Studio → Device Manager → start an AVD (e.g., Pixel 7)
2) From `apps/VoiceRelay` in a new terminal:

   npm run android

- Tips:
  - If the emulator isn’t running, the build may fail; start it first.
  - If Gradle issues occur, try: `cd android && ./gradlew clean && cd ..`

What You Should See

- The app renders a centered “Hello World” text.

Repo Context and Next Steps

- Future features: microphone capture, Groq transcription, forwarding transcripts to the relay server, and HTTP/WebSocket comms with the workstation. See `agents.md` at the repo root for a concise plan.

Troubleshooting

- Clear Metro/Watchman cache: `watchman watch-del-all || true && rm -rf node_modules && npm install && npm start -- --reset-cache`
- iOS Pods: run `pod repo update` then `pod install` inside `ios/`
- Android SDK: ensure `$ANDROID_HOME` and `platform-tools` are on PATH; start the emulator first.
