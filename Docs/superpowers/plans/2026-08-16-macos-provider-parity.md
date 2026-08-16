# macOS MiMo and DeepSeek Provider Parity Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Restore MiMo on macOS and add Settings-based, securely stored credentials for both MiMo and DeepSeek while retaining Windows-compatible fallback precedence.

**Architecture:** Selectively restore the proven MiMo implementation from `agent/add-mimo-quota`, then integrate it with the current `main` branch that already contains DeepSeek. Keep provider authentication isolated in `MiMoAuthStore` and `DeepSeekAuthStore`; both expose test-injected Keychain closures while production defaults use Security.framework. Extend the existing Providers settings tab with two secure fields and persist credentials before the normal settings callback closes the window.

**Tech Stack:** Swift 5.9 package, AppKit, Security.framework/macOS Keychain, Foundation URLSession, Swift Testing, shell packaging scripts.

---

## File Map

- Create `Sources/Quota/Providers/MiMo/MiMoAuthStore.swift`: MiMoCode account discovery and Keychain-backed console Cookie.
- Create `Sources/Quota/Providers/MiMo/MiMoModels.swift`: MiMo API wire models and quota-state mapping.
- Create `Sources/Quota/Providers/MiMo/MiMoProvider.swift`: MiMo provider lifecycle and refresh integration.
- Create `Sources/Quota/Providers/MiMo/MiMoUsageClient.swift`: Xiaomi Token Plan API requests.
- Modify `Sources/Quota/Providers/DeepSeek/DeepSeekAuthStore.swift`: add injected and production Keychain storage.
- Modify `Sources/Quota/Core/ProviderID.swift`: restore stable `.mimo` identifier.
- Modify `Sources/Quota/Core/ProviderRegistry.swift`: register both MiMo and DeepSeek.
- Modify `Sources/Quota/Settings/SettingsWindowController.swift`: render, load, save, and report failures for both secure fields.
- Modify localization files under `Sources/Quota/Localization` and `Sources/Quota/Resources`: combine MiMo and DeepSeek text.
- Create `Sources/Quota/Resources/ProviderIconMiMo.svg` and `TabIconMiMo.svg`: restore MiMo assets.
- Modify `README.md` and `README.zh-CN.md`: document five providers and both manual credential flows.
- Create `Tests/QuotaTests/MiMoModelsTests.swift`: MiMo mapping/auth regression tests.
- Create `Tests/QuotaTests/DeepSeekAuthStoreTests.swift`: DeepSeek credential precedence and persistence tests.
- Modify `Tests/QuotaTests/QuotaServiceTests.swift`: registry composition regression test.

### Task 1: Restore MiMo tests and establish RED

**Files:**
- Create: `Tests/QuotaTests/MiMoModelsTests.swift`

- [ ] **Step 1: Restore the existing MiMo behavior tests before production files**

Run:

```bash
git restore --source agent/add-mimo-quota -- Tests/QuotaTests/MiMoModelsTests.swift
```

The restored file must include mapping tests plus these authentication expectations:

```swift
let store = MiMoAuthStore(
    homeDirectory: home,
    environment: ["XIAOMI_MIMO_SESSION_COOKIE": " Cookie: a=1; b=2 "],
    keychainReader: { nil },
    keychainWriter: { _ in }
)
#expect(try store.loadSessionCookie() == "a=1; b=2")
```

```swift
let store = MiMoAuthStore(
    homeDirectory: URL(fileURLWithPath: "/nonexistent"),
    environment: [:],
    keychainReader: { "session=from-keychain" },
    keychainWriter: { _ in }
)
#expect(try store.loadSessionCookie() == "session=from-keychain")
```

- [ ] **Step 2: Add save, delete, and invalid multiline tests**

Append tests that capture the injected writer:

```swift
@Test func savesAndDeletesNormalizedMiMoCookie() throws {
    var writes: [String?] = []
    let store = MiMoAuthStore(
        homeDirectory: URL(fileURLWithPath: "/nonexistent"),
        environment: [:],
        keychainReader: { nil },
        keychainWriter: { writes.append($0) }
    )

    try store.saveSessionCookie(" Cookie: session=manual ")
    try store.saveSessionCookie("")

    #expect(writes.count == 2)
    #expect(writes[0] == "session=manual")
    #expect(writes[1] == nil)
}

@Test func rejectsMultilineMiMoCookie() {
    let store = MiMoAuthStore(
        homeDirectory: URL(fileURLWithPath: "/nonexistent"),
        environment: ["XIAOMI_MIMO_SESSION_COOKIE": "a=1\nb=2"],
        keychainReader: { nil },
        keychainWriter: { _ in }
    )
    #expect(throws: MiMoQuotaError.self) {
        _ = try store.loadSessionCookie()
    }
}
```

- [ ] **Step 3: Run the focused test target and verify RED**

Run:

```bash
swift test --filter MiMo
```

Expected: FAIL because `MiMoAuthStore`, `MiMoUsageResponse`, and related MiMo production types are absent. If this machine reports `no such module 'Testing'` before compiling the tests, record that environment limitation and use `swift build -c release --arch x86_64` later as the compilation gate; do not misreport the tests as passing.

- [ ] **Step 4: Commit tests only**

```bash
git add Tests/QuotaTests/MiMoModelsTests.swift
git commit -m "test: define macOS MiMo provider behavior"
```

### Task 2: Restore the MiMo provider implementation and reach GREEN

**Files:**
- Create: `Sources/Quota/Providers/MiMo/MiMoAuthStore.swift`
- Create: `Sources/Quota/Providers/MiMo/MiMoModels.swift`
- Create: `Sources/Quota/Providers/MiMo/MiMoProvider.swift`
- Create: `Sources/Quota/Providers/MiMo/MiMoUsageClient.swift`
- Create: `Sources/Quota/Resources/ProviderIconMiMo.svg`
- Create: `Sources/Quota/Resources/TabIconMiMo.svg`

- [ ] **Step 1: Restore the focused MiMo implementation from the feature branch**

Run:

```bash
git restore --source agent/add-mimo-quota -- \
  Sources/Quota/Providers/MiMo/MiMoAuthStore.swift \
  Sources/Quota/Providers/MiMo/MiMoModels.swift \
  Sources/Quota/Providers/MiMo/MiMoProvider.swift \
  Sources/Quota/Providers/MiMo/MiMoUsageClient.swift \
  Sources/Quota/Resources/ProviderIconMiMo.svg \
  Sources/Quota/Resources/TabIconMiMo.svg
```

Keep the existing auth contract:

```swift
func loadSessionCookie() throws -> String {
    let rawValue = environment["XIAOMI_MIMO_SESSION_COOKIE"] ?? keychainReader()
    guard let cookie = Self.normalizeCookie(rawValue), !cookie.isEmpty else {
        throw MiMoQuotaError.sessionCookieMissing
    }
    return cookie
}

func savedSessionCookie() -> String {
    Self.normalizeCookie(keychainReader()) ?? ""
}

func saveSessionCookie(_ value: String) throws {
    let normalized = Self.normalizeCookie(value)
    try keychainWriter(normalized?.isEmpty == false ? normalized : nil)
}
```

- [ ] **Step 2: Run MiMo tests and verify GREEN or the documented framework blocker**

```bash
swift test --filter MiMo
```

Expected in a complete Swift Testing environment: all MiMo tests PASS. On this machine, the only acceptable blocker is the previously observed missing `Testing` module; MiMo source compilation must be checked in Task 6.

- [ ] **Step 3: Commit the MiMo implementation**

```bash
git add Sources/Quota/Providers/MiMo Sources/Quota/Resources/ProviderIconMiMo.svg Sources/Quota/Resources/TabIconMiMo.svg
git commit -m "feat: restore MiMo provider on macOS"
```

### Task 3: Add DeepSeek Keychain tests and implementation

**Files:**
- Create: `Tests/QuotaTests/DeepSeekAuthStoreTests.swift`
- Modify: `Sources/Quota/Providers/DeepSeek/DeepSeekAuthStore.swift`

- [ ] **Step 1: Write DeepSeek credential tests first**

Create tests using injected closures:

