import Foundation
import Combine

struct WorkoutTemplate: Codable, Identifiable, Equatable {
    let id: UUID
    var name: String
    var exercises: [String]
    var createdAt: Date

    init(id: UUID = UUID(), name: String, exercises: [String], createdAt: Date = .now) {
        self.id = id; self.name = name; self.exercises = exercises; self.createdAt = createdAt
    }
}

@MainActor
final class TemplateStore: ObservableObject {

    @Published private(set) var templates: [WorkoutTemplate] = []

    private let url: URL

    init(fileURL: URL? = nil) {
        self.url = fileURL ?? Self.defaultURL()
        load()
        if templates.isEmpty { templates = Self.starterTemplates() }
    }

    func add(_ t: WorkoutTemplate) {
        templates.append(t)
        templates.sort { $0.name < $1.name }
        save()
    }

    func update(_ t: WorkoutTemplate) {
        guard let i = templates.firstIndex(where: { $0.id == t.id }) else { return }
        templates[i] = t
        save()
    }

    func delete(_ id: UUID) {
        templates.removeAll { $0.id == id }
        save()
    }

    // MARK: Seed / Persistence

    private static func starterTemplates() -> [WorkoutTemplate] {
        [
            WorkoutTemplate(name: "Push Day",  exercises: ["Bench Press", "Overhead Press", "Incline DB Press", "Tricep Pushdown"]),
            WorkoutTemplate(name: "Pull Day",  exercises: ["Deadlift", "Barbell Row", "Lat Pulldown", "Bicep Curl"]),
            WorkoutTemplate(name: "Leg Day",   exercises: ["Back Squat", "Romanian Deadlift", "Leg Press", "Calf Raise"]),
        ]
    }

    private func load() {
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        if let data = try? Data(contentsOf: url),
           let decoded = try? JSONDecoder.iso.decode([WorkoutTemplate].self, from: data) {
            self.templates = decoded
        }
    }

    private func save() {
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            let data = try JSONEncoder.iso.encode(templates)
            try data.write(to: url, options: [.atomic])
        } catch {
            // swallow — retry on next mutation
        }
    }

    private static func defaultURL() -> URL {
        let base = (try? FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true))
            ?? FileManager.default.temporaryDirectory
        return base.appendingPathComponent("RackTimer", isDirectory: true).appendingPathComponent("templates.json")
    }
}
