# CodeWalk - Voice-Driven Development Assistant

## Overview
CodeWalk is a voice-driven development assistant that transforms speech into code documentation, comments, and development workflows. This is the main production branch containing the latest stable release.

## Project Structure
CodeWalk follows a phased development approach with separate branches for each major milestone:
- **main** (this branch) - Current production release
- **phase-1-terminal-stt** - Terminal-based STT foundation (completed)
- **phase-2-tauri-app** - Desktop GUI application (active development)

## Current Release
The current release provides a fully functional speech-to-text tool that integrates with your clipboard for seamless voice-to-text workflows.

### Features
- Global hotkey activation from any application
- High-quality speech recognition via Groq Whisper API
- Instant clipboard integration
- Terminal and global operation modes
- Cross-platform audio capture
- Minimal resource footprint

## Quick Start

### Prerequisites
- Rust 1.70+
- Groq API key from [console.groq.com/keys](https://console.groq.com/keys)
- macOS (Windows/Linux support coming in Phase 2)

### Installation
```bash
# Clone the repository
git clone https://github.com/jaxs-ribs/codewalk.git
cd codewalk

# Set up your API key
echo "GROQ_API_KEY=your_key_here" > .env

# Build and run
cargo build --release
cargo run
```

### Usage
#### Terminal Mode
```bash
cargo run
```
- Press **SPACE** to toggle recording (when terminal is focused)
- Press **Q** to quit

#### Global Mode
```bash
cargo run -- --global
```
- Press **Cmd+Shift+Option+Space** from anywhere to toggle recording
- Press **Ctrl+C** in terminal to quit

## macOS Setup
For global hotkey support:
1. Open **System Preferences → Security & Privacy → Privacy → Accessibility**
2. Click the lock to make changes
3. Add your terminal application (Terminal.app, iTerm2, etc.)
4. Restart your terminal if needed

## Development Philosophy
CodeWalk uses a phased branch strategy where:
- Each phase lives in its own branch as a complete, runnable application
- Phases build upon each other while maintaining independence
- The main branch always contains the latest stable, production-ready release

This approach ensures:
- Clean separation of concerns between development stages
- Easy rollback and comparison between phases
- Clear progression path for features
- Stable production releases

## Roadmap
### ✅ Phase 1: Terminal STT (Complete)
Core speech-to-text functionality with terminal interface

### 🚧 Phase 2: Tauri Desktop App (In Progress)
Native desktop application with GUI

### 📋 Phase 3: Cloud Sync (Planned)
Multi-device synchronization and collaboration

### 📋 Phase 4: AI Enhancement (Planned)
Context-aware code generation and suggestions

### 📋 Phase 5: IDE Integration (Planned)
Direct integration with popular development environments

## Contributing
We welcome contributions! Please:
1. Check the appropriate phase branch for your feature
2. Create feature branches from the relevant phase branch
3. Test thoroughly on your target platform
4. Submit PRs to the appropriate phase branch

## Support
- **Issues**: [GitHub Issues](https://github.com/jaxs-ribs/codewalk/issues)
- **Documentation**: See phase-specific READMEs in each branch
- **API Keys**: Get your Groq API key at [console.groq.com](https://console.groq.com/keys)

## License
MIT - See LICENSE file for details

## Acknowledgments
Built with:
- 🦀 Rust for performance and reliability
- 🎤 Groq Whisper for speech recognition
- 🖥️ Tauri for desktop applications (Phase 2+)
- ❤️ Open source community contributions