```swift
import Foundation
import Testing
@testable import Quota

@Test func deepSeekCredentialPrecedenceIsEnvironmentThenFileThenKeychain() throws {
    let home = FileManager.default.temporaryDirectory
        .appendingPathComponent("quota-deepseek-auth-\(UUID().uuidString)")
    let config = home.appendingPathComponent(".deepseek")
    try FileManager.default.createDirectory(at: config, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: home) }
    try Data("file-key".utf8).write(to: config.appendingPathComponent("api_key"))

    let environmentStore = DeepSeekAuthStore(
        homeDirectory: home,
        environment: ["DEEPSEEK_API_KEY": " env-key "],
        keychainReader: { "saved-key" },
        keychainWriter: { _ in }
    )
    #expect(try environmentStore.loadAPIKey() == "env-key")

    let fileStore = DeepSeekAuthStore(
        homeDirectory: home,
        environment: [:],
        keychainReader: { "saved-key" },
        keychainWriter: { _ in }
    )
    #expect(try fileStore.loadAPIKey() == "file-key")

    try FileManager.default.removeItem(at: config.appendingPathComponent("api_key"))
    #expect(try fileStore.loadAPIKey() == "saved-key")
}

@Test func savesNormalizesAndDeletesDeepSeekAPIKey() throws {
    var writes: [String?] = []
    let store = DeepSeekAuthStore(
        homeDirectory: URL(fileURLWithPath: "/nonexistent"),
        environment: [:],
        keychainReader: { "saved-key" },
        keychainWriter: { writes.append($0) }
    )
    #expect(store.savedAPIKey() == "saved-key")
    try store.saveAPIKey("  \"sk-manual\"  ")
    try store.saveAPIKey(" ")
    #expect(writes[0] == "sk-manual")
    #expect(writes[1] == nil)
}
```

- [ ] **Step 2: Verify RED**

```bash
swift test --filter DeepSeekAuthStore
```

Expected: FAIL because the current initializer lacks Keychain closures and `savedAPIKey`/`saveAPIKey` do not exist, subject to the documented missing `Testing` module limitation.

- [ ] **Step 3: Implement injectable Keychain-backed storage**

Add `import Security`, constants, closures, and APIs following this contract:

```swift
static let shared = DeepSeekAuthStore()
static let keychainService = "Quota-DeepSeek-api-key"
static let keychainAccount = "api.deepseek.com"

private let keychainReader: () -> String?
private let keychainWriter: (String?) throws -> Void

func loadAPIKey() throws -> String {
    if let value = Self.normalizeAPIKey(environment["DEEPSEEK_API_KEY"]), !value.isEmpty {
        return value
    }
    if let data = try? Data(contentsOf: apiKeyFileURL),
       let value = Self.normalizeAPIKey(String(data: data, encoding: .utf8)),
       !value.isEmpty {
        return value
    }
    if let value = Self.normalizeAPIKey(keychainReader()), !value.isEmpty {
        return value
    }
    throw DeepSeekQuotaError.notSignedIn
}

func savedAPIKey() -> String {
    Self.normalizeAPIKey(keychainReader()) ?? ""
}

func saveAPIKey(_ value: String) throws {
    let normalized = Self.normalizeAPIKey(value)
    try keychainWriter(normalized?.isEmpty == false ? normalized : nil)
}
```

Use the same `SecItemCopyMatching`, `SecItemUpdate`/`SecItemAdd`, and `SecItemDelete` pattern as `MiMoAuthStore`, but map write failures to a new `DeepSeekQuotaError.keychainWriteFailed` case.

- [ ] **Step 4: Run tests and verify GREEN**

```bash
swift test --filter DeepSeekAuthStore
```

Expected in a complete environment: both tests PASS.

- [ ] **Step 5: Commit DeepSeek secure storage**

```bash
git add Tests/QuotaTests/DeepSeekAuthStoreTests.swift Sources/Quota/Providers/DeepSeek/DeepSeekAuthStore.swift Sources/Quota/Providers/DeepSeek/DeepSeekModels.swift
git commit -m "feat: store DeepSeek API key in macOS Keychain"
```

### Task 4: Register both providers and merge localization

**Files:**
- Modify: `Sources/Quota/Core/ProviderID.swift`
- Modify: `Sources/Quota/Core/ProviderRegistry.swift`
- Modify: `Sources/Quota/Localization/L.swift`
- Modify: `Sources/Quota/Localization/LocalizationKey.swift`
- Modify: `Sources/Quota/Resources/en.lproj/Localizable.strings`
- Modify: `Sources/Quota/Resources/zh-Hans.lproj/Localizable.strings`
- Modify: `Tests/QuotaTests/QuotaServiceTests.swift`

- [ ] **Step 1: Add a failing registry test**

```swift
@Test func defaultRegistryContainsMiMoAndDeepSeekExactlyOnce() {
    let ids = ProviderRegistry.makeDefault().providerIDs
    #expect(ids.filter { $0 == .mimo }.count == 1)
    #expect(ids.filter { $0 == .deepseek }.count == 1)
    #expect(ids.count == 5)
}
```

- [ ] **Step 2: Verify RED**

```bash
swift test --filter defaultRegistryContainsMiMoAndDeepSeekExactlyOnce
```

