import SwiftUI

struct ContentView: View {
    @Environment(AppState.self) private var state

    var body: some View {
        VSplitView {
            VStack(alignment: .leading, spacing: 12) {
                if state.executable == nil {
                    Label("yt-dlp не найден. Установите его командой: brew install yt-dlp ffmpeg",
                          systemImage: "exclamationmark.octagon.fill")
                        .foregroundStyle(.red)
                }
                URLBar()
                InfoPanel()
                PresetBar()
                OptionsView()
                CommandPreview()
            }
            .padding()
            .frame(minHeight: 500)

            QueueView()
                .frame(minHeight: 170)
        }
        .onChange(of: state.options) { state.saveOptions() }
    }
}

struct URLBar: View {
    @Environment(AppState.self) private var state

    var body: some View {
        @Bindable var s = state
        HStack {
            TextField("Ссылка на видео, плейлист или канал (можно несколько через пробел)", text: $s.urlText)
                .textFieldStyle(.roundedBorder)
                .onSubmit { state.analyze() }
            Button {
                state.pasteAndAnalyze()
            } label: {
                Label("Вставить", systemImage: "doc.on.clipboard")
            }
            .help("Вставить ссылку из буфера обмена и проанализировать")
            Button("Анализ") { state.analyze() }
                .disabled(state.urls.isEmpty || state.isAnalyzing || state.executable == nil)
            Button {
                state.enqueue()
            } label: {
                Label("Скачать", systemImage: "arrow.down.circle.fill")
            }
            .buttonStyle(.borderedProminent)
            .keyboardShortcut(.return, modifiers: .command)
            .disabled(state.urls.isEmpty || state.executable == nil)
            .help("Скачать (⌘↩)")
        }
    }
}

struct InfoPanel: View {
    @Environment(AppState.self) private var state

    var body: some View {
        if state.isAnalyzing {
            HStack {
                ProgressView().controlSize(.small)
                Text("Получаю информацию…").foregroundStyle(.secondary)
            }
            .frame(height: 90)
        } else if let error = state.analyzeError {
            Label(error, systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.red)
                .textSelection(.enabled)
                .lineLimit(4)
        } else if let info = state.currentInfo {
            HStack(alignment: .top, spacing: 12) {
                AsyncImage(url: info.thumbnailURL) { image in
                    image.resizable().aspectRatio(contentMode: .fill)
                } placeholder: {
                    Color.secondary.opacity(0.15)
                }
                .frame(width: 160, height: 90)
                .clipShape(RoundedRectangle(cornerRadius: 6))

                VStack(alignment: .leading, spacing: 4) {
                    Text(info.title ?? "Без названия")
                        .font(.headline)
                        .lineLimit(2)
                        .textSelection(.enabled)
                    if let author = info.uploader ?? info.channel {
                        Text(author).foregroundStyle(.secondary)
                    }
                    HStack(spacing: 12) {
                        if info.isPlaylist { Label("Плейлист · \(info.itemCount) шт.", systemImage: "list.bullet") }
                        if let d = info.durationText { Label(d, systemImage: "clock") }
                        if let n = info.formats?.count, n > 0 { Label("Форматов: \(n)", systemImage: "film") }
                        if let site = info.extractorKey { Label(site, systemImage: "globe") }
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
                Spacer()
            }
        }
    }
}

struct CommandPreview: View {
    @Environment(AppState.self) private var state

    var body: some View {
        let command = state.commandPreview
        HStack(alignment: .top) {
            Text(command)
                .font(.system(.caption, design: .monospaced))
                .textSelection(.enabled)
                .lineLimit(3)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(command, forType: .string)
            } label: {
                Image(systemName: "doc.on.doc")
            }
            .buttonStyle(.borderless)
            .help("Скопировать команду для терминала")
        }
        .padding(8)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 6))
    }
}
