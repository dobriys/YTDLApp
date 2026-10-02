import Foundation

/// Всё, что касается запуска внешнего yt-dlp.
enum YTDLP {
    static let fileMarker = "@@FILE@@"
    static let progressMarker = "[PROG]"

    static func locate() -> URL? {
        ["/opt/homebrew/bin/yt-dlp", "/usr/local/bin/yt-dlp", NSHomeDirectory() + "/.local/bin/yt-dlp"]
            .first { FileManager.default.isExecutableFile(atPath: $0) }
            .map(URL.init(fileURLWithPath:))
    }

    /// Приложения из Finder не видят Homebrew в PATH — без этого yt-dlp не найдёт ffmpeg и deno.
    static var environment: [String: String] {
        var env = ProcessInfo.processInfo.environment
        env["PATH"] = "/opt/homebrew/bin:/usr/local/bin:" + (env["PATH"] ?? "/usr/bin:/bin")
        env["PYTHONUNBUFFERED"] = "1"
        env["PYTHONIOENCODING"] = "utf-8"
        return env
    }

    /// Служебные аргументы, нужные приложению для разбора вывода. В предпросмотр команды не попадают.
    static let runtimeArguments = [
        "--newline", "--progress",
        "--progress-template",
        "download:\(progressMarker)%(progress._percent_str)s|%(progress._speed_str)s|%(progress._eta_str)s|%(info.playlist_index)s|%(info.n_entries)s|%(info.title)s",
        "--exec", "printf '%s\\n' \(fileMarker)%(filepath)q",
    ]

    static func cookieArguments(_ o: DownloadOptions) -> [String] {
        o.browser == .none ? [] : ["--cookies-from-browser", o.browser.rawValue]
    }

    /// Аргументы, соответствующие настройкам. `custom` — выбранные вручную форматы (видео, аудио).
    static func arguments(_ o: DownloadOptions, urls: [String], custom: (video: String, audio: String)?) -> [String] {
        var a: [String] = []
        let preferMP4 = o.container == .mp4 ? ["-S", "res,ext:mp4:m4a"] : []

        switch o.formatMode {
        case .best:
            a += ["-f", "bv*+ba/b"] + preferMP4
        case .maxHeight:
            let h = o.maxHeight
            a += ["-f", "bv*[height<=\(h)]+ba/b[height<=\(h)]/b"] + preferMP4
        case .audioOnly:
            a += ["-f", "ba/b", "-x", "--audio-format", o.audioFormat.rawValue]
            if o.audioFormat != .best { a += ["--audio-quality", "\(o.audioQuality)"] }
        case .custom:
            let ids = [custom?.video, custom?.audio].compactMap { $0 }.filter { !$0.isEmpty }
            a += ["-f", ids.isEmpty ? "bv*+ba/b" : ids.joined(separator: "+")]
        }
        if o.formatMode != .audioOnly, o.container != .auto {
            a += ["--merge-output-format", o.container.rawValue]
        }

        if o.writeSubs || o.autoSubs {
            if o.writeSubs { a.append("--write-subs") }
            if o.autoSubs { a.append("--write-auto-subs") }
            let langs = o.subLangs.trimmingCharacters(in: .whitespaces)
            a += ["--sub-langs", langs.isEmpty ? "all" : langs]
            if o.embedSubs, o.formatMode != .audioOnly { a.append("--embed-subs") }
        }

        if o.embedThumbnail { a.append("--embed-thumbnail") }
        if o.embedMetadata { a.append("--embed-metadata") }
        if o.embedChapters { a.append("--embed-chapters") }
        if o.sponsorBlock { a += ["--sponsorblock-remove", "sponsor"] }
        if o.cutSection {
            let start = o.sectionStart.trimmingCharacters(in: .whitespaces)
            let end = o.sectionEnd.trimmingCharacters(in: .whitespaces)
            a += ["--download-sections", "*\(start.isEmpty ? "0" : start)-\(end.isEmpty ? "inf" : end)"]
        }

        if o.noPlaylist {
            a.append("--no-playlist")
        } else if !o.playlistItems.trimmingCharacters(in: .whitespaces).isEmpty {
            a += ["-I", o.playlistItems.trimmingCharacters(in: .whitespaces)]
        }
        if o.useArchive { a += ["--download-archive", o.outputDir + "/.yt-dlp-archive.txt"] }

        a += cookieArguments(o)
        if !o.rateLimit.trimmingCharacters(in: .whitespaces).isEmpty {
            a += ["-r", o.rateLimit.trimmingCharacters(in: .whitespaces)]
        }
        if o.fragments > 1 { a += ["-N", "\(o.fragments)"] }

        a += ["-P", o.outputDir, "-o", o.template.isEmpty ? "%(title)s.%(ext)s" : o.template]
        a.append("--")
        a += urls
        return a
    }

    static func commandLine(_ args: [String]) -> String {
        (["yt-dlp"] + args.map(shellQuote)).joined(separator: " ")
    }

    static func shellQuote(_ s: String) -> String {
        if s.range(of: #"^[A-Za-z0-9_@%+=:,./-]+$"#, options: .regularExpression) != nil { return s }
        return "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    /// Запускает yt-dlp и собирает stdout/stderr целиком.
    static func capture(_ executable: URL, _ args: [String]) async throws -> (status: Int32, out: Data, err: Data) {
        try await withCheckedThrowingContinuation { cont in
            DispatchQueue.global().async {
                let p = Process()
                p.executableURL = executable
                p.arguments = args
                p.environment = environment
                let outPipe = Pipe(), errPipe = Pipe()
                p.standardOutput = outPipe
                p.standardError = errPipe
                p.standardInput = FileHandle.nullDevice
                do { try p.run() } catch { cont.resume(throwing: error); return }

                var err = Data()
                let group = DispatchGroup()
                group.enter()
                DispatchQueue.global().async {
                    err = errPipe.fileHandleForReading.readDataToEndOfFile()
                    group.leave()
                }
                let out = outPipe.fileHandleForReading.readDataToEndOfFile()
                group.wait()
                p.waitUntilExit()
                cont.resume(returning: (p.terminationStatus, out, err))
            }
        }
    }

    static func errorText(from stderr: Data) -> String {
        let lines = String(decoding: stderr, as: UTF8.self).split(separator: "\n").map(String.init)
        let errors = lines.filter { $0.hasPrefix("ERROR:") }.map { $0.dropFirst(6).trimmingCharacters(in: .whitespaces) }
        return errors.last ?? lines.last ?? "Неизвестная ошибка"
    }
}

/// Режет поток байтов на строки (yt-dlp пишет и \n, и \r).
final class LineSplitter {
    private var buffer = Data()
    private let onLine: (String) -> Void

    init(onLine: @escaping (String) -> Void) { self.onLine = onLine }

    func feed(_ data: Data) {
        buffer.append(data)
        while let i = buffer.firstIndex(where: { $0 == 10 || $0 == 13 }) {
            let line = buffer[buffer.startIndex..<i]
            buffer.removeSubrange(buffer.startIndex...i)
            if !line.isEmpty { onLine(String(decoding: line, as: UTF8.self)) }
        }
    }

    func flush() {
        if !buffer.isEmpty { onLine(String(decoding: buffer, as: UTF8.self)) }
        buffer.removeAll()
    }
}
