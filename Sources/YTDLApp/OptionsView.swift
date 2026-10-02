import SwiftUI

struct OptionsView: View {
    var body: some View {
        TabView {
            FormatTab().tabItem { Text("Формат") }
            SubtitlesTab().tabItem { Text("Субтитры") }
            ProcessingTab().tabItem { Text("Обработка") }
            PlaylistTab().tabItem { Text("Плейлист") }
            SaveTab().tabItem { Text("Сохранение") }
        }
        .frame(minHeight: 250)
    }
}

private struct FormatTab: View {
    @Environment(AppState.self) private var state

    var body: some View {
        @Bindable var s = state
        Form {
            Picker("Что скачать", selection: $s.options.formatMode) {
                ForEach(FormatMode.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)

            switch state.options.formatMode {
            case .best:
                Text("Лучшее доступное видео и звук, склеенные в один файл.")
                    .foregroundStyle(.secondary)
            case .maxHeight:
                Picker("Не выше", selection: $s.options.maxHeight) {
                    ForEach([2160, 1440, 1080, 720, 480, 360], id: \.self) { Text("\($0)p").tag($0) }
                }
            case .audioOnly:
                Picker("Формат аудио", selection: $s.options.audioFormat) {
                    ForEach(AudioFormat.allCases) { Text($0.title).tag($0) }
                }
                Picker("Качество", selection: $s.options.audioQuality) {
                    Text("Лучшее").tag(0)
                    Text("Высокое").tag(2)
                    Text("Среднее").tag(5)
                    Text("Низкое").tag(9)
                }
                .disabled(state.options.audioFormat == .best)
            case .custom:
                if let info = state.currentInfo, !(info.formats ?? []).isEmpty {
                    Picker("Видео", selection: $s.customVideo) {
                        Text("— без видео —").tag("")
                        ForEach(info.videoFormats) { Text($0.label).tag($0.formatId) }
                    }
                    Picker("Аудио", selection: $s.customAudio) {
                        Text("— без аудио —").tag("")
                        ForEach(info.audioFormats) { Text($0.label).tag($0.formatId) }
                    }
                } else {
                    Text("Нажмите «Анализ», чтобы увидеть доступные форматы одного видео.")
                        .foregroundStyle(.secondary)
                }
            }

            if state.options.formatMode != .audioOnly {
                Picker("Контейнер", selection: $s.options.container) {
                    ForEach(Container.allCases) { Text($0.title).tag($0) }
                }
            }
        }
        .formStyle(.grouped)
    }
}

private struct SubtitlesTab: View {
    @Environment(AppState.self) private var state

    var body: some View {
        @Bindable var s = state
        let enabled = state.options.writeSubs || state.options.autoSubs
        Form {
            Toggle("Скачать субтитры автора", isOn: $s.options.writeSubs)
            Toggle("Скачать автоматические субтитры", isOn: $s.options.autoSubs)
            TextField("Языки", text: $s.options.subLangs, prompt: Text("ru,en  или  all"))
                .disabled(!enabled)
            Toggle("Встроить в видеофайл", isOn: $s.options.embedSubs)
                .disabled(!enabled || state.options.formatMode == .audioOnly)
            if let info = state.currentInfo, !info.isPlaylist {
                LabeledContent("Есть у видео") {
                    Text(info.subtitleLanguages.isEmpty ? "нет" : info.subtitleLanguages.joined(separator: ", "))
                        .textSelection(.enabled)
                }
                LabeledContent("Автоматические", value: info.autoCaptionCount > 0 ? "\(info.autoCaptionCount) языков" : "нет")
            }
        }
        .formStyle(.grouped)
    }
}

private struct ProcessingTab: View {
    @Environment(AppState.self) private var state

    var body: some View {
        @Bindable var s = state
        Form {
            Toggle("Встроить обложку", isOn: $s.options.embedThumbnail)
            Toggle("Записать метаданные (название, автор, дата)", isOn: $s.options.embedMetadata)
            Toggle("Добавить главы", isOn: $s.options.embedChapters)
            Toggle("Вырезать спонсорские вставки (SponsorBlock)", isOn: $s.options.sponsorBlock)
            Toggle("Скачать только фрагмент", isOn: $s.options.cutSection)
            if state.options.cutSection {
                HStack {
                    TextField("С", text: $s.options.sectionStart, prompt: Text("0:30"))
                    TextField("По", text: $s.options.sectionEnd, prompt: Text("1:45 (пусто — до конца)"))
                }
            }
        }
        .formStyle(.grouped)
    }
}

private struct PlaylistTab: View {
    @Environment(AppState.self) private var state

    var body: some View {
        @Bindable var s = state
        Form {
            Toggle("Только само видео, даже если ссылка из плейлиста", isOn: $s.options.noPlaylist)
            TextField("Какие элементы", text: $s.options.playlistItems, prompt: Text("например 1-5,8,10:  (пусто — все)"))
                .disabled(state.options.noPlaylist)
            Toggle("Пропускать уже скачанное (архив в папке загрузок)", isOn: $s.options.useArchive)
        }
        .formStyle(.grouped)
    }
}

private struct SaveTab: View {
    @Environment(AppState.self) private var state

    private let fields = [
        ("Название", "%(title)s"),
        ("ID", "%(id)s"),
        ("Автор", "%(uploader)s"),
        ("Дата загрузки", "%(upload_date>%Y-%m-%d)s"),
        ("Номер в плейлисте", "%(playlist_index)03d"),
        ("Название плейлиста", "%(playlist)s"),
        ("Разрешение", "%(resolution)s"),
    ]

    var body: some View {
        @Bindable var s = state
        Form {
            LabeledContent("Папка") {
                HStack {
                    Text((state.options.outputDir as NSString).abbreviatingWithTildeInPath)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Button("Выбрать…", action: chooseFolder)
                    Button {
                        NSWorkspace.shared.open(URL(fileURLWithPath: state.options.outputDir))
                    } label: {
                        Image(systemName: "folder")
                    }
                    .help("Открыть в Finder")
                }
            }
            HStack {
                TextField("Имя файла", text: $s.options.template)
                    .font(.system(.body, design: .monospaced))
                Menu("Поле") {
                    ForEach(fields, id: \.1) { name, token in
                        Button(name) { insert(token) }
                    }
                }
                .fixedSize()
                Button("Сброс") { state.options.template = DownloadOptions().template }
            }
            Picker("Cookies из браузера", selection: $s.options.browser) {
                ForEach(Browser.allCases) { Text($0.title).tag($0) }
            }
            .help("Для видео с возрастным ограничением, приватных и доступных по подписке")
            TextField("Ограничение скорости", text: $s.options.rateLimit, prompt: Text("например 2M (пусто — без ограничения)"))
            Stepper("Параллельных фрагментов: \(state.options.fragments)", value: $s.options.fragments, in: 1...16)
        }
        .formStyle(.grouped)
    }

    /// Вставляет поле перед расширением, чтобы шаблон оставался валидным.
    private func insert(_ token: String) {
        var t = state.options.template
        if let r = t.range(of: ".%(ext)s", options: .backwards) {
            t.insert(contentsOf: " " + token, at: r.lowerBound)
        } else {
            t += token
        }
        state.options.template = t
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.directoryURL = URL(fileURLWithPath: state.options.outputDir)
        if panel.runModal() == .OK, let url = panel.url {
            state.options.outputDir = url.path
        }
    }
}
