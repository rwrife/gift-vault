import GiftVaultKit
import GiftVaultStoreKit
import SwiftUI

// App composition root (issue #4). The app model lives in
// GiftVaultStoreKit (compile-checked on Linux CI); this file only wires
// it to SwiftUI and supplies the wall-clock "today" the store refuses
// to read itself (issue #2 contract: the caller supplies dates).

@main
struct GiftVaultApp: App {
    @State private var model: GiftVaultAppModel = GiftVaultApp.makeModel()

    var body: some Scene {
        WindowGroup {
            HomeTabView()
                .environmentObject(model)
        }
    }

    /// UI-test launches (`-ui-testing`) get the deterministic fixture
    /// vault on a fixed today; normal launches open the on-device
    /// database. A store that cannot be opened falls back to an empty
    /// in-memory vault rather than crashing the launch (data-loss is
    /// visible; a crash loop is not recoverable by the user).
    private static func makeModel() -> GiftVaultAppModel {
        let fixedToday = CalendarDate(year: 2026, month: 9, day: 23)!
        if CommandLine.arguments.contains("-ui-testing") {
            if let seeded = try? GiftVaultAppModel.fixtures(today: fixedToday) {
                return seeded
            }
        }
        if let store = try? GiftVaultStore(url: vaultURL()) {
            return GiftVaultAppModel(store: store, today: AppClock.today)
        }
        return GiftVaultAppModel(store: try! .inMemory(), today: AppClock.today)
    }

    private static func vaultURL() -> URL {
        let fileManager = FileManager.default
        let base = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let directory = base.appendingPathComponent("GiftVault", isDirectory: true)
        try? fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appendingPathComponent("vault.sqlite")
    }
}

/// The only place the app reads the wall clock. Domain facts always
/// flow from an explicit `CalendarDate`, never from `Date()` deep down.
enum AppClock {
    static var today: CalendarDate {
        CalendarDate(date: Date(), timeZone: .current)
            ?? CalendarDate(year: 2026, month: 1, day: 1)!
    }

    /// DatePicker binding helper: the stored day at local midnight.
    static func date(from day: CalendarDate) -> Date {
        day.startOfDay(in: .current) ?? Date(timeIntervalSince1970: 0)
    }

    static func calendarDate(from date: Date) -> CalendarDate? {
        CalendarDate(date: date, timeZone: .current)
    }
}
