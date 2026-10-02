import Foundation

// MARK: - Ответ `yt-dlp -J`

struct MediaFormat: Decodable, Identifiable, Hashable {
    let formatId: String
    let ext: String?
    let height: Int?
    let fps: Double?
    let vcodec: String?
    let acodec: String?
    let abr: Double?
    let filesize: Double?
    let filesizeApprox: Double?
    let formatNote: String?
    let resolution: String?

    var id: String { formatId }
    var hasVideo: Bool { vcodec.map { $0 != "none" } ?? (height != nil) }
    var hasAudio: Bool { acodec.map { $0 != "none" } ?? (height == nil) }
    var size: Double? { filesize ?? filesizeApprox }

    var label: String {
        var parts: [String] = []
        if hasVideo {
            parts.append(height.map { "\($0)p" } ?? resolution ?? "видео")
            if let fps, fps > 30 { parts.append("\(Int(fps)) fps") }
        } else if let abr {
            parts.append("\(Int(abr)) кбит/с")
        }
        if let ext { parts.append(ext) }
        if let codec = (hasVideo ? vcodec : acodec)?.split(separator: ".").first {
            parts.append(String(codec))
        }
        if hasVideo && hasAudio { parts.append("со звуком") }
        if !hasVideo, let note = formatNote, !note.isEmpty { parts.append(note) }
        if let size { parts.append(ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .file)) }
        return "\(formatId) — " + parts.joined(separator: " · ")
    }
}

struct MediaInfo: Decodable {
    struct Thumbnail: Decodable { let url: String? }
    struct Entry: Decodable { let title: String? }
    struct Track: Decodable { let ext: String? }

    let _type: String?
    let id: String?
    let title: String?
    let uploader: String?
    let channel: String?
    let duration: Double?
    let thumbnail: String?
    let thumbnails: [Thumbnail]?
    let extractorKey: String?
    let formats: [MediaFormat]?
    let entries: [Entry]?
    let playlistCount: Int?
    let subtitles: [String: [Track]]?
    let automaticCaptions: [String: [Track]]?

    var isPlaylist: Bool { _type == "playlist" || entries != nil }
    var itemCount: Int { playlistCount ?? entries?.count ?? 0 }

    var thumbnailURL: URL? {
        (thumbnail ?? thumbnails?.last?.url).flatMap(URL.init(string:))
    }

    private var usableFormats: [MediaFormat] {
        (formats ?? []).filter { $0.ext != "mhtml" }
    }
    /// В порядке от лучшего к худшему (yt-dlp сортирует наоборот).
    var videoFormats: [MediaFormat] { usableFormats.filter(\.hasVideo).reversed() }
    var audioFormats: [MediaFormat] { usableFormats.filter { $0.hasAudio && !$0.hasVideo }.reversed() }

    var subtitleLanguages: [String] { (subtitles ?? [:]).keys.filter { $0 != "live_chat" }.sorted() }
    var autoCaptionCount: Int { automaticCaptions?.count ?? 0 }

    var durationText: String? {
        guard let duration, duration > 0 else { return nil }
        let s = Int(duration)
        return s >= 3600
            ? String(format: "%d:%02d:%02d", s / 3600, s / 60 % 60, s % 60)
            : String(format: "%d:%02d", s / 60, s % 60)
    }
}

// MARK: - Настройки загрузки

enum FormatMode: String, Codable, CaseIterable, Identifiable {
    case best, maxHeight, audioOnly, custom
    var id: Self { self }
    var title: String {
        switch self {
        case .best: "Лучшее"
        case .maxHeight: "Ограничить качество"
        case .audioOnly: "Только аудио"
        case .custom: "Выбрать формат"
        }
    }
}

enum Container: String, Codable, CaseIterable, Identifiable {
    case auto, mp4, mkv, webm
    var id: Self { self }
    var title: String { self == .auto ? "Как есть" : rawValue }
}

enum AudioFormat: String, Codable, CaseIterable, Identifiable {
    case best, mp3, m4a, opus, flac, wav
    var id: Self { self }
    var title: String { self == .best ? "Без конвертации" : rawValue }
}

enum Browser: String, Codable, CaseIterable, Identifiable {
    case none, safari, chrome, firefox, edge, brave, opera, vivaldi, chromium
    var id: Self { self }
    var title: String {
        switch self {
        case .none: "Не использовать"
        case .safari: "Safari"
        case .chrome: "Chrome"
        case .firefox: "Firefox"
        case .edge: "Edge"
        case .brave: "Brave"
        case .opera: "Opera"
        case .vivaldi: "Vivaldi"
        case .chromium: "Chromium"
        }
    }
}

struct DownloadOptions: Codable, Equatable {
    var formatMode: FormatMode = .best
    var maxHeight = 1080
    var container: Container = .mp4
    var audioFormat: AudioFormat = .mp3
    var audioQuality = 0

    var writeSubs = false
    var autoSubs = false
    var subLangs = "ru,en"
    var embedSubs = true

    var embedThumbnail = true
    var embedMetadata = true
    var embedChapters = true
    var sponsorBlock = false
    var cutSection = false
    var sectionStart = ""
    var sectionEnd = ""

    var noPlaylist = false
    var playlistItems = ""
    var useArchive = false

    var outputDir = NSHomeDirectory() + "/Downloads"
    var template = "%(title)s [%(id)s].%(ext)s"
    var browser: Browser = .none
    var rateLimit = ""
    var fragments = 1
}

extension DownloadOptions {
    /// Настройки пресета поверх текущих. Папка общая для всех пресетов, а элементы
    /// плейлиста и фрагмент относятся к конкретной ссылке — они остаются как были.
    func applying(_ preset: DownloadOptions) -> DownloadOptions {
        var result = preset
        result.outputDir = outputDir
        result.playlistItems = playlistItems
        result.cutSection = cutSection
        result.sectionStart = sectionStart
        result.sectionEnd = sectionEnd
        return result
    }
}

// MARK: - Пресеты

struct Preset: Codable, Identifiable, Equatable {
    var id = UUID()
    var name: String
    var options: DownloadOptions

    static let builtIn: [Preset] = {
        func make(_ n: Int, _ name: String, _ configure: (inout DownloadOptions) -> Void) -> Preset {
            var o = DownloadOptions()
            configure(&o)
            return Preset(id: UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", n))!, name: name, options: o)
        }
        return [
            make(1, "Лучшее видео") { _ in },
            make(2, "1080p с субтитрами") {
                $0.formatMode = .maxHeight
                $0.maxHeight = 1080
                $0.writeSubs = true
                $0.subLangs = "ru,en"
                $0.embedSubs = true
            },
            make(3, "Музыка mp3") {
                $0.formatMode = .audioOnly
                $0.audioFormat = .mp3
                $0.audioQuality = 0
                $0.embedChapters = false
                $0.template = "%(uploader)s — %(title)s.%(ext)s"
            },
            make(4, "Подкаст / лекция") {
                $0.formatMode = .audioOnly
                $0.audioFormat = .m4a
                $0.audioQuality = 2
                $0.sponsorBlock = true
            },
            make(5, "Архив канала") {
                $0.useArchive = true
                $0.template = "%(playlist,uploader)s/%(playlist_index&{:03d} - |)s%(title)s.%(ext)s"
            },
            make(6, "Экономно (720p)") {
                $0.formatMode = .maxHeight
                $0.maxHeight = 720
            },
        ]
    }()
}
