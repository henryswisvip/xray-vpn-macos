import Foundation
import os.log

enum ServerCatalogError: LocalizedError {
    case missingSubscriptionURL
    case badStatusCode(Int)
    case emptyServerList

    var errorDescription: String? {
        switch self {
        case .missingSubscriptionURL:
            return "Subscription URL is not configured."
        case .badStatusCode(let statusCode):
            return "Subscription request failed with HTTP \(statusCode)."
        case .emptyServerList:
            return "Subscription contains no supported servers."
        }
    }
}

@MainActor
final class ServerCatalog: ObservableObject {
    @Published private(set) var servers: [ManagedServer]
    @Published private(set) var isRefreshing = false
    @Published private(set) var lastUpdated: Date?
    @Published var lastError: String?

    private let logger = Logger(subsystem: "com.henryswisvip.xrayvpn", category: "ServerCatalog")
    private let fileManager = FileManager.default
    private let urlSession: URLSession
    private let cacheFileURL: URL
    private var refreshTask: Task<Void, Never>?

    init(urlSession: URLSession = .shared) {
        self.urlSession = urlSession
        self.cacheFileURL = ServerCatalog.makeCacheFileURL(fileManager: fileManager)
        self.servers = ServiceConfig.fallbackServers

        loadCachedServers()
        startAutoRefreshTask()
    }

    deinit {
        refreshTask?.cancel()
    }

    func server(withID id: String) -> ManagedServer? {
        servers.first(where: { $0.id == id })
    }

    func refreshNow() async {
        guard !isRefreshing else { return }
        guard let subscriptionURL = ServiceConfig.subscriptionURL else {
            lastError = ServerCatalogError.missingSubscriptionURL.localizedDescription
            return
        }

        isRefreshing = true
        defer { isRefreshing = false }

        do {
            var request = URLRequest(url: subscriptionURL)
            request.cachePolicy = .reloadIgnoringLocalCacheData
            request.timeoutInterval = 20

            let (data, response) = try await urlSession.data(for: request)
            if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
                throw ServerCatalogError.badStatusCode(http.statusCode)
            }

            let parsed = try SubscriptionParser.parseServers(from: data, defaultSocksPort: ServiceConfig.defaultSocksPort)
            guard !parsed.isEmpty else {
                throw ServerCatalogError.emptyServerList
            }

            servers = parsed
            lastUpdated = Date()
            lastError = nil
            try saveServersToCache(parsed)
        } catch {
            logger.error("Server refresh failed: \(error.localizedDescription, privacy: .public)")
            lastError = error.localizedDescription

            if servers.isEmpty {
                servers = ServiceConfig.fallbackServers
            }
        }
    }

    private func startAutoRefreshTask() {
        refreshTask?.cancel()
        refreshTask = Task { [weak self] in
            guard let self else { return }
            await self.refreshNow()

            let interval = max(ServiceConfig.refreshInterval, 60)
            let nanoseconds = UInt64(interval * 1_000_000_000)

            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: nanoseconds)
                await self.refreshNow()
            }
        }
    }

    private func loadCachedServers() {
        guard let data = try? Data(contentsOf: cacheFileURL),
              let cached = try? JSONDecoder().decode([ManagedServer].self, from: data),
              !cached.isEmpty
        else {
            return
        }

        servers = cached
        if let attributes = try? fileManager.attributesOfItem(atPath: cacheFileURL.path) {
            lastUpdated = attributes[.modificationDate] as? Date
        }
    }

    private func saveServersToCache(_ servers: [ManagedServer]) throws {
        let directory = cacheFileURL.deletingLastPathComponent()
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)

        let data = try JSONEncoder().encode(servers)
        try data.write(to: cacheFileURL, options: [.atomic])
    }

    private static func makeCacheFileURL(fileManager: FileManager) -> URL {
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fileManager.temporaryDirectory
        return appSupport
            .appendingPathComponent("XrayVPN", isDirectory: true)
            .appendingPathComponent("servers_cache.json")
    }
}
