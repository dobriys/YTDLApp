import SwiftUI

struct PresetBar: View {
    @Environment(AppState.self) private var state

    private enum NameDialog { case create, rename }
    @State private var nameDialog: NameDialog?
    @State private var name = ""
    @State private var confirmDelete = false

    var body: some View {
        HStack(spacing: 8) {
            Text("Пресет:")
            Menu(state.selectedPreset?.name ?? "Без пресета") {
                ForEach(state.presets) { preset in
                    Toggle(preset.name, isOn: Binding(
                        get: { state.selectedPresetID == preset.id },
                        set: { _ in state.applyPreset(preset) }
                    ))
                }
            }
            .fixedSize()

            if state.isPresetModified, let preset = state.selectedPreset {
                Text("(изменён)").foregroundStyle(.secondary)
                Button("Обновить пресет") { state.updateSelectedPreset() }
                    .help("Сохранить текущие настройки в «\(preset.name)»")
                Button("Отменить изменения") { state.applyPreset(preset) }
            }

            Spacer()

            Menu {
                Button("Сохранить как новый…") { showNameDialog(.create, initial: "") }
                Button("Переименовать…") { showNameDialog(.rename, initial: state.selectedPreset?.name ?? "") }
                    .disabled(state.selectedPreset == nil)
                Button("Удалить…", role: .destructive) { confirmDelete = true }
                    .disabled(state.selectedPreset == nil)
                Divider()
                Button("Вернуть встроенные пресеты") { state.restoreBuiltInPresets() }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .help("Управление пресетами")
        }
        .alert(nameDialog == .rename ? "Переименовать пресет" : "Новый пресет",
               isPresented: Binding(get: { nameDialog != nil }, set: { if !$0 { nameDialog = nil } })) {
            TextField("Название", text: $name)
            Button("Отмена", role: .cancel) {}
            Button("Сохранить") { commitName() }
        } message: {
            if nameDialog == .create {
                Text("Сохранятся текущие настройки, кроме папки загрузок.")
            }
        }
        .confirmationDialog("Удалить пресет «\(state.selectedPreset?.name ?? "")»?", isPresented: $confirmDelete) {
            Button("Удалить", role: .destructive) { state.deleteSelectedPreset() }
        } message: {
            Text("Текущие настройки останутся как есть.")
        }
    }

    private func showNameDialog(_ kind: NameDialog, initial: String) {
        name = initial
        nameDialog = kind
    }

    private func commitName() {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        switch nameDialog {
        case .create: state.saveAsNewPreset(named: trimmed)
        case .rename: state.renameSelectedPreset(to: trimmed)
        case nil: break
        }
    }
}
