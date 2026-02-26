import Foundation

// MARK: - FirebaseConfig
// Reads Firebase project settings from GoogleService-Info.plist at runtime.
// On iOS the Firebase SDK reads this automatically.
// On macOS (swift build) we parse it manually here.
//
// ⚠️  Place GoogleService-Info.plist in the project root before building.

enum FirebaseConfig {

    // Parsed lazily from GoogleService-Info.plist the first time they are accessed.
    // On macOS, prefer MAC_API_KEY if present (unrestricted key for REST API calls),
    // falling back to API_KEY.
    #if os(macOS)
    static let apiKey: String   = value(for: "MAC_API_KEY") ?? value(for: "API_KEY") ?? ""
    #else
    static let apiKey: String   = value(for: "API_KEY")   ?? ""
    #endif
    static let projectId: String = value(for: "PROJECT_ID") ?? ""

    private static func value(for key: String) -> String? {
        // 1. Bundle resource (Xcode target / .app bundle)
        if let url = Bundle.main.url(forResource: "GoogleService-Info", withExtension: "plist"),
           let dict = NSDictionary(contentsOf: url) as? [String: Any],
           let val = dict[key] as? String {
            print("✅ FirebaseConfig: '\(key)' loaded from bundle: \(url.path)")
            return val
        }

        // 2. Beside the executable (swift build / run.sh)
        let execPath = Bundle.main.executablePath ?? ""
        let candidates = [
            // Inside .app/Contents/Resources/
            URL(fileURLWithPath: execPath)
                .deletingLastPathComponent()       // MacOS/
                .deletingLastPathComponent()       // Contents/
                .appendingPathComponent("Resources/GoogleService-Info.plist")
                .path,
            // next to the binary
            Bundle.main.bundlePath + "/GoogleService-Info.plist",
            // project root when run via run.sh from the project directory
            FileManager.default.currentDirectoryPath + "/GoogleService-Info.plist",
            // two levels up from .build/arm64-.../debug/
            URL(fileURLWithPath: execPath)
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .appendingPathComponent("GoogleService-Info.plist")
                .path
        ]
        for path in candidates {
            if let dict = NSDictionary(contentsOfFile: path) as? [String: Any],
               let val = dict[key] as? String {
                print("✅ FirebaseConfig: '\(key)' loaded from: \(path)")
                return val
            }
        }

        print("⚠️  FirebaseConfig: '\(key)' not found in GoogleService-Info.plist")
        print("⚠️  Searched: Bundle.main.bundlePath=\(Bundle.main.bundlePath)")
        print("⚠️  Searched: cwd=\(FileManager.default.currentDirectoryPath)")
        print("⚠️  Searched: executablePath=\(execPath)")
        return nil
    }
}

