# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

envpocket is a macOS command-line utility that securely stores environment files and values in the system keychain. It provides versioning support, complete history management, and encrypted team sharing capabilities.

**Key Features:**
- File-based storage (`save` command) for `.env` files and configuration files
- Direct value storage (`set` command) for API keys, tokens, and secrets
- Automatic version history on updates
- Encrypted team sharing with export/import
- Wildcard pattern matching for bulk operations
- **Vault support** for organizing keys into namespaces (e.g., `prod/sql/onprem`)

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

# Generate version information (runs automatically before builds)
mise run gen:version

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
# Run all tests (uses swift-testing framework)
swift test

# Run with verbose output
swift test --verbose

# Run specific test by name
swift test --filter "Save file to keychain"

# Run all tests in a specific file
swift test --filter EnvPocketMockTests
```

**Note:** This project uses Swift Testing (not XCTest). Tests use `@Test` attributes and `#expect` assertions.

## Version Management

The project uses **dynamic version generation** to display different version strings for development and release builds:

- **Release builds**: Show clean version number (e.g., `0.5.0`)
- **Debug builds**: Show version with git hash (e.g., `0.5.0-dev+afd6729`)

### How It Works

1. **Version Source**: Version number is read from `Formula/envpocket.rb`
2. **Generation Script**: `scripts/generate-version.sh` creates `Sources/EnvPocket/Version.swift` before each build
3. **Build Integration**: All mise build tasks automatically run `gen:version` first
4. **Git Ignored**: `Version.swift` is auto-generated and excluded from version control

### Version Display

```bash
# Debug build shows git hash
.build/debug/envpocket --version
# Output: 0.5.0-dev+afd6729

# Release build shows clean version
.build/release/envpocket --version
# Output: 0.5.0
```

### Updating Version

To release a new version:
1. Use `mise run release:publish` (interactive)
2. Or manually update `version X.Y.Z` in `Formula/envpocket.rb`
3. The version generation script will automatically pick up the new version on next build

**Note**: Never manually edit `Sources/EnvPocket/Version.swift` - it's auto-generated.

## Architecture

Four-file modular architecture for separation of concerns:

### Source Files
1. **`EnvPocket.swift`**: Core business logic class
   - File operations: `saveFile()`, `getFile()`
   - Value operations: `setValue()` for direct key-value storage
   - Management: `deleteFile()`, `listKeys()`, `showHistory()`, `listVaults()`
   - Pattern matching: `matchKeys()` for wildcard operations
   - Vault support: `parseVaultAndKey()` helper, vault-aware prefixing with `::`
   - Encryption: `exportEncrypted()`, `importEncrypted()` (AES-256-GCM with PBKDF2)
   - Version history management with automatic backup

2. **`KeychainProtocol.swift`**: Protocol-based keychain abstraction
   - `KeychainProtocol`: Interface for keychain operations (save, load, delete, list)
   - `RealKeychain`: Production implementation using macOS Security framework
   - `MockKeychain`: In-memory implementation for testing (with `clear()` helper)
   - Enables dependency injection and testing without actual keychain access

3. **`ErrorTypes.swift`**: User-facing error message system
   - `KeychainError`: Maps OSStatus codes to user-friendly messages
   - `UserMessage`: Enum for consistent message display (success, error, warning, info)
   - Static factory methods for common error scenarios
   - Proper stderr routing for errors and warnings

4. **`main.swift`**: CLI interface using ArgumentParser
   - `@main EnvPocketCommand`: Main command with subcommands and vault documentation
   - Subcommands: Save, Set, Get, Delete, List, History, Export, Import
   - Type-safe argument parsing with @Argument, @Option, @Flag
   - All commands support `--vault` option with `EP_VAULT` environment variable fallback
   - Interactive password prompting with `readPassword()` (hidden echo via termios)
   - Auto-generated help text and usage information
   - Exit codes (0 for success, 1 for failure)

### Key Design Patterns
- **Protocol-Oriented Design**: `KeychainProtocol` enables testability through dependency injection
- **Namespace Isolation**: All keychain entries use prefixes (`envpocket:` or `envpocket-history:`) to prevent conflicts
- **Vault Isolation**: Optional `::` separator allows vault namespacing while supporting `/` in vault names
- **Atomic Operations**: Delete-then-add pattern ensures data consistency
- **Version Preservation**: Current version automatically backed up before updates
- **Dependency Injection**: EnvPocket accepts optional `vault` parameter, all commands resolve `--vault` flag > `EP_VAULT` env var > nil

## Storage Architecture

### Keychain Structure
- **Current Version**: `envpocket:[vault::]<key>` (vault is optional)
- **History Versions**: `envpocket-history:[vault::]<key>:<ISO8601-timestamp>`
- **Item Class**: `kSecClassGenericPassword`
- **Vault Separator**: `::` (double colon) separates vault from key
- **Attributes**:
  - `kSecAttrAccount`: Prefixed key name (account identifier) with optional vault namespace
  - `kSecValueData`: File/value contents as binary data (UTF-8 encoded)
  - `kSecAttrLabel`: Original file path OR `"(direct value)"` for set command
  - `kSecAttrComment`: Last modification timestamp (ISO8601 format)

**Examples:**
- No vault: `envpocket:api-key`
- With vault: `envpocket:prod/sql::database-url`
- History without vault: `envpocket-history:api-key:2025-01-17T10:30:00Z`
- History with vault: `envpocket-history:prod/sql::database-url:2025-01-17T10:30:00Z`

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

## Command Usage Patterns

### save vs set
- **`save <key> <file>`**: For environment files, config files, certificates
  - Stores entire file content
  - Label preserves original file path
  - Example: `envpocket save prod-env .env.production`

