import SwiftUI

struct QueueView: View {
    @Environment(AppState.self) private var state

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Загрузки").font(.headline)
                Spacer()
                if !state.version.isEmpty {
                    Text("yt-dlp \(state.version)").font(.caption).foregroundStyle(.secondary)
                }
                Button("Очистить завершённые") { state.clearFinished() }
                    .disabled(!state.queue.contains(where: \.isFinished))
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
            Divider()

            if state.queue.isEmpty {
                ContentUnavailableView("Очередь пуста", systemImage: "tray",
                                       description: Text("Вставьте ссылку и нажмите «Скачать»"))
            } else {
                List {
                    ForEach(state.queue) { DownloadRow(item: $0) }
                }
            }
        }
    }
}

private struct DownloadRow: View {
    @Environment(AppState.self) private var state
    let item: DownloadItem
    @State private var showLog = false

    var body: some View {
        HStack(spacing: 10) {
            statusIcon.font(.title2).frame(width: 28)

            VStack(alignment: .leading, spacing: 4) {
                Text(item.title)
                    .lineLimit(1)
                    .truncationMode(.middle)
                switch item.status {
                case .downloading: ProgressView(value: item.progress)
                case .processing: ProgressView().progressViewStyle(.linear)
                default: EmptyView()
                }
                Text(item.statusLine)
                    .font(.caption)
                    .foregroundStyle(item.status == .failed ? .red : .secondary)
                    .lineLimit(2)
                    .textSelection(.enabled)
            }

            Spacer()

            if item.isActive || item.status == .waiting {
                iconButton("xmark.circle", "Остановить") { item.cancel() }
            }
            if item.status == .failed || item.status == .cancelled {
                iconButton("arrow.clockwise", "Повторить") { state.retry(item) }
            }
            if item.status == .done {
                iconButton("magnifyingglass", "Показать в Finder", action: reveal)
            }
            iconButton("doc.text", "Журнал yt-dlp") { showLog = true }
                .popover(isPresented: $showLog) { LogView(item: item) }
            if !item.isActive {
                iconButton("trash", "Убрать из списка") { state.remove(item) }
            }
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .onTapGesture(count: 2) {
            if item.files.count == 1, let f = item.files.first {
                NSWorkspace.shared.open(URL(fileURLWithPath: f))
            } else {
                reveal()
            }
        }
    }

    @ViewBuilder private var statusIcon: some View {
        switch item.status {
        case .waiting: Image(systemName: "clock").foregroundStyle(.secondary)
        case .downloading: Image(systemName: "arrow.down.circle").foregroundStyle(.blue)
        case .processing: Image(systemName: "gearshape.2").foregroundStyle(.orange)
        case .done: Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
        case .failed: Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.red)
        case .cancelled: Image(systemName: "stop.circle").foregroundStyle(.secondary)
        }
    }

    private func iconButton(_ symbol: String, _ help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) { Image(systemName: symbol) }
            .buttonStyle(.borderless)
            .help(help)
    }

    private func reveal() {
        let urls = item.files.map { URL(fileURLWithPath: $0) }
            .filter { FileManager.default.fileExists(atPath: $0.path) }
        if urls.isEmpty {
            NSWorkspace.shared.open(URL(fileURLWithPath: item.outputDir))
        } else {
            NSWorkspace.shared.activateFileViewerSelecting(urls)
        }
    }
}

private struct LogView: View {
    let item: DownloadItem

    var body: some View {
        VStack(alignment: .leading) {
            HStack {
                Text("Журнал").font(.headline)
                Spacer()
                Button("Скопировать") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(fullText, forType: .string)
                }
            }
            ScrollView {
                Text(fullText.isEmpty ? "Пока пусто" : fullText)
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .defaultScrollAnchor(.bottom)
        }
        .padding()
        .frame(width: 640, height: 340)
    }

    private var fullText: String {
        (YTDLP.commandLine(item.arguments) + "\n\n" + item.log.joined(separator: "\n"))
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
