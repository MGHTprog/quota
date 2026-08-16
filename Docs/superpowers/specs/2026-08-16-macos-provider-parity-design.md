# macOS MiMo and DeepSeek Provider Parity Design

## Goal

Bring the macOS application to functional parity with the Windows application for MiMo and DeepSeek. Both providers must appear in the provider list, accept credentials entered manually in Settings, store those credentials securely, and preserve the same external credential fallbacks used by Windows.

## Scope

This change is limited to the macOS Swift application. Existing Windows code and binaries remain unchanged.

The macOS provider registry will expose Codex, Grok, Claude, MiMo, and DeepSeek. Existing provider ordering and enablement preferences will continue to resolve against the available provider IDs so current users retain their saved choices while the newly available provider is appended by the existing configuration logic.

## Architecture

### MiMo restoration

Restore the MiMo implementation from `agent/add-mimo-quota` selectively instead of merging that branch wholesale. The restored units include:

- MiMo authentication, API models, usage client, and provider implementation.
- MiMo provider and tab icons.
- MiMo localization keys and strings.
- MiMo model and mapping tests.
- MiMo registration in `ProviderRegistry`.
- The secure MiMo Cookie field in the macOS provider settings tab.

MiMoCode's `auth.json` remains responsible for identifying the signed-in Xiaomi account and regional base URL. The Xiaomi console Cookie is resolved in this order:

1. `XIAOMI_MIMO_SESSION_COOKIE` environment variable.
2. A value entered in Settings and stored in macOS Keychain.

The settings field displays only the Keychain-saved value, matching Windows behavior where environment-based credentials are not copied into the editable field.

### DeepSeek manual credential

Extend `DeepSeekAuthStore` with a dedicated macOS Keychain entry. DeepSeek API keys are resolved in the same order as Windows:

1. `DEEPSEEK_API_KEY` environment variable.
2. `~/.deepseek/api_key` configuration file.
3. A value entered in Settings and stored in macOS Keychain.

The settings field displays only the Keychain-saved value. Saving an empty value deletes the saved Keychain item without affecting environment variables or the configuration file.

### Secure storage

MiMo and DeepSeek use separate generic-password Keychain services and accounts. Keychain writes update an existing item or create it with `kSecAttrAccessibleAfterFirstUnlock`. Deletes treat a missing item as success.

Credential normalization follows Windows-visible behavior:

- MiMo accepts either a raw Cookie value or a complete value beginning with `Cookie:`. The prefix and surrounding whitespace are removed. Embedded newlines are rejected.
- DeepSeek trims surrounding whitespace and removes one matching pair of surrounding single or double quotes.

Provider requests read credentials when refreshing, so newly saved values take effect without restarting the application. Saving Settings invalidates active provider connections through the existing save flow.

## Settings UI

The Providers tab contains the reorderable provider list followed by two secure text fields:

1. MiMo Cookie.
2. DeepSeek API Key.

Each field has localized help text describing accepted input and fallback sources. Both use `NSSecureTextField`. The settings window loads saved Keychain values when opened.

On Save, changed credentials are normalized and written independently. If either write fails, an alert identifies the affected credential and the settings window remains open. Cancel does not modify Keychain values.

## Data Flow

1. The user opens Settings and the controller loads saved Keychain values into secure fields.
2. The user edits provider enablement/order and either credential.
3. Save validates general settings, then persists changed MiMo and DeepSeek credentials.
4. The normal settings save callback persists provider configuration and invalidates connections.
5. The next refresh resolves credentials using each provider's precedence rules and requests current quota or balance data.
6. Provider errors are mapped to localized missing, expired, invalid-response, and HTTP failure messages.

## Error Handling

- Missing MiMoCode account data reports the existing MiMo sign-in error.
- Missing or malformed MiMo Cookie reports the existing session-cookie error.
- Missing DeepSeek credentials report the existing DeepSeek not-signed-in error, updated to mention the Settings field.
- Keychain failures produce provider-specific save alerts and do not close Settings.
- Empty saved credentials delete only the relevant Keychain item.
- HTTP authentication and response errors continue through each provider's existing error mapping.

## Testing

Implementation follows test-driven development:

- MiMo authentication tests cover account discovery, environment-over-Keychain precedence, Cookie normalization, saved value loading, saving, and deletion.
- DeepSeek authentication tests cover environment, file, and Keychain precedence; quoted-key normalization; saved value loading; saving; deletion; and missing credentials.
- Provider registry tests verify both MiMo and DeepSeek are available exactly once.
- Existing MiMo and DeepSeek model mapping tests verify API payload conversion.
- A release build verifies all restored sources and resources compile into the app.
- Packaging verification checks the app version, x86_64 binary architecture, DeepSeek/MiMo resources, code signature, and generated DMG.

## Deliverables

- Updated macOS source and tests with MiMo and DeepSeek parity.
- A signed ad-hoc `Quota.app` for x86_64 macOS.
- A packaged `Quota-0.5.0.dmg` containing the updated app.

