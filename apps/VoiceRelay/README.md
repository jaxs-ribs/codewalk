VoiceRelay Mobile (React Native)

Minimal React Native app that displays “Hello World.” This lives under `apps/VoiceRelay` and will later capture microphone audio, transcribe via Groq, and forward transcripts to the relay server and workstation. See the repo root `agents.md` for the larger plan.

Quick Launch (everything already installed)

- Terminal 1 (Metro):

  cd apps/VoiceRelay
  npm start

- Terminal 2 (iOS Simulator):

  cd apps/VoiceRelay
  npm run ios -- --simulator="iPhone 16 Pro"

- Android Emulator (optional):

  cd apps/VoiceRelay
  npm run android

What You Should See

- A centered “Hello World” on screen.
  Now also shows a relay connectivity status pill (Connected/Disconnected) and last-checked time.

What Worked For Us (macOS setup notes)

1) Node via nvm

   cd apps/VoiceRelay
   nvm install && nvm use   # uses .nvmrc (20.19.4)
   npm install

2) Xcode and Simulator

   sudo xcode-select -s /Applications/Xcode.app/Contents/Developer
   sudo xcodebuild -runFirstLaunch
   sudo xcodebuild -license accept
   open -a Xcode  # allow it to install additional components
   # Ensure a simulator exists (e.g., iPhone 16 Pro) in Xcode > Window > Devices & Simulators
   xcrun simctl list devices | head -n 20

3) CocoaPods (Homebrew path)

   brew install cocoapods
   cd ios && pod install && cd ..

4) Run

   npm start
   # in another terminal
   npm run ios -- --simulator="iPhone 16 Pro"

Tips

- List simulators: `xcrun simctl list devices | head -n 20`
- If Pods errors occur, re-run `pod install` inside `ios/`
- Android: start an AVD in Android Studio first; if Gradle issues, try `cd android && ./gradlew clean && cd ..`

Config: Relay Connectivity Indicator

- Default health endpoint:
  - iOS Simulator: `http://localhost:3001/health`
  - Android Emulator: `http://10.0.2.2:3001/health`
- To change the port/host, edit constants at the top of `apps/VoiceRelay/App.tsx:1` (see `RELAY_PORT`, `RELAY_HOST`, and `RELAY_HEALTH_URL`).
- The indicator checks immediately at launch and every 10 seconds.

Troubleshooting

- Clear Metro/Watchman cache: `watchman watch-del-all || true && rm -rf node_modules && npm install && npm start -- --reset-cache`
- If CoreSimulator errors: reboot macOS once after running `xcodebuild -runFirstLaunch`, then retry.

Next Bite-Sized Task

- Add a simple WebSocket echo to the relay once available:
  - Connect to the relay’s `ws://<host>:<port>/ws` after the health check is “Connected”.
  - Send a JSON hello (session placeholders for now) and echo a test message.
  - Render connection state and last message received.
  - This builds directly on the health check and proves bi-directional connectivity.