Expected: FAIL because `.mimo` and the MiMo registry entry are absent.

- [ ] **Step 3: Add the identifier and registry entry**

```swift
static let mimo = ProviderID(rawValue: "mimo")
static let deepseek = ProviderID(rawValue: "deepseek")
```

Use this composition order:

```swift
let mimo = MiMoProvider(proxySettingsStore: proxySettingsStore)
let deepseek = DeepSeekProvider(proxySettingsStore: proxySettingsStore)
return ProviderRegistry(providers: [codex, grok, claude, mimo, deepseek])
```

- [ ] **Step 4: Merge localization without deleting DeepSeek keys**

Restore the MiMo keys from `agent/add-mimo-quota`, then retain all current DeepSeek keys. Add DeepSeek settings keys:

```swift
case deepseekAPIKeyLabel = "settings.providers.deepseekAPIKey.label"
case deepseekAPIKeyPlaceholder = "settings.providers.deepseekAPIKey.placeholder"
case deepseekAPIKeyHelp = "settings.providers.deepseekAPIKey.help"
case deepseekAPIKeySaveErrorTitle = "settings.providers.deepseekAPIKey.saveErrorTitle"
```

English strings:

```text
"settings.providers.deepseekAPIKey.label" = "DeepSeek API Key";
"settings.providers.deepseekAPIKey.placeholder" = "Paste the DeepSeek API key";
"settings.providers.deepseekAPIKey.help" = "The saved key is stored only in macOS Keychain. DEEPSEEK_API_KEY and ~/.deepseek/api_key remain supported and take priority.";
"settings.providers.deepseekAPIKey.saveErrorTitle" = "Could not save DeepSeek API Key";
```

Chinese strings:

```text
"settings.providers.deepseekAPIKey.label" = "DeepSeek API Key";
"settings.providers.deepseekAPIKey.placeholder" = "粘贴 DeepSeek API 密钥";
"settings.providers.deepseekAPIKey.help" = "手动填写的密钥仅保存在 macOS 钥匙串中；仍兼容 DEEPSEEK_API_KEY 和 ~/.deepseek/api_key，且它们优先。";
"settings.providers.deepseekAPIKey.saveErrorTitle" = "无法保存 DeepSeek API Key";
```

Update `error.deepseekNotSignedIn` in both languages to mention Settings as the manual path, and add `error.deepseekKeychainWriteFailed`.

- [ ] **Step 5: Run the registry and model tests**

```bash
swift test --filter defaultRegistryContainsMiMoAndDeepSeekExactlyOnce
swift test --filter MiMo
swift test --filter DeepSeek
```

Expected in a complete environment: PASS.

- [ ] **Step 6: Commit provider composition and text**

```bash
git add Sources/Quota/Core Sources/Quota/Localization Sources/Quota/Resources Tests/QuotaTests/QuotaServiceTests.swift
git commit -m "feat: expose MiMo and DeepSeek providers on macOS"
```

### Task 5: Add both manual credentials to Settings

**Files:**
- Modify: `Sources/Quota/Settings/SettingsWindowController.swift`

- [ ] **Step 1: Add secure fields and loaded-value state**

Add alongside the provider controls:

```swift
private let mimoCookieLabel = NSTextField(labelWithString: "")
private let mimoCookieField = NSSecureTextField(string: "")
private let mimoCookieHelpLabel = NSTextField(wrappingLabelWithString: "")
private let deepseekAPIKeyLabel = NSTextField(labelWithString: "")
private let deepseekAPIKeyField = NSSecureTextField(string: "")
private let deepseekAPIKeyHelpLabel = NSTextField(wrappingLabelWithString: "")
private var loadedMiMoCookie = ""
private var loadedDeepSeekAPIKey = ""
```

- [ ] **Step 2: Render fields in the Providers stack**

Place rows after the provider help text in this order:

```swift
let stack = NSStackView(views: [
    header,
    providerListView,
    providersHelpLabel,
    mimoCookieRow,
    mimoCookieHelpLabel,
    deepseekAPIKeyRow,
    deepseekAPIKeyHelpLabel,
])
```

Use `NSSecureTextField`, localized labels/placeholders/help text, and a settings window/container height sufficient for five provider rows plus both fields without clipping.

- [ ] **Step 3: Load only saved Keychain values**

```swift
private func reloadProviderCredentials() {
    loadedMiMoCookie = MiMoAuthStore.shared.savedSessionCookie()
    mimoCookieField.stringValue = loadedMiMoCookie
    loadedDeepSeekAPIKey = DeepSeekAuthStore.shared.savedAPIKey()
    deepseekAPIKeyField.stringValue = loadedDeepSeekAPIKey
}
```

