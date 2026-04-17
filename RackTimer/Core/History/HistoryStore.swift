import Foundation
import Combine

struct LoggedSet: Codable, Identifiable, Equatable {
    let id: UUID
    var exercise: String
    var weight: Double
    var reps: Int
    var note: String
    var date: Date

    init(id: UUID = UUID(), exercise: String, weight: Double, reps: Int, note: String = "", date: Date = .now) {
        self.id = id; self.exercise = exercise; self.weight = weight; self.reps = reps; self.note = note; self.date = date
    }
}

/// File-backed history. Writes happen on the main actor; read returns a
/// snapshot copy to callers. For the scale of one person's lifting log this
/// is more than fast enough and avoids the ceremony of Core Data.
@MainActor
final class HistoryStore: ObservableObject {

    @Published private(set) var sets: [LoggedSet] = []

    private let url: URL
    private let maxInMemory = 2000

    init(fileURL: URL? = nil) {
        self.url = fileURL ?? Self.defaultURL()
        load()
    }

    func add(_ set: LoggedSet) {
        sets.insert(set, at: 0)
        if sets.count > maxInMemory { sets.removeLast(sets.count - maxInMemory) }
        save()
    }

    func delete(_ id: UUID) {
        sets.removeAll { $0.id == id }
        save()
    }

    /// Most recent logged set for the given exercise name (case-insensitive),
    /// or `nil` if none.
    func lastSet(for exercise: String) -> LoggedSet? {
        let key = exercise.trimmingCharacters(in: .whitespaces).lowercased()
        guard !key.isEmpty else { return nil }
        return sets.first { $0.exercise.lowercased() == key }
    }

    /// Returns distinct exercise names seen, most recent first.
    var distinctExercises: [String] {
        var seen = Set<String>()
        var out: [String] = []
        for s in sets {
            let k = s.exercise.lowercased()
            if !seen.contains(k) { seen.insert(k); out.append(s.exercise) }
        }
        return out
    }

    /// Filters the in-memory list by free-tier history window (days).
    /// Premium callers should pass `nil` to get everything.
    func visibleSets(maxDays: Int?) -> [LoggedSet] {
        guard let maxDays else { return sets }
        let cutoff = Calendar.current.date(byAdding: .day, value: -maxDays, to: .now) ?? .distantPast
        return sets.filter { $0.date >= cutoff }
    }

    // MARK: Persistence

    private func load() {
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        do {
            let data = try Data(contentsOf: url)
            let decoded = try JSONDecoder.iso.decode([LoggedSet].self, from: data)
            self.sets = decoded
        } catch {
            // Corrupt file — start fresh, keep the old one as .bak for manual recovery.
            let bak = url.appendingPathExtension("bak-\(Int(Date().timeIntervalSince1970))")
            try? FileManager.default.moveItem(at: url, to: bak)
            self.sets = []
        }
    }

    private func save() {
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            let data = try JSONEncoder.iso.encode(sets)
            try data.write(to: url, options: [.atomic])
        } catch {
            // Intentionally swallow — no UX for this beyond next-launch recovery.
        }
    }

    private static func defaultURL() -> URL {
        let base = (try? FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true))
            ?? FileManager.default.temporaryDirectory
        return base.appendingPathComponent("RackTimer", isDirectory: true).appendingPathComponent("history.json")
    }
}

extension JSONEncoder {
    static let iso: JSONEncoder = { let e = JSONEncoder(); e.dateEncodingStrategy = .iso8601; e.outputFormatting = [.sortedKeys]; return e }()
}
extension JSONDecoder {
    static let iso: JSONDecoder = { let d = JSONDecoder(); d.dateDecodingStrategy = .iso8601; return d }()
}
