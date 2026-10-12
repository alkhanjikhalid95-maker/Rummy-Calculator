import SwiftUI

struct NameEditorView: View {
    var presetNames: PresetNamesManager
    @Environment(\.dismiss) private var dismiss
    @State private var editingName: String?
    @State private var editText = ""
    @State private var newName = ""

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack {
                        TextField("أضف اسماً جديداً", text: $newName)
                            .submitLabel(.done)
                            .onSubmit(addName)
                        Button(action: addName) {
                            Image(systemName: "plus.circle.fill")
                                .font(.title3)
                                .foregroundStyle(Color.ink)
                        }
                        .disabled(newName.trimmingCharacters(in: .whitespaces).isEmpty)
                        .accessibilityLabel(Text("إضافة"))
                    }
                }

                // Custom names (editable)
                if !presetNames.customNames.isEmpty {
                    Section("أسماؤك") {
                        ForEach(presetNames.customNames, id: \.self) { name in
                            if editingName == name {
                                HStack {
                                    TextField("الاسم", text: $editText)
                                        .submitLabel(.done)
                                        .onSubmit {
                                            saveEdit(oldName: name)
                                        }
                                    Button {
                                        saveEdit(oldName: name)
                                    } label: {
                                        Image(systemName: "checkmark.circle.fill")
                                            .foregroundStyle(Color.positive)
                                            .font(.title3)
                                    }
                                    .accessibilityLabel(Text("حفظ"))
                                    Button {
                                        editingName = nil
                                        editText = ""
                                    } label: {
                                        Image(systemName: "xmark.circle.fill")
                                            .foregroundStyle(Color.negative)
                                            .font(.title3)
                                    }
                                    .accessibilityLabel(Text("إلغاء"))
                                }
                                .buttonStyle(.plain)
                            } else {
                                HStack {
                                    Text(name)
                                    Spacer()
                                    Button {
                                        editingName = name
                                        editText = name
                                    } label: {
                                        Image(systemName: "pencil")
                                            .foregroundStyle(Color.ink)
                                    }
                                    .buttonStyle(.plain)
                                    .accessibilityLabel(Text("تعديل \(name)"))
                                }
                            }
                        }
                        .onDelete { indexSet in
                            for index in indexSet {
                                presetNames.removeName(presetNames.customNames[index])
                            }
                        }
                    }
                }

                // Built-in names (read-only)
                Section("أسماء جاهزة") {
                    ForEach(builtInNames, id: \.self) { name in
                        Text(name)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .navigationTitle("الأسماء المحفوظة")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("تم") { dismiss() }
                        .fontWeight(.semibold)
                }
            }
            .animation(.default, value: presetNames.customNames)
        }
        .tint(Color.ink)
        .themedSheet()
    }

    private var builtInNames: [String] {
        // Show built-in names that aren't overridden by custom
        let customLowered = Set(presetNames.customNames.map { $0.lowercased() })
        return PresetNamesManager.builtIn.filter { !customLowered.contains($0.lowercased()) }
    }

    private func addName() {
        presetNames.addNames([newName])
        newName = ""
    }

    private func saveEdit(oldName: String) {
        let trimmed = editText.trimmingCharacters(in: .whitespaces)
        if !trimmed.isEmpty && trimmed != oldName {
            presetNames.renameName(from: oldName, to: trimmed)
        }
        editingName = nil
        editText = ""
    }
}
