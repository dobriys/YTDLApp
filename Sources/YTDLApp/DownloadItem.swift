import Foundation
import Observation

@Observable
final class DownloadItem: Identifiable {
    enum Status { case waiting, downloading, processing, done, failed, cancelled }

    let id = UUID()
    let arguments: [String]
    let outputDir: String
    var title: String
    var status: Status = .waiting
    var progress = 0.0
    var speed = ""
    var eta = ""
    var position = ""
    var stage = ""
    var errorMessage: String?
    var files: [String] = []
    var log: [String] = []

    @ObservationIgnored var onFinish: (() -> Void)?
    @ObservationIgnored private var process: Process?
    @ObservationIgnored private var cancelled = false

    init(title: String, arguments: [String], outputDir: String) {
        self.title = title
        self.arguments = arguments
        self.outputDir = outputDir
    }

    var isActive: Bool { status == .downloading || status == .processing }
    var isFinished: Bool { status == .done || status == .failed || status == .cancelled }

    var statusLine: String {
        switch status {
        case .waiting:
            return "В очереди"
        case .downloading:
            var parts = [String(format: "%.1f%%", progress * 100)]
            if !speed.isEmpty { parts.append(speed) }
            if !eta.isEmpty { parts.append("осталось \(eta)") }
            if !position.isEmpty { parts.append("элемент \(position)") }
            return parts.joined(separator: " · ")
        case .processing:
            return stage.isEmpty ? "Обработка…" : stage + "…"
        case .done:
            if files.count > 1 { return "Готово · файлов: \(files.count)" }
            if let f = files.first { return "Готово · " + (f as NSString).lastPathComponent }
            return "Готово (новых файлов нет)"
        case .failed:
            return errorMessage ?? "Ошибка"
        case .cancelled:
            return "Отменено"
        }
    }

    func start(executable: URL) {
        cancelled = false
        status = .downloading
        progress = 0
        speed = ""; eta = ""; position = ""; stage = ""
        errorMessage = nil
        files = []
        log = []

        let p = Process()
        p.executableURL = executable
        p.arguments = YTDLP.runtimeArguments + arguments
        p.environment = YTDLP.environment
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = pipe
        p.standardInput = FileHandle.nullDevice

        // Завершаемся только когда и процесс вышел, и весь вывод прочитан.
        let group = DispatchGroup()
        group.enter(); group.enter()
        var exitCode: Int32 = 0

        let splitter = LineSplitter { [weak self] line in
            DispatchQueue.main.async { self?.handle(line) }
        }
        pipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            if data.isEmpty {
                handle.readabilityHandler = nil
                splitter.flush()
                group.leave()
            } else {
                splitter.feed(data)
            }
        }
        p.terminationHandler = { proc in
            exitCode = proc.terminationStatus
            group.leave()
        }
        group.notify(queue: .main) { [weak self] in self?.finish(code: exitCode) }

        do {
            try p.run()
            process = p
        } catch {
            pipe.fileHandleForReading.readabilityHandler = nil
            status = .failed
            errorMessage = error.localizedDescription
            onFinish?()
        }
    }

    func cancel() {
        cancelled = true
        guard let p = process, p.isRunning else {
            if status == .waiting { status = .cancelled }
            return
        }
        // Сначала дочерние процессы (ffmpeg), иначе они держат вывод открытым.
        let pkill = Process()
        pkill.executableURL = URL(fileURLWithPath: "/usr/bin/pkill")
        pkill.arguments = ["-TERM", "-P", "\(p.processIdentifier)"]
        try? pkill.run()
        pkill.waitUntilExit()
        p.terminate()
    }

    private func finish(code: Int32) {
        process = nil
        speed = ""; eta = ""; stage = ""
        if cancelled {
            status = .cancelled
        } else if code == 0 {
            status = .done
            progress = 1
        } else {
            status = .failed
            if errorMessage == nil { errorMessage = "yt-dlp завершился с кодом \(code)" }
        }
        onFinish?()
    }

    private static let stages: [String: String] = [
        "Merger": "Склейка видео и звука",
        "ExtractAudio": "Извлечение аудио",
        "EmbedThumbnail": "Встраивание обложки",
        "ThumbnailsConvertor": "Подготовка обложки",
        "Metadata": "Запись метаданных",
        "EmbedSubtitle": "Встраивание субтитров",
        "SubtitlesConvertor": "Конвертация субтитров",
        "SponsorBlock": "Поиск спонсорских вставок",
        "ModifyChapters": "Вырезание фрагментов",
        "VideoRemuxer": "Перепаковка",
        "VideoConvertor": "Конвертация",
    ]

    private func handle(_ line: String) {
        if line.hasPrefix(YTDLP.progressMarker) {
            let parts = line.dropFirst(YTDLP.progressMarker.count)
                .split(separator: "|", omittingEmptySubsequences: false)
                .map { $0.trimmingCharacters(in: .whitespaces) }
            guard parts.count >= 6 else { return }
            func value(_ s: String) -> String { s == "NA" || s.hasPrefix("Unknown") ? "" : s }
            if let pct = Double(parts[0].replacingOccurrences(of: "%", with: "")) { progress = pct / 100 }
            speed = value(parts[1])
            eta = value(parts[2])
            let (index, total) = (value(parts[3]), value(parts[4]))
            position = index.isEmpty ? "" : (total.isEmpty ? index : "\(index) из \(total)")
            let t = parts[5...].joined(separator: "|")
            if !value(t).isEmpty { title = t }
            status = .downloading
            stage = ""
            return
        }

        log.append(line)
        if log.count > 3000 { log.removeFirst(log.count - 3000) }

        if line.hasPrefix(YTDLP.fileMarker) {
            files.append(String(line.dropFirst(YTDLP.fileMarker.count)))
        } else if line.hasPrefix("ERROR:") {
            errorMessage = line.dropFirst(6).trimmingCharacters(in: .whitespaces)
        } else if line.hasPrefix("["), let close = line.firstIndex(of: "]") {
            let tag = String(line[line.index(after: line.startIndex)..<close])
            if let name = Self.stages[tag] ?? (tag.hasPrefix("Fixup") ? "Исправление файла" : nil) {
                status = .processing
                stage = name
            }
        }
    }
}
