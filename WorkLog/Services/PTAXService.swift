import AppKit
import Foundation
import Observation

nonisolated struct PTAXSnapshot: Codable, Sendable {
    let bulletinDate: String
    let usdToBRL: Decimal
    let eurToBRL: Decimal

    var hasValidRates: Bool {
        usdToBRL.isFinite && usdToBRL > 0 && eurToBRL.isFinite && eurToBRL > 0
    }

    func convert(_ value: Decimal, from source: ProjectCurrency, to target: ProjectCurrency) -> Decimal? {
        if source == target || value == 0 { return value }
        guard hasValidRates else { return nil }
        let converted = value * rate(for: source) / rate(for: target)
        return converted.isFinite ? converted : nil
    }

    private func rate(for currency: ProjectCurrency) -> Decimal {
        switch currency {
        case .brl: 1
        case .usd: usdToBRL
        case .eur: eurToBRL
        }
    }
}

nonisolated enum PTAXClient {
    enum FetchError: Error, Equatable {
        case invalidRequest
        case invalidResponse
        case noCommonClosing
    }

    private struct Response: Decodable {
        let value: [Bulletin]
    }

    private struct Bulletin: Decodable {
        let dataHoraCotacao: String
        let tipoBoletim: String
        let cotacaoVenda: Decimal
    }

    static func fetch(for date: Date) async throws -> PTAXSnapshot {
        let calendar = PTAXCalendar.brasilia
        guard let start = calendar.date(byAdding: .day, value: -10, to: date) else {
            throw FetchError.invalidRequest
        }
        async let usd = fetchBulletins(for: .usd, from: start, through: date)
        async let eur = fetchBulletins(for: .eur, from: start, through: date)
        return try await snapshot(usd: usd, eur: eur, through: PTAXCalendar.day(containing: date))
    }

    private static func fetchBulletins(for currency: ProjectCurrency, from start: Date, through end: Date) async throws -> Data {
        var components = URLComponents()
        components.scheme = "https"
        components.host = "olinda.bcb.gov.br"
        components.path = "/olinda/servico/PTAX/versao/v1/odata/CotacaoMoedaPeriodo(moeda=@moeda,dataInicial=@dataInicial,dataFinalCotacao=@dataFinalCotacao)"
        components.queryItems = [
            URLQueryItem(name: "@moeda", value: "'\(currency.rawValue)'"),
            URLQueryItem(name: "@dataInicial", value: "'\(PTAXCalendar.requestDate(start))'"),
            URLQueryItem(name: "@dataFinalCotacao", value: "'\(PTAXCalendar.requestDate(end))'"),
            URLQueryItem(name: "$format", value: "json"),
        ]
        guard let url = components.url else { throw FetchError.invalidRequest }
        let request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 15)
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let response = response as? HTTPURLResponse, response.statusCode == 200 else {
            throw FetchError.invalidResponse
        }
        return data
    }

    static func snapshot(usd: Data, eur: Data, through endDate: String) throws -> PTAXSnapshot {
        let usdClosings = try closingBulletins(usd, through: endDate)
        let eurClosings = try closingBulletins(eur, through: endDate)
        guard let date = usdClosings.keys.filter({ eurClosings[$0] != nil }).max(),
              let usdRate = usdClosings[date]?.cotacaoVenda,
              let eurRate = eurClosings[date]?.cotacaoVenda else {
            throw FetchError.noCommonClosing
        }
        return PTAXSnapshot(bulletinDate: date, usdToBRL: usdRate, eurToBRL: eurRate)
    }

    private static func closingBulletins(_ data: Data, through endDate: String) throws -> [String: Bulletin] {
        let response = try JSONDecoder().decode(Response.self, from: data)
        var closings: [String: Bulletin] = [:]
        for bulletin in response.value {
            let kind = bulletin.tipoBoletim.uppercased()
            guard kind == "FECHAMENTO" || kind == "FECHAMENTO PTAX",
                  bulletin.cotacaoVenda.isFinite, bulletin.cotacaoVenda > 0 else { continue }
            let date = String(bulletin.dataHoraCotacao.prefix(10))
            guard PTAXCalendar.isDate(date), date <= endDate else { continue }
            if let earlier = closings[date], earlier.dataHoraCotacao >= bulletin.dataHoraCotacao { continue }
            closings[date] = bulletin
        }
        return closings
    }
}

private nonisolated enum PTAXCalendar {
    static let brasilia: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Sao_Paulo")!
        return calendar
    }()

    static func day(containing date: Date) -> String {
        let parts = brasilia.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year!, parts.month!, parts.day!)
    }

    static func requestDate(_ date: Date) -> String {
        let parts = brasilia.dateComponents([.year, .month, .day], from: date)
        return String(format: "%02d-%02d-%04d", parts.month!, parts.day!, parts.year!)
    }

    static func isDate(_ day: String) -> Bool {
        guard day.range(of: #"^[0-9]{4}-[0-9]{2}-[0-9]{2}$"#, options: .regularExpression) != nil else {
            return false
        }
        let parts = day.split(separator: "-").compactMap { Int($0) }
        guard let date = brasilia.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2])) else {
            return false
        }
        return self.day(containing: date) == day
    }
}