- [ ] **Step 4: Persist changed values before closing**

In `save()`, after proxy/hotkey validation and before `onSave`:

```swift
do {
    let mimoCookie = mimoCookieField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
    if mimoCookie != loadedMiMoCookie {
        try MiMoAuthStore.shared.saveSessionCookie(mimoCookie)
        loadedMiMoCookie = MiMoAuthStore.shared.savedSessionCookie()
    }

    let deepseekAPIKey = deepseekAPIKeyField.stringValue
        .trimmingCharacters(in: .whitespacesAndNewlines)
    if deepseekAPIKey != loadedDeepSeekAPIKey {
        try DeepSeekAuthStore.shared.saveAPIKey(deepseekAPIKey)
        loadedDeepSeekAPIKey = DeepSeekAuthStore.shared.savedAPIKey()
    }
} catch let error as MiMoQuotaError {
    presentCredentialSaveError(title: L.mimoCookieSaveErrorTitle, error: error)
    return
} catch {
    presentCredentialSaveError(title: L.deepseekAPIKeySaveErrorTitle, error: error)
    return
}
```

Use a shared alert helper taking a localized title. Confirm Cancel only closes the window and performs no writes.

- [ ] **Step 5: Compile the settings integration**

```bash
swift build -c release --arch x86_64
```

Expected: `Build complete!` with no errors. Existing warnings may remain but newly introduced unused-variable or missing-localization errors must be fixed.

- [ ] **Step 6: Commit Settings integration**

```bash
git add Sources/Quota/Settings/SettingsWindowController.swift
git commit -m "feat: add manual MiMo and DeepSeek credentials to settings"
```

### Task 6: Documentation, complete verification, and packaging

**Files:**
- Modify: `README.md`
- Modify: `README.zh-CN.md`
- Output: `.build/package/Quota.app`
- Output: `.build/Quota-0.5.0.dmg`

- [ ] **Step 1: Document both credential workflows**

Update the provider list to Codex, Claude, Grok, MiMo, and DeepSeek. Document:

```text
MiMo: paste the signed-in Xiaomi console Cookie in Settings → Providers; it is stored in macOS Keychain.
DeepSeek: paste an API key in Settings → Providers; DEEPSEEK_API_KEY and ~/.deepseek/api_key remain supported with higher priority.
```

- [ ] **Step 2: Run all available tests freshly**

```bash
swift test
```

Expected in a complete environment: all tests PASS with zero failures. If the local toolchain still reports `no such module 'Testing'`, report tests as blocked by the toolchain and continue only with the full release compilation; do not claim tests passed.

- [ ] **Step 3: Run a clean release build**

Avoid root-owned stale caches by using the current user-owned `.build`. Run:

```bash
swift build -c release --arch x86_64
```

Expected: exit code 0 and `Build complete!`.

- [ ] **Step 4: Package the app and DMG**

```bash
bash Scripts/package-dmg.sh
```

Expected outputs:

```text
.build/package/Quota.app
.build/Quota-0.5.0.dmg
```

- [ ] **Step 5: Verify architecture, signature, version, and both providers' resources**

```bash
lipo -info .build/package/Quota.app/Contents/MacOS/Quota
codesign --verify --deep --strict --verbose=1 .build/package/Quota.app
/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' .build/package/Quota.app/Contents/Info.plist
find .build/package/Quota.app/Contents/Resources/Quota_Quota.bundle \
  \( -iname '*MiMo*' -o -iname '*DeepSeek*' \) -print
ls -lh .build/Quota-0.5.0.dmg
```

Expected: x86_64 architecture, valid signature, version `0.5.0`, all four provider/tab icons, and a non-empty DMG.

- [ ] **Step 6: Review diff and commit documentation**

```bash
git diff --check
git status --short
git add README.md README.zh-CN.md
git commit -m "docs: explain MiMo and DeepSeek setup"
```

- [ ] **Step 7: Final requirement audit**

Confirm from source and artifacts:

- Provider registry contains both `.mimo` and `.deepseek`.
- Both secure fields are visible in Providers settings.
- MiMo uses environment then Keychain.
- DeepSeek uses environment then file then Keychain.
- Empty manual values delete saved credentials.
- Both provider resources exist in the app bundle.
- App and DMG paths are reported with any test-framework limitation stated explicitly.
