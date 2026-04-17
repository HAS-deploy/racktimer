import SwiftUI

struct TemplatesView: View {
    @EnvironmentObject private var templates: TemplateStore
    @EnvironmentObject private var purchases: PurchaseManager
    @Environment(\.analytics) private var analytics

    @State private var editing: WorkoutTemplate?
    @State private var showPaywall = false
    @State private var showNew = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(templates.templates) { t in
                        Button { editing = t } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(t.name).font(.headline)
                                Text(t.exercises.joined(separator: " · "))
                                    .font(.caption).foregroundStyle(.secondary).lineLimit(2)
                            }
                        }
                        .foregroundStyle(.primary)
                    }
                    .onDelete { idx in
                        idx.map { templates.templates[$0].id }.forEach(templates.delete)
                    }
                } footer: {
                    if !purchases.isPremium {
                        Text("Free: up to \(PricingConfig.freeTemplateSlots) templates. Premium unlocks unlimited.")
                            .font(.caption)
                    }
                }
            }
            .navigationTitle("Templates")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        let atLimit = !purchases.isPremium && templates.templates.count >= PricingConfig.freeTemplateSlots
                        if atLimit {
                            analytics.track(.paywallViewed, properties: ["from": "templates_limit"])
                            showPaywall = true
                        } else {
                            showNew = true
                        }
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .sheet(item: $editing) { t in
                NavigationStack { TemplateEditView(template: t) }
            }
            .sheet(isPresented: $showNew) {
                NavigationStack { TemplateEditView(template: nil) }
            }
            .sheet(isPresented: $showPaywall) {
                PaywallView(source: "templates_limit")
            }
        }
    }
}

struct TemplateEditView: View {
    @EnvironmentObject private var templates: TemplateStore
    @Environment(\.dismiss) private var dismiss

    let template: WorkoutTemplate?

    @State private var name: String = ""
    @State private var exercises: [String] = []
    @State private var newExercise: String = ""

    var body: some View {
        Form {
            Section("Name") { TextField("e.g. Upper A", text: $name).textInputAutocapitalization(.words) }
            Section("Exercises") {
                ForEach(exercises, id: \.self) { e in Text(e) }
                    .onDelete { idx in exercises.remove(atOffsets: idx) }
                HStack {
                    TextField("Add exercise", text: $newExercise)
                        .textInputAutocapitalization(.words)
                    Button("Add") {
                        let t = newExercise.trimmingCharacters(in: .whitespaces)
                        if !t.isEmpty { exercises.append(t); newExercise = "" }
                    }.disabled(newExercise.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
        .navigationTitle(template == nil ? "New Template" : "Edit Template")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") { save(); dismiss() }
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || exercises.isEmpty)
            }
        }
        .onAppear {
            if let t = template { name = t.name; exercises = t.exercises }
        }
    }

    private func save() {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        if let t = template {
            var updated = t; updated.name = trimmed; updated.exercises = exercises
            templates.update(updated)
        } else {
            templates.add(WorkoutTemplate(name: trimmed, exercises: exercises))
        }
    }
}
