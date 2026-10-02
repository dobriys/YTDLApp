import AppKit
import Observation

@MainActor
@Observable
final class AppState {
    static let shared = AppState()

    var urlText = ""
    var options: DownloadOptions
    var info: MediaInfo?
    var infoURL: String?
    var customVideo = ""
    var customAudio = ""
    var isAnalyzing = false
    var analyzeError: String?
    var queue: [DownloadItem] = []
    var version = ""

    let executable = YTDLP.locate()
    let maxConcurrent = 2

    @ObservationIgnored private var analyzeToken = 0
    private static let optionsKey = "options"

    private init() {
        if let data = UserDefaults.standard.data(forKey: Self.optionsKey),
           let saved = try? JSONDecoder().decode(DownloadOptions.self, from: data) {
            options = saved
        } else {
            options = DownloadOptions()
        }
        if let exe = executable {
            Task {
                if let r = try? await YTDLP.capture(exe, ["--version"]) {
                    version = String(decoding: r.out, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
                }
            }
        }
    }

    func saveOptions() {
        if let data = try? JSONEncoder().encode(options) {
            UserDefaults.standard.set(data, forKey: Self.optionsKey)
        }
    }

    var urls: [String] {
        urlText.split(whereSeparator: \.isWhitespace).map(String.init)
    }

    /// Информация актуальна, только если анализировали ровно ту ссылку, что сейчас в поле.
    var currentInfo: MediaInfo? {
        urls == [infoURL] ? info : nil
    }

    private var customSelection: (video: String, audio: String)? {
        currentInfo == nil ? nil : (customVideo, customAudio)
    }

    var commandPreview: String {
        let shown = urls.isEmpty ? ["<ссылка>"] : urls
        return YTDLP.commandLine(YTDLP.arguments(options, urls: shown, custom: customSelection))
    }

    func pasteAndAnalyze() {
        guard let text = NSPasteboard.general.string(forType: .string)?
            .trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else { return }
        urlText = text
        analyze()
    }

    func analyze() {
        guard let exe = executable, let url = urls.first else { return }
        analyzeToken += 1
        let token = analyzeToken
        isAnalyzing = true
        analyzeError = nil

        let args = ["-J", "--flat-playlist", "--no-warnings"] + YTDLP.cookieArguments(options) + ["--", url]
        Task {
            defer { if token == analyzeToken { isAnalyzing = false } }
            do {
                let result = try await YTDLP.capture(exe, args)
                guard token == analyzeToken else { return }
                guard result.status == 0 else {
                    analyzeError = YTDLP.errorText(from: result.err)
                    return
                }
                let decoder = JSONDecoder()
                decoder.keyDecodingStrategy = .convertFromSnakeCase
                let decoded = try decoder.decode(MediaInfo.self, from: result.out)
                info = decoded
                infoURL = url
                customVideo = decoded.videoFormats.first?.formatId ?? ""
                customAudio = decoded.audioFormats.first?.formatId ?? ""
            } catch {
                if token == analyzeToken { analyzeError = error.localizedDescription }
            }
        }
    }

    func enqueue() {
        let list = urls
        guard !list.isEmpty else { return }
        let custom = customSelection
        for url in list {
            let title = (list.count == 1 ? currentInfo?.title : nil) ?? url
            let args = YTDLP.arguments(options, urls: [url], custom: custom)
            let item = DownloadItem(title: title, arguments: args, outputDir: options.outputDir)
            item.onFinish = { [weak self] in self?.pump() }
            queue.append(item)
        }
        pump()
    }

    func pump() {
        guard let exe = executable else { return }
        var running = queue.filter(\.isActive).count
        for item in queue where item.status == .waiting && running < maxConcurrent {
            item.start(executable: exe)
            running += 1
        }
    }

    func retry(_ item: DownloadItem) {
        item.status = .waiting
        pump()
    }

    func remove(_ item: DownloadItem) {
        item.cancel()
        queue.removeAll { $0.id == item.id }
    }

    func clearFinished() {
        queue.removeAll(where: \.isFinished)
    }

    func cancelAll() {
        queue.forEach { $0.cancel() }
    }
}
