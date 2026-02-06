# envpocket

A secure command-line utility for macOS that stores environment files in the system keychain with automatic versioning and history management.

## Features

- **Secure Storage**: Uses macOS Keychain for encrypted storage of sensitive environment files
- **Version History**: Automatically maintains version history when files are updated
- **File Path Tracking**: Remembers original file locations for easy reference
- **Simple CLI**: Intuitive commands for saving, retrieving, and managing stored files
- **Atomic Operations**: Ensures data consistency during updates
- **Clean Namespace**: All keychain entries are prefixed to avoid conflicts
- **Team Sharing**: Export/import encrypted files for secure team collaboration
- **Vault Support**: Organize keys into isolated namespaces (e.g., `prod/sql/onprem`) for multi-environment workflows

## Installation

### Using Homebrew (Recommended)

```bash
brew install thieso2/tap/envpocket
```

Or if you prefer to tap first:

```bash
brew tap thieso2/tap
brew install envpocket
```

### Download Binary

Download the latest release directly from [GitHub Releases](https://github.com/thieso2/envpocket/releases):

```bash
# Download the latest release
wget https://github.com/thieso2/envpocket/releases/latest/download/envpocket-macos.tar.gz

# Extract and install
tar xzf envpocket-macos.tar.gz
sudo cp envpocket /usr/local/bin/

# Verify installation
envpocket --version
```

### Building from Source

#### Prerequisites

- macOS 10.15 or later
- Swift 5.9 or later
- Xcode Command Line Tools

```bash
# Clone the repository
git clone https://github.com/thieso2/envpocket.git
cd envpocket

# Build the release version
swift build -c release

# Copy to a location in your PATH (optional)
sudo cp .build/release/envpocket /usr/local/bin/
```

### Quick Build

```bash
# Build and run directly
swift run envpocket <command> [args]
```

## Usage

### Save a File

Store a file in the keychain under a given key:

```bash
envpocket save myapp-prod .env.production
```

### Set a Value

Store a value directly (without a file):

```bash
# With value as argument
envpocket set api-key "sk-1234567890"

# Or be prompted for the value (useful for secrets)
envpocket set api-key
# You'll be prompted: Enter value for 'api-key':
```

This is useful for storing API keys, tokens, or other simple values without creating a file first.

### Retrieve a File

Get the latest version of a stored file:

```bash
envpocket get myapp-prod .env
```

### Retrieve a Specific Version

Get a historical version by index (0 = most recent):

```bash
envpocket get myapp-prod --version 2 .env.backup
```

### List All Stored Files

View all stored keys with metadata:

```bash
envpocket list
```

Output shows:
- Original file paths
- Last modification dates
- Number of versions in history

### View Version History

See all available versions for a specific key:

```bash
envpocket history myapp-prod
```

### Delete a File

Remove a file and all its versions from the keychain:

```bash
envpocket delete myapp-prod
```

### Using Vaults for Organization

Vaults allow you to organize keys into isolated namespaces, perfect for separating environments or services:

```bash
# Set vault via environment variable (applies to all commands)
export EP_VAULT=prod/sql
envpocket save database-url .env.database
envpocket get database-url -

# Or use --vault flag (overrides EP_VAULT)
envpocket save api-key .env --vault staging/api/v2
envpocket get api-key - --vault staging/api/v2

# List all vaults
envpocket list --vaults

# List keys in a specific vault
envpocket list --vault prod/sql

# Delete only within a vault
envpocket delete test-* -f --vault staging
```

**Vault Features:**
- **Isolated Namespaces**: Keys in different vaults are completely separate
- **Nested Support**: Use `/` for hierarchy (e.g., `prod/sql/onprem`)
- **Backwards Compatible**: No vault means default namespace
- **Per-Command**: Via `--vault` flag or `EP_VAULT` environment variable

### Export for Team Sharing

Export an encrypted version of your environment file:

```bash
# With password on command line
envpocket export myapp-prod --password "shared-team-secret"

# With interactive password prompt (recommended for security)
envpocket export myapp-prod
# You'll be prompted to enter and confirm the password
```

This creates `myapp-prod.envpocket` that can be safely shared via Git, Slack, email, etc.

### Import from Team Member

Import an encrypted environment file shared by a team member:

```bash
# With password on command line
envpocket import myapp-prod myapp-prod.envpocket --password "shared-team-secret"

# With interactive password prompt (recommended for security)
envpocket import myapp-prod myapp-prod.envpocket
# You'll be prompted to enter the password
```

## Examples

### Managing Multiple Environment Files

```bash
# Store different environment configurations
envpocket save app-dev .env.development
envpocket save app-staging .env.staging
envpocket save app-prod .env.production

# List all stored configurations
envpocket list

# Retrieve specific environment
envpocket get app-staging .env
```

### Storing API Keys and Secrets

```bash
# Store API keys and tokens directly
envpocket set openai-key "sk-proj-abc123..."
envpocket set github-token "ghp_xyz789..."
envpocket set db-password "super-secret-password"

# Retrieve and use in scripts
API_KEY=$(envpocket get openai-key -)
curl -H "Authorization: Bearer $API_KEY" https://api.openai.com/v1/models

# Update a value (old version automatically backed up)
envpocket set openai-key "sk-proj-new-key..."

# View history of changes
envpocket history openai-key
```

### Quick Environment Switching with Vaults

```bash
# Store credentials for different environments
envpocket set db-url "postgres://prod-host/db" --vault prod
envpocket set db-url "postgres://staging-host/db" --vault staging
envpocket set db-url "postgres://localhost/db" --vault dev

# Switch environments by changing vault
export EP_VAULT=prod
./run-migrations.sh  # Uses production database

export EP_VAULT=staging
./run-migrations.sh  # Uses staging database

export EP_VAULT=dev
./run-migrations.sh  # Uses local development database

# In your scripts, retrieve from current vault
DB_URL=$(envpocket get db-url -)
echo "Connecting to: $DB_URL"
```

### Working with Versions

```bash
# Save initial version
envpocket save database-config db.conf

# Make changes and save again (previous version backed up automatically)
envpocket save database-config db.conf

# View history
envpocket history database-config

# Retrieve previous version
envpocket get database-config --version 1 db.conf.old
```

### Backup and Restore Workflow

```bash
# Backup all .env files
for file in .env*; do
  envpocket save "backup-$(basename $file)" "$file"
done

# Restore specific backup
envpocket get backup-.env.production .env.production
```

### Multi-Environment Workflow with Vaults

```bash
# Store production database configs in prod vault
export EP_VAULT=prod/database
envpocket save postgres-url .env.postgres
envpocket save redis-url .env.redis
envpocket save mongodb-url .env.mongo

# Store staging database configs in staging vault
export EP_VAULT=staging/database
envpocket save postgres-url .env.postgres
envpocket save redis-url .env.redis

# Same key names, different vaults = no conflicts!
envpocket get postgres-url - --vault prod/database
envpocket get postgres-url - --vault staging/database

# List all database vaults
envpocket list --vaults
```

### Service-Based Organization

```bash
# Organize by microservice
envpocket save stripe-key .env --vault payments/prod
envpocket save twilio-key .env --vault notifications/prod
envpocket save sendgrid-key .env --vault email/prod

# Store development versions separately
envpocket save stripe-key .env --vault payments/dev
envpocket save twilio-key .env --vault notifications/dev

# Quick switching between environments
export EP_VAULT=payments/prod
envpocket list  # Shows only production payment keys

export EP_VAULT=payments/dev
envpocket list  # Shows only development payment keys
```

### Team-Based Vault Isolation

```bash
# Frontend team vault
envpocket save next-env .env --vault team-frontend/prod
envpocket save react-env .env --vault team-frontend/staging

# Backend team vault
envpocket save api-keys .env --vault team-backend/prod
envpocket save db-config .env --vault team-backend/staging

# DevOps team has access to all vaults
envpocket list --vaults  # Shows all team vaults
```

### Regional Deployment with Vaults

```bash
# US East region
envpocket save app-config .env --vault prod/us-east/app
envpocket save db-config .env --vault prod/us-east/db

# EU West region
envpocket save app-config .env --vault prod/eu-west/app
envpocket save db-config .env --vault prod/eu-west/db

# Deploy to specific region
export EP_VAULT=prod/us-east/app
envpocket get app-config .env
./deploy.sh us-east-1
```

### Team Collaboration Workflow

```bash
# Team lead exports production environment from vault
envpocket export production-env --password "team-secret-2024" --vault prod

# Commit encrypted file to repository
git add production-env.envpocket
git commit -m "Update production environment configuration"
git push

# Team member pulls and imports to their vault
git pull
envpocket import production-env production-env.envpocket --password "team-secret-2024" --vault prod

# Now team member can use the environment
envpocket get production-env .env --vault prod
```

### Secure Environment Distribution

```bash
# Export multiple environments with the same password
envpocket export app-dev --password "dev-team-pass" app-dev.envpocket
envpocket export app-staging --password "dev-team-pass" app-staging.envpocket
envpocket export app-prod --password "prod-team-pass" app-prod.envpocket

# Different passwords for different security levels
# Share dev/staging password with all developers
# Share production password only with senior developers/DevOps
```

## Security Considerations

- **Keychain Access**: envpocket requires keychain access permissions on first use
- **User-Specific**: Stored items are only accessible by the current user
- **Encrypted Storage**: Data is encrypted by macOS Keychain Services
- **No Network Access**: All operations are local to your machine
- **Password Protection**: Keychain may require authentication based on your security settings
- **Team Sharing Security**: 
  - Export/import uses AES-256-GCM encryption with PBKDF2 key derivation
  - Passwords should be shared through secure channels (password managers, encrypted messaging)
  - Each exported file includes a random salt for added security
  - Version history is preserved during export/import

### Note: Keychain Isolation

envpocket implements strict namespace isolation to ensure it only touches its own keychain entries:

- **Mandatory Prefix System**: All entries are prefixed with `envpocket:` (current) or `envpocket-history:` (versions)
- **Vault Namespacing**: When using vaults, entries use format `envpocket:<vault>::<key>` for complete isolation
- **Filtered Operations**: List operations only process entries with envpocket prefixes, ignoring all other keychain items
- **Exact Matching**: All keychain operations (read/write/delete) use exact account matching with prefixed keys - no wildcard queries at the keychain API level
- **Vault Scoping**: All operations are vault-scoped when a vault is specified, preventing cross-vault access

This design guarantees that envpocket cannot access or modify any keychain entries created by other applications, and that vaults provide true isolation between different namespaces.

### Advanced Security Hardening

For enhanced security features including code signing, notarization, and Hardened Runtime, see the [`hardening` branch](https://github.com/thieso2/envpocket/tree/hardening). This branch includes:

- Entitlements configuration for runtime restrictions
- Code signing and notarization scripts  
- Keychain access group support
- Comprehensive security documentation

These features require an Apple Developer account but provide additional security for production deployments.

## Technical Details

### Storage Structure

**Without Vaults (Default Namespace):**
- **Current Version**: `envpocket:<key>`
- **History Versions**: `envpocket-history:<key>:<timestamp>`

**With Vaults:**
- **Current Version**: `envpocket:<vault>::<key>`
- **History Versions**: `envpocket-history:<vault>::<key>:<timestamp>`
- **Separator**: `::` (double colon) allows `/` in vault names
- **Examples**:
  - `envpocket:prod/sql::database-url`
  - `envpocket-history:prod/sql::database-url:2025-01-17T10:30:00Z`

**Metadata:**
- **Timestamps**: ISO 8601 format for precise versioning
- **Original file paths** and modification times preserved
- **Vault context** included in export/import metadata

### Keychain Item Type

Files are stored as generic password items (`kSecClassGenericPassword`) with:
- **Account**: Prefixed key name with optional vault namespace (`envpocket:[vault::]<key>`)
- **Data**: File contents as binary
- **Label**: Original file path or `"(direct value)"` for set command
- **Comment**: Last modification timestamp

### Vault Isolation

- Keys in different vaults are **completely isolated**
- Same key name can exist in multiple vaults without conflict
- List operations are vault-scoped (only show keys in current vault)
- History is vault-specific (each vault maintains independent version history)
- Delete operations only affect keys within the specified vault

## Troubleshooting

### Permission Denied

If you encounter keychain access issues:

1. Check System Preferences > Security & Privacy > Privacy > Full Disk Access
2. Ensure Terminal has necessary permissions
3. You may need to unlock your keychain: `security unlock-keychain`

### File Not Found

When retrieving files:
- Use `envpocket list` to verify the key exists
- Check spelling and case sensitivity
- Use `envpocket history <key>` to see available versions

### Build Errors

For Swift build issues:
- Verify Swift version: `swift --version`
- Update Xcode Command Line Tools: `xcode-select --install`
- Clean build artifacts: `swift package clean`

## Development

### Using mise Task Runner

This project includes [mise](https://mise.jdx.dev/) task definitions for common development workflows:

```bash
# Install mise (if not already installed)
curl https://mise.run | sh

# Build and test
mise run dev

# Build release version
mise run build:release

# Run tests
mise run test

# Install locally to ~/.local/bin
mise run install:local

# Check for warnings
mise run lint

# See all available tasks
mise tasks
```

### Running Tests

```bash
swift test

# Or with mise
mise run test
```

### Debug Build

```bash
swift build
.build/debug/envpocket <command> [args]

# Or with mise
mise run build
```

### Project Structure

```
envpocket/
├── Package.swift              # Swift Package Manager manifest
├── VERSION                    # Version source (read by build scripts)
├── Sources/
│   └── EnvPocket/
│       ├── main.swift         # CLI interface (ArgumentParser)
│       ├── EnvPocket.swift    # Core business logic
│       ├── KeychainProtocol.swift  # Keychain abstraction
│       └── ErrorTypes.swift   # User-facing error messages
├── Tests/
│   └── EnvPocketTests/
│       └── EnvPocketMockTests.swift
├── scripts/
│   └── generate-version.sh   # Generates Version.swift from VERSION
└── .github/
    └── workflows/
        └── release.yml        # CI: build, release, push formula to tap
```

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

1. Fork the repository
2. Create your feature branch (`git checkout -b feature/AmazingFeature`)
3. Commit your changes (`git commit -m 'Add some AmazingFeature'`)
4. Push to the branch (`git push origin feature/AmazingFeature`)
5. Open a Pull Request

## License

This project is licensed under the MIT License - see the LICENSE file for details.

## Acknowledgments

- Built with Swift and macOS Security Framework
- Inspired by the need for secure local environment file management
- Thanks to the Swift community for excellent documentation and tools