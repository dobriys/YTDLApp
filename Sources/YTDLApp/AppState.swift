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
    var presets: [Preset]
    var selectedPresetID: UUID?

    let executable = YTDLP.locate()
    let maxConcurrent = 2

    @ObservationIgnored private var analyzeToken = 0
    private static let optionsKey = "options"
    private static let presetsKey = "presets"
    private static let selectedPresetKey = "selectedPreset"

    private init() {
        let defaults = UserDefaults.standard
        if let data = defaults.data(forKey: Self.optionsKey),
           let saved = try? JSONDecoder().decode(DownloadOptions.self, from: data) {
            options = saved
        } else {
            options = DownloadOptions()
        }
        if let data = defaults.data(forKey: Self.presetsKey),
           let saved = try? JSONDecoder().decode([Preset].self, from: data) {
            presets = saved
            selectedPresetID = defaults.string(forKey: Self.selectedPresetKey).flatMap(UUID.init(uuidString:))
        } else {
            presets = Preset.builtIn
            let current = options
            selectedPresetID = presets.first { current == current.applying($0.options) }?.id
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

    // MARK: Пресеты

    var selectedPreset: Preset? {
        presets.first { $0.id == selectedPresetID }
    }

    var isPresetModified: Bool {
        guard let preset = selectedPreset else { return false }
        return options != options.applying(preset.options)
    }

    func applyPreset(_ preset: Preset) {
        selectedPresetID = preset.id
        options = options.applying(preset.options)
        savePresets()
    }

    func updateSelectedPreset() {
        guard let i = presets.firstIndex(where: { $0.id == selectedPresetID }) else { return }
        presets[i].options = options
        savePresets()
    }

    func saveAsNewPreset(named name: String) {
        let preset = Preset(name: name, options: options)
        presets.append(preset)
        selectedPresetID = preset.id
        savePresets()
    }

    func renameSelectedPreset(to name: String) {
        guard let i = presets.firstIndex(where: { $0.id == selectedPresetID }) else { return }
        presets[i].name = name
        savePresets()
    }

    func deleteSelectedPreset() {
        presets.removeAll { $0.id == selectedPresetID }
        selectedPresetID = nil
        savePresets()
    }

    /// Возвращает встроенные пресеты к исходному виду, свои пресеты не трогает.
    func restoreBuiltInPresets() {
        let builtInIDs = Set(Preset.builtIn.map(\.id))
        presets = Preset.builtIn + presets.filter { !builtInIDs.contains($0.id) }
        savePresets()
    }

    private func savePresets() {
        let defaults = UserDefaults.standard
        if let data = try? JSONEncoder().encode(presets) {
            defaults.set(data, forKey: Self.presetsKey)
        }
        defaults.set(selectedPresetID?.uuidString, forKey: Self.selectedPresetKey)
    }

    // MARK: Ссылки и загрузка

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
