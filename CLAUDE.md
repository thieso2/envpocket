# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

envpocket is a macOS command-line utility that securely stores environment files in the system keychain. It provides versioning support, complete history management, and encrypted team sharing capabilities.

## Build and Development Commands

### Using mise (Recommended)
The project includes mise task runner configuration for common workflows:

```bash
# Build debug version
mise run build

# Build release version
mise run build:release

# Run tests
mise run test

# Run tests with verbose output
mise run test:verbose

# Clean build artifacts
mise run clean

# Development workflow (build + test)
mise run dev

# CI workflow (lint + test + release build)
mise run ci

# Install locally to ~/.local/bin
mise run install:local

# Install to /usr/local/bin (requires sudo)
mise run install

# Check for compilation warnings
mise run lint

# List all available tasks
mise tasks
```

### Using Swift directly
```bash
# Debug build
swift build

# Release build (optimized)
swift build -c release

# Build and copy to current directory
swift build -c release && cp .build/release/envpocket ./

# Clean build artifacts
swift package clean
```

### Running
```bash
# Via Swift Package Manager (includes rebuilding)
swift run envpocket <command> [args]

# Via mise
mise run run -- <command> [args]

# Via debug build
.build/debug/envpocket <command> [args]

# Via release build
.build/release/envpocket <command> [args]
```

### Testing
```bash
# Run all tests
swift test

# Run with verbose output
swift test --verbose

# Run specific test
swift test --filter EnvPocketTests
```

## Architecture

Three-file modular architecture for separation of concerns:

### Source Files
1. **`EnvPocket.swift`**: Core business logic class
   - All keychain operations (save, get, delete, list, history)
   - Encryption/decryption for team sharing (AES-256-GCM with PBKDF2)
   - Wildcard pattern matching for bulk deletions
   - Version history management

2. **`KeychainProtocol.swift`**: Protocol-based keychain abstraction
   - `KeychainProtocol`: Interface for keychain operations
   - `RealKeychain`: Production implementation using Security framework
   - `MockKeychain`: In-memory implementation for testing
   - Enables dependency injection and testing without actual keychain access

3. **`main.swift`**: CLI argument parsing and command dispatch
   - Command enumeration and routing
   - Interactive password prompting with hidden echo
   - Usage help text
   - Exit codes (0 for success, 1 for failure)

### Key Design Patterns
- **Protocol-Oriented Design**: `KeychainProtocol` enables testability through dependency injection
- **Namespace Isolation**: All keychain entries use prefixes to prevent conflicts
- **Atomic Operations**: Delete-then-add pattern ensures data consistency
- **Version Preservation**: Current version automatically backed up before updates

## Storage Architecture

### Keychain Structure
- **Current Version**: `envpocket:<key>`
- **History Versions**: `envpocket-history:<key>:<ISO8601-timestamp>`
- **Item Class**: `kSecClassGenericPassword`
- **Attributes**:
  - `kSecAttrAccount`: Prefixed key name (account identifier)
  - `kSecValueData`: File contents as binary data
  - `kSecAttrLabel`: Original file path
  - `kSecAttrComment`: Last modification timestamp (ISO8601 format)

### History Management
- On update: Current version moved to history with current timestamp
- On delete: Current version AND all history entries removed (cascade)
- Sorting: History sorted by timestamp (newest first, index 0)

### Team Sharing Encryption
- **Algorithm**: AES-256-GCM for authenticated encryption
- **Key Derivation**: PBKDF2 with 100,000 iterations using SHA-256
- **Salt**: 32 random bytes per export
- **Format**: Custom binary format with magic header "ENVPOCKET_V1"
- **Structure**: header + salt (32B) + nonce (12B) + ciphertext + tag (16B)
- **Data Format**: JSON containing base64-encoded file data, metadata, and history

## Common Development Patterns

### Running Local Builds
When testing changes:
```bash
swift build && .build/debug/envpocket list
```

### Testing with Mock Keychain
Tests use `MockKeychain` for isolated testing without touching the system keychain. When adding new functionality, inject the keychain dependency:
```swift
let envPocket = EnvPocket(keychain: MockKeychain())
```

### Adding New Commands
1. Add command to `Command` enum in `main.swift`
2. Add implementation method in `EnvPocket.swift`
3. Add command handling in `main()` switch statement
4. Update `usage()` help text
5. Add tests in `EnvPocketTests.swift`

### Working with Keychain Queries
All keychain operations use exact account matching with prefixed keys. Never use wildcard queries at the keychain API level - filtering is done in-memory after retrieving all items.

## Publishing and Releases

### Publishing a New Release (with mise)
```bash
# Interactive release workflow (recommended)
mise run release:publish

# Manual steps:
# 1. Create release archive
mise run release:archive

# 2. Create GitHub release manually
gh release create v0.4.2 envpocket-macos.tar.gz --title "v0.4.2" --generate-notes

# 3. Update formula with new version and SHA256
mise run release:formula 0.4.2 <sha256-from-archive>

# 4. Commit and push
git add Formula/envpocket.rb
git commit -m "Update Homebrew formula to v0.4.2"
git push
```

### Release Checklist
1. Ensure all tests pass: `mise run test`
2. Ensure no warnings: `mise run lint`
3. Update version if needed in `Formula/envpocket.rb`
4. Run release workflow: `mise run release:publish`
5. Verify Homebrew installation: `brew upgrade envpocket`

## Code Quality Requirements

- Compile without warnings
- Maintain protocol-based abstraction for keychain
- Preserve namespace isolation (all keys must have proper prefixes)
- Exit with status 1 on all failures
- Include descriptive error messages for users
