# Flux

**Flux** is a premium, glassmorphic productivity dashboard for macOS that lives quietly in your menu bar. It consolidates fragmented workflows — file creation, clipboard management, snippets, color picking, and note-taking — into a single, high-performance interface.

---
Don't want to build from source? **[Download the latest compiled `.dmg` from the Releases section](https://github.com/user/repo/releases)**.

---

## Key Features

### Instant File Creation
*   **One-Tap Creation**: Create `.html`, `.swift`, `.json`, and more in your active Finder window with a single click.
*   **Drag & Drop**: Drag file type icons directly from Flux into any folder to create a new file instantly.
*   **Custom Extensions**: Type any extension (`.go`, `.rs`, `.tsx`) via the "Other" tile.

### Intelligent Clipboard
*   **Deep History**: Automatically tracks everything you copy — configurable up to 5,000 items.
*   **Searchable**: Instantly find anything from your history with the built-in search bar.
*   **One-Click Restore**: Click any item to put it back on your active pasteboard.
*   **Delete Items**: Remove individual entries with a single tap, or clear the entire history at once.
*   **Privacy Protection**: Flux automatically ignores content copied from password managers and macOS Keychain (respects the `org.nspasteboard.ConcealedType` standard).
*   **App Blacklist**: Choose specific applications whose clipboard content should never be saved — configurable from a searchable list of every app installed on your device.

### Snippet Library
*   **Reusable Templates**: Save emails, boilerplate code, or frequently used text as named snippets.
*   **One-Click Copy**: Tap any snippet to instantly load it onto your clipboard.
*   **Edit & Delete**: Full inline editing and deletion with confirmation dialogs.

### Scratchpad
*   **Multi-Note**: Manage multiple named notes with a collapsible sidebar.
*   **Auto-Hiding Sidebar**: Hover the left edge to reveal the notes list; it stays out of your way when you're writing.
*   **Instant Persistence**: All notes are saved to disk immediately.

### Design Toolkit
*   **System-Wide Eyedropper**: Pick any pixel color on your screen.
*   **Format Converter**: Instantly get HEX, RGB, and HSL values — click each to copy.
*   **Color History**: Remembers your recently picked colors.

### Finder Integration
*   **Copy Exact Path**: Installs a native macOS Quick Action that lets you right-click any file in Finder and copy its full POSIX path to the clipboard instantly — no Terminal needed.

### Localization
*   **Context-Aware Translation Engine**: Localizes the entire UI into dozens of languages on the fly using the Google Translate API, with smart caching for offline use.
*   **Protected Terms**: `Flux`, `Copy Exact Path`, and `Services` are always preserved in their original form, regardless of language.
*   **Set in Onboarding**: Choose your language on first launch.

---

## ⌨️ Shortcuts & Interaction

| Action | Default Shortcut |
| :--- | :--- |
| **Show / Hide Flux** | Tap `Control` |
| **Switch to Tab 1–5** | `⌘ + 1` – `⌘ + 5` |

> All shortcuts are fully configurable in **Settings**.

---

## Building From Source

Flux is written in **SwiftUI** and uses a custom Python build pipeline that produces a universal binary and a distributable `.dmg` in a single command.

### Prerequisites
1.  **macOS 13.0 (Ventura) or later** — supports Apple Silicon & Intel
2.  **Xcode Command Line Tools**: `xcode-select --install`
3.  **Python 3**

### Build & Install

```bash
python3 build_standalone.py
```

This single command will:
- Compile a **Universal Binary** for both Apple Silicon and Intel.
- Generate high-resolution `.icns` icons at all required sizes.
- Bundle the Finder extension (`FluxFinder.appex`).
- Ad-hoc sign and package everything into `/Applications/Flux.app`.
- Create `Flux_Universal.dmg` for distribution.
- Launch the app automatically.

---

## Configuration

All data is stored locally in `~/.flux/`:

| File | Contents |
| :--- | :--- |
| `settings.json` | Preferences, hotkeys, blacklist, language |
| `clipboard.json` | Clipboard history |
| `scratchpads.json` | Notes |
| `translations.json` | Cached UI translations (offline-safe) |

---

## Security & Privacy

*   **Local First**: No data ever leaves your machine, except for optional UI translation requests to the Google Translate API.
*   **Keychain-Safe**: Clipboard content flagged as sensitive by password managers is automatically ignored and never stored.
*   **App Blacklist**: Fine-grained control over which applications Flux monitors.
*   **No Account Required**: Zero sign-up, zero telemetry, zero cloud dependency.

---

*Flux — Flow through your work.*
