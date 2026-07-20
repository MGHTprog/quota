import Foundation

/// Resolves SPM / packaged app resources without crashing on `Bundle.module`.
///
/// In a distributed `.app`, resources live in `Contents/Resources/Quota_Quota.bundle`.
/// Accessing `Bundle.module` there can assert during one-time initialization when the
/// generated SPM accessor cannot locate its expected bundle layout — which is exactly
/// what crashed the menu popup after opening a GitHub release build.
enum ResourceBundle {
    private static let packagedBundleName = "Quota_Quota.bundle"

    /// Preferred bundle for localized strings and resource files.
    static var resources: Bundle {
        if let packaged = packagedBundle {
            return packaged
        }
        // `swift run` / tests: SPM resource accessor.
        return .module
    }

    static var packagedBundle: Bundle? {
        guard let url = Bundle.main.resourceURL?.appendingPathComponent(packagedBundleName) else {
            return nil
        }
        return Bundle(url: url)
    }

    /// Looks up a resource URL safely for both packaged apps and local SPM runs.
    static func url(forResource name: String, withExtension ext: String) -> URL? {
        if let url = Bundle.main.url(forResource: name, withExtension: ext) {
            return url
        }
        if let url = packagedBundle?.url(forResource: name, withExtension: ext) {
            return url
        }
        // Only touch Bundle.module outside a real .app bundle.
        if Bundle.main.bundleURL.pathExtension.lowercased() == "app" {
            return nil
        }
        return Bundle.module.url(forResource: name, withExtension: ext)
    }

    static func path(forResource name: String, ofType ext: String) -> String? {
        url(forResource: name, withExtension: ext)?.path
    }
}
