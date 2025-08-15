# Phase 2: Tauri Desktop Application

## Overview
This is Phase 2 of the CodeWalk project - transforming the terminal STT application into a full-featured desktop application using Tauri. This phase brings a native GUI experience while maintaining the core STT functionality from Phase 1.

## Purpose
Phase 2 evolves the terminal application into a modern desktop app that:
- Provides an intuitive graphical user interface
- Offers better user experience with visual feedback
- Enables richer features through native OS integration
- Maintains cross-platform compatibility (macOS, Windows, Linux)

## Current Development Focus
This is the active development branch where we're building:
- Tauri-based desktop application framework
- React/TypeScript frontend for the UI
- Enhanced audio visualization
- Settings management through GUI
- System tray integration
- Native notifications

## Features (In Development)
- ✅ Core STT functionality from Phase 1
- 🚧 Native desktop application with Tauri
- 🚧 Modern React-based user interface
- 🚧 System tray integration for background operation
- 🚧 Visual audio waveform during recording
- 🚧 Settings panel for configuration
- 🚧 History of transcriptions
- 🚧 Multiple output formats (clipboard, file, direct insertion)
- 🚧 Customizable hotkeys through GUI

## How to Run

### Prerequisites
- Rust 1.70+ installed
- Node.js 16+ and npm/yarn
- Groq API key (set as `GROQ_API_KEY` environment variable)
- Tauri prerequisites for your OS:
  - macOS: Xcode Command Line Tools
  - Linux: See [Tauri Linux Prerequisites](https://tauri.app/v1/guides/getting-started/prerequisites/#linux)
  - Windows: See [Tauri Windows Prerequisites](https://tauri.app/v1/guides/getting-started/prerequisites/#windows)

### Installation
```bash
# Clone this branch
git clone -b phase-2-tauri-app https://github.com/jaxs-ribs/codewalk.git
cd codewalk

# Install dependencies
npm install

# Run in development mode
npm run tauri dev

# Build for production
npm run tauri build
```

### Development Setup
```bash
# Install Tauri CLI
cargo install tauri-cli

# Install frontend dependencies
npm install

# Run development server with hot reload
npm run tauri dev
```

## Technical Stack
- **Framework**: Tauri (Rust backend + Web frontend)
- **Backend**: Rust (inherited from Phase 1)
  - Audio: cpal
  - STT: Groq Whisper API
  - Clipboard: arboard
- **Frontend**: 
  - React with TypeScript
  - Vite for build tooling
  - Tailwind CSS for styling
- **IPC**: Tauri's secure IPC for frontend-backend communication

## Migration from Phase 1
This phase builds directly on the Phase 1 codebase:
1. Core Rust STT logic remains unchanged
2. Terminal UI replaced with Tauri webview
3. Added IPC commands for frontend communication
4. Enhanced with native desktop features

## Development Status
🚧 **Active Development** - This is the current working branch where new features are being implemented.

### Completed
- [x] Project structure setup
- [x] Core STT functionality integration

### In Progress
- [ ] Tauri application scaffold
- [ ] React frontend implementation
- [ ] IPC command bindings
- [ ] System tray integration

### Planned
- [ ] Settings persistence
- [ ] Auto-updater
- [ ] Cross-platform testing
- [ ] Performance optimizations

## Contributing
This is the active development branch. When working on new features:
1. Create feature branches from `phase-2-tauri-app`
2. Test thoroughly on your target platform
3. Ensure backward compatibility with Phase 1 core features
4. Update this README with any new setup requirements

## Next Steps
Once Phase 2 is complete, it will be merged to `main` for release. Future phases may include:
- Phase 3: Cloud sync and collaboration features
- Phase 4: AI-enhanced code generation
- Phase 5: IDE integrations

## License
MIT