@MainActor
@Observable
final class PTAXService {
    private(set) var snapshot: PTAXSnapshot?
    private(set) var isRefreshing = false
    private(set) var didFailToRefresh = false

    var isUsingCachedRates: Bool { snapshot != nil && didFailToRefresh }

    private struct Cache: Codable {
        let queryDate: String
        let snapshot: PTAXSnapshot
    }

    private static let cacheKey = "WorkLog.ptax.cache"
    private static let retryInterval: TimeInterval = 15 * 60

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let now: () -> Date
    @ObservationIgnored private let fetch: (Date) async throws -> PTAXSnapshot
    @ObservationIgnored private var lastQueryDate: String?
    @ObservationIgnored private var lastFailure: (day: String, time: Date)?
    @ObservationIgnored private var scheduledRefresh: Timer?
    @ObservationIgnored private var observers: [(NotificationCenter, NSObjectProtocol)] = []

    init(
        defaults: UserDefaults = .standard,
        now: @escaping () -> Date = Date.init,
        fetch: @escaping (Date) async throws -> PTAXSnapshot = PTAXClient.fetch
    ) {
        self.defaults = defaults
        self.now = now
        self.fetch = fetch
        if let data = defaults.data(forKey: Self.cacheKey),
           let cache = try? JSONDecoder().decode(Cache.self, from: data),
           cache.snapshot.hasValidRates,
           PTAXCalendar.isDate(cache.snapshot.bulletinDate),
           PTAXCalendar.isDate(cache.queryDate),
           cache.snapshot.bulletinDate <= cache.queryDate {
            snapshot = cache.snapshot
            lastQueryDate = cache.queryDate
        }
    }

    isolated deinit {
        scheduledRefresh?.invalidate()
        observers.forEach { center, token in center.removeObserver(token) }
    }

    func start() {
        guard observers.isEmpty else { return }
        observe(NSApplication.didBecomeActiveNotification, center: .default)
        observe(.NSSystemClockDidChange, center: .default)
        observe(NSWorkspace.didWakeNotification, center: NSWorkspace.shared.notificationCenter)
        checkNowAndSchedule()
    }

    func convert(_ value: Decimal, from source: ProjectCurrency, to target: ProjectCurrency) -> Decimal? {
        if source == target || value == 0 { return value }
        return snapshot?.convert(value, from: source, to: target)
    }

    func refreshIfNeeded() async {
        let startedAt = now()
        let day = PTAXCalendar.day(containing: startedAt)
        guard !isRefreshing, lastQueryDate != day, retryDate(after: startedAt, on: day) == nil else { return }

        isRefreshing = true
        defer { isRefreshing = false }
        do {
            let loaded = try await fetch(startedAt)
            guard loaded.hasValidRates,
                  PTAXCalendar.isDate(loaded.bulletinDate),
                  loaded.bulletinDate <= day,
                  snapshot.map({ $0.bulletinDate > day || loaded.bulletinDate >= $0.bulletinDate }) ?? true else {
                throw PTAXClient.FetchError.invalidResponse
            }
            let cache = try JSONEncoder().encode(Cache(queryDate: day, snapshot: loaded))
            defaults.set(cache, forKey: Self.cacheKey)
            snapshot = loaded
            lastQueryDate = day
            lastFailure = nil
            didFailToRefresh = false
        } catch {
            lastFailure = (day, now())
            didFailToRefresh = true
        }
    }

    private func retryDate(after date: Date, on day: String) -> Date? {
        guard let lastFailure, lastFailure.day == day, lastFailure.time <= date else { return nil }
        let retryAt = lastFailure.time.addingTimeInterval(Self.retryInterval)
        return retryAt > date ? retryAt : nil
    }

    private func observe(_ notification: Notification.Name, center: NotificationCenter) {
        let token = center.addObserver(forName: notification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor [weak self] in self?.checkNowAndSchedule() }
        }
        observers.append((center, token))
    }

    private func checkNowAndSchedule() {
        scheduledRefresh?.invalidate()
        scheduledRefresh = nil
        guard !isRefreshing else { return }
        Task { [weak self] in
            guard let self else { return }
            await self.refreshIfNeeded()
            self.scheduleNextRefresh()
        }
    }

    private func scheduleNextRefresh() {
        guard !isRefreshing else { return }
        let current = now()
        guard let midnight = PTAXCalendar.brasilia.dateInterval(of: .day, for: current)?.end else { return }
        let day = PTAXCalendar.day(containing: current)
        let next = lastQueryDate == day
            ? midnight
            : min(midnight, retryDate(after: current, on: day) ?? current)
        scheduledRefresh?.invalidate()
        let timer = Timer(fire: next, interval: 0, repeats: false) { [weak self] _ in
            Task { @MainActor [weak self] in self?.checkNowAndSchedule() }
        }
        RunLoop.main.add(timer, forMode: .common)
        scheduledRefresh = timer
    }
}