- **`set <key> [value]`**: For API keys, tokens, passwords
  - Stores string value directly (no file needed)
  - Label is `"(direct value)"`
  - Interactive prompt if value omitted (secure for secrets)
  - Example: `envpocket set api-key` or `envpocket set api-key "sk-123"`

### get Command
- Retrieves both file-based and value-based entries
- Use `-` as output to write to stdout: `envpocket get api-key -`
- Use `--version <index>` to retrieve history: `envpocket get key --version 1 output.txt`
- Use `--force` or `-f` to overwrite existing files without confirmation
- Omit output path to use original filename (file-based entries only)
- File overwrite safety: Prompts for confirmation unless `--force` flag is used

### delete Command
- Supports wildcards: `envpocket delete test-* -f`
- Single character wildcard: `envpocket delete v? -f` (matches v1, v2, not v10)
- Use `-f` flag to skip confirmation prompt
- Cascade deletes all history entries

### Vaults - Organizing Keys into Namespaces

Vaults allow you to organize keys into isolated namespaces. This is useful for separating environments (prod/staging/dev) or organizing by service/team.

**Key Concepts:**
- Vaults create isolated namespaces - keys in different vaults don't collide
- Supports unlimited nesting with `/` separator (e.g., `prod/sql/onprem`)
- Specified via `--vault` flag or `EP_VAULT` environment variable
- 100% backwards compatible - no vault means default namespace

**Vault Naming Rules:**
- Length: 1-100 characters
- Allowed characters: `a-zA-Z0-9/_-` (letters, numbers, slash, underscore, hyphen)
- Examples: `prod`, `staging/api`, `dev/frontend/v2`, `team-a/db/mysql`

**Storage Structure:**
- With vault: `envpocket:prod/sql/onprem::database-url`
- Without vault: `envpocket:database-url` (backwards compatible)
- History with vault: `envpocket-history:prod/sql/onprem::database-url:2025-01-17T10:30:00Z`
- Separator: `::` (double colon) allows `/` in vault names

**Usage Examples:**

```bash
# Set vault via environment variable (applies to all commands)
export EP_VAULT=prod/sql/onprem
envpocket save database-url .env.database
envpocket get database-url -
envpocket list
envpocket history database-url

# Or use --vault flag (overrides EP_VAULT)
envpocket save api-key .env --vault staging/api/v2
envpocket get api-key - --vault staging/api/v2

# List all vaults
envpocket list --vaults

# List keys in specific vault
envpocket list --vault prod/sql

# Delete with vaults (only deletes within the vault)
envpocket delete test-* -f --vault staging

# Export/import preserves vault context
envpocket export db-url db.envpocket --vault prod
envpocket import db-url db.envpocket --vault staging  # Import to different vault
```

**Vault Isolation:**
```bash
# Same key in different vaults are completely separate
export EP_VAULT=prod
envpocket set api-key "prod-secret-123"

export EP_VAULT=staging
envpocket set api-key "staging-secret-456"

envpocket get api-key - --vault prod      # Output: prod-secret-123
envpocket get api-key - --vault staging   # Output: staging-secret-456
```

**When to Use Vaults:**
- **Environment separation**: `prod`, `staging`, `dev`
- **Service organization**: `service-a/db`, `service-b/api`
- **Team isolation**: `team-frontend`, `team-backend`
- **Multi-region**: `prod/us-east`, `prod/eu-west`
- **Nested hierarchies**: `org/team/env/service`

## Common Development Patterns

### Running Local Builds
When testing changes:
```bash
swift build && .build/debug/envpocket list
```

### Testing with Swift Testing Framework
The project uses **swift-testing** (not XCTest):

```swift
import Testing
@testable import EnvPocket

@Test("Description of what this tests")
func testSomething() {
    let env = TestEnvironment()
    let result = env.envPocket.saveFile(key: "test", filePath: "/path")
    #expect(result == true)
}
```

**TestEnvironment class:**
- Uses `MockKeychain` for isolated testing without touching system keychain
- Setup in `init()`, cleanup in `deinit()`
- Automatically creates/removes temp files
- Each test gets fresh keychain state

### Adding New Commands
1. Create new subcommand struct in `main.swift` (e.g., `struct MyCommand: ParsableCommand`)
2. Add subcommand to `EnvPocketCommand.configuration.subcommands` array
3. Define arguments/options using `@Argument`, `@Option`, `@Flag` property wrappers
4. Add implementation method in `EnvPocket.swift` that returns Bool (success/failure)
5. Call implementation from subcommand's `run()` method, use `UserMessage` for output
6. Add tests in `EnvPocketMockTests.swift` using `@Test` and `#expect`
7. Update README.md with usage examples
8. Help text auto-generated by ArgumentParser from property help strings

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

- **Swift 6.0**: Project uses Swift tools version 6.0
- **No Warnings**: Must compile without warnings (`mise run lint` to check)
- **ArgumentParser**: CLI uses swift-argument-parser for type-safe argument handling
- **Error Messages**: Use `UserMessage` enum for all user-facing output (never raw print statements)
- **Protocol Abstraction**: Maintain `KeychainProtocol` for testability
- **Namespace Isolation**: All keys must have `envpocket:` or `envpocket-history:` prefixes
- **Error Handling**: Exit with status 1 on failures, route errors to stderr
- **Testing**: Use swift-testing framework with `@Test` and `#expect`
- **Labels**: File-based entries use file path, value-based entries use `"(direct value)"`
- **User Confirmations**: Destructive or overwrite operations should prompt unless `--force` flag used
