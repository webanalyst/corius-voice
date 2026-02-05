# Repository Guidelines

## Project Structure & Module Organization
- `CoriusVoice/`: main SwiftUI app source.
- `CoriusVoice/Models`, `Services`, `ViewModels`, `Views`, `Utilities`: core feature layers.
- `CoriusVoice/Resources` and `CoriusVoice/Assets.xcassets`: bundled assets and app resources.
- `CoriusVoiceTests/`: XCTest targets (`CoriusVoiceTests.swift`, `IntegrationTests.swift`, `ViewModelTests.swift`).
- `CoriusVoice.xcodeproj` and `Tests.xctestplan`: Xcode project and shared test plan.

## Build, Test, and Development Commands
- `open CoriusVoice.xcodeproj`: open the app in Xcode for local development and run with ⌘R.
- `xcodebuild build -project CoriusVoice.xcodeproj -scheme CoriusVoice`: CI-style build from the command line.
- `xcodebuild test -project CoriusVoice.xcodeproj -scheme CoriusVoice`: run the full test suite.
- `xcodebuild test -project CoriusVoice.xcodeproj -scheme CoriusVoice -testClass WorkspaceViewModelTests`: run a single test class (adjust class name as needed).
- `xcodebuild test -project CoriusVoice.xcodeproj -scheme CoriusVoice -enableCodeCoverage YES`: run tests with coverage.

## Coding Style & Naming Conventions
- Swift 5.9 with 4-space indentation and LF line endings (see `.swiftformat`).
- SwiftFormat rules include wrapping parameters/arguments before the first item and trimming whitespace.
- SwiftLint is configured via `.swiftlint.yml` with `unused_import`, `implicit_return`, and multiline parameter alignment enabled.
- Follow standard Swift naming: `UpperCamelCase` for types and `lowerCamelCase` for properties/functions.

## Testing Guidelines
- Tests use XCTest and live in `CoriusVoiceTests/`.
- Prefer descriptive test names like `testSearchAndFilterWorkflow` or `testCreateEditSaveWorkflow` (see `IntegrationTests.swift`).
- Keep test data minimal and deterministic; use `MockWorkspaceStorage` where available.

## Commit & Pull Request Guidelines
- Existing commits use short, descriptive subjects; one example follows Conventional Commits (`feat: ...`).
- Keep commit messages concise and action-oriented; use prefixes like `feat:`, `fix:`, or `chore:` when it helps.
- PRs should include a summary, testing notes (commands run), and screenshots for UI changes.

## Security & Configuration Tips
- API keys (Deepgram, OpenRouter) are entered via in-app Settings; do not commit secrets.
- The app requires macOS microphone and Accessibility permissions; mention these in PR notes if they affect testing.

## Automation Notes
- Avoid reformatting generated assets (`Assets.xcassets`, `Resources`) unless the change is intentional.
- If you touch Swift files, run SwiftFormat/SwiftLint locally before opening a PR.
