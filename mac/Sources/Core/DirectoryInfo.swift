import Foundation

enum DirectoryInfo {
    static func branch(at directory: URL) -> String? {
        var current = directory.resolvingSymlinksInPath().standardizedFileURL
        while true {
            let marker = current.appendingPathComponent(".git")
            var isDirectory: ObjCBool = false
            if FileManager.default.fileExists(atPath: marker.path, isDirectory: &isDirectory) {
                let gitDirectory: URL
                if isDirectory.boolValue {
                    gitDirectory = marker
                } else {
                    guard let content = try? String(contentsOf: marker, encoding: .utf8),
                        content.hasPrefix("gitdir:")
                    else { return nil }
                    let path = String(content.dropFirst(7)).trimmingCharacters(in: .whitespacesAndNewlines)
                    gitDirectory = URL(fileURLWithPath: path, relativeTo: current)
                }
                guard let content = try? String(contentsOf: gitDirectory.appendingPathComponent("HEAD"), encoding: .utf8)
                else { return nil }
                let head = content.trimmingCharacters(in: .whitespacesAndNewlines)
                if head.hasPrefix("ref: refs/heads/") {
                    return String(head.dropFirst(16))
                }
                return head.isEmpty ? nil : "分离状态 · \(head.prefix(7))"
            }
            let parent = current.deletingLastPathComponent()
            if parent.path == current.path { return nil }
            current = parent
        }
    }
}
