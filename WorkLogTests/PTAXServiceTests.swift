import Foundation
import Testing
@testable import WorkLog

@MainActor
struct PTAXServiceTests {
    @Test func selectsLatestCommonClosingBulletin() throws {
        let usd = Data("""
            {"value": [
              {"dataHoraCotacao": "2026-11-20 13:04:18.325373", "tipoBoletim": "Fechamento", "cotacaoVenda": 5.2},
              {"dataHoraCotacao": "2026-11-19 13:04:18.325373", "tipoBoletim": "Fechamento", "cotacaoVenda": 5},
              {"dataHoraCotacao": "2026-11-19 13:05:18.325373", "tipoBoletim": "Intermediário", "cotacaoVenda": 5.5}
            ]}
            """.utf8)
        let eur = Data("""
            {"value": [
              {"dataHoraCotacao": "2026-11-20 13:04:18.325373", "tipoBoletim": "Fechamento", "cotacaoVenda": 0},
              {"dataHoraCotacao": "2026-11-19 13:04:18.325373", "tipoBoletim": "Fechamento PTAX", "cotacaoVenda": 6.5}
            ]}
            """.utf8)

        let snapshot = try PTAXClient.snapshot(usd: usd, eur: eur, through: "2026-11-20")

        #expect(snapshot.bulletinDate == "2026-11-19")
        #expect(snapshot.convert(26, from: .usd, to: .eur) == 20)
        #expect(snapshot.convert(1, from: .eur, to: .brl) == Decimal(6.5))
    }

    @Test func doesNotAcceptPartialSnapshot() {
        let usd = Data("""
            {"value": [
              {"dataHoraCotacao": "2026-11-19 13:04:18.325373", "tipoBoletim": "Fechamento", "cotacaoVenda": 5}
            ]}
            """.utf8)

        #expect(throws: PTAXClient.FetchError.noCommonClosing) {
            try PTAXClient.snapshot(usd: usd, eur: Data(#"{"value":[]}"#.utf8), through: "2026-11-20")
        }
    }

    @Test func refreshesOncePerBrasiliaDateAcrossRestarts() async throws {
        let (name, defaults) = try makeDefaults()
        defer { defaults.removePersistentDomain(forName: name) }
        let dateFormatter = ISO8601DateFormatter()
        var now = try #require(dateFormatter.date(from: "2026-11-20T02:59:00Z"))
        var requests = 0
        let fetch: (Date) async throws -> PTAXSnapshot = { _ in
            requests += 1
            return .init(bulletinDate: "2026-11-18", usdToBRL: 5, eurToBRL: 6.5)
        }
        let service = PTAXService(defaults: defaults, now: { now }, fetch: fetch)
        await service.refreshIfNeeded()
        await service.refreshIfNeeded()
        let reopened = PTAXService(defaults: defaults, now: { now }, fetch: fetch)
        #expect(reopened.snapshot?.bulletinDate == "2026-11-18")
        await reopened.refreshIfNeeded()
        #expect(requests == 1)

        now = now.addingTimeInterval(60)
        await reopened.refreshIfNeeded()
        #expect(requests == 2)
    }

    @Test func keepsLastClosingAndThrottlesRetryWhileOffline() async throws {
        let (name, defaults) = try makeDefaults()
        defer { defaults.removePersistentDomain(forName: name) }
        let dateFormatter = ISO8601DateFormatter()
        var now = try #require(dateFormatter.date(from: "2026-11-20T03:00:00Z"))
        var requests = 0
        var offline = false
        let service = PTAXService(defaults: defaults, now: { now }) { _ in
            requests += 1
            if offline { throw URLError(.notConnectedToInternet) }
            return .init(bulletinDate: "2026-11-19", usdToBRL: 5, eurToBRL: 6.5)
        }
        #expect(service.convert(1, from: .usd, to: .usd) == 1)
        #expect(service.convert(0, from: .usd, to: .eur) == 0)
        #expect(service.convert(1, from: .usd, to: .eur) == nil)

        await service.refreshIfNeeded()
        offline = true
        now = now.addingTimeInterval(86_400)
        await service.refreshIfNeeded()
        await service.refreshIfNeeded()
        #expect(requests == 2)
        #expect(service.isUsingCachedRates)
        #expect(service.convert(10, from: .usd, to: .brl) == 50)

        now = now.addingTimeInterval(15 * 60)
        offline = false
        await service.refreshIfNeeded()
        #expect(requests == 3)
        #expect(!service.isUsingCachedRates)
    }

    @Test func yesterdayFailureDoesNotDelayNewDayRefresh() async throws {
        let (name, defaults) = try makeDefaults()
        defer { defaults.removePersistentDomain(forName: name) }
        var now = try #require(ISO8601DateFormatter().date(from: "2026-11-20T02:55:00Z"))
        var requests = 0
        let service = PTAXService(defaults: defaults, now: { now }) { _ in
            requests += 1
            if requests == 1 { throw URLError(.notConnectedToInternet) }
            return .init(bulletinDate: "2026-11-19", usdToBRL: 5, eurToBRL: 6.5)
        }

        await service.refreshIfNeeded()
        #expect(service.didFailToRefresh)
        now = now.addingTimeInterval(5 * 60)
        await service.refreshIfNeeded()
        #expect(requests == 2)
        #expect(!service.didFailToRefresh)
    }

    private func makeDefaults() throws -> (name: String, defaults: UserDefaults) {
        let name = "WorkLog.PTAXServiceTests.\(UUID())"
        return (name, try #require(UserDefaults(suiteName: name)))
    }
}
