import Foundation

struct StockQuote: Identifiable {
    let id: String
    let symbol: String
    let companyName: String
    let price: Double
    let change: Double
    let changePercent: Double
    let updatedAt: Date

    var isPositive: Bool { change >= 0 }
    var priceDisplay: String { String(format: "$%.2f", price) }
    var changeDisplay: String { String(format: "%+.2f%%", changePercent) }
}

class StocksManager: ObservableObject {
    static let shared = StocksManager()

    private let watchlistKey = "luna.stocks.watchlist.v1"
    private var activeTask: URLSessionDataTask?

    @Published var quotes: [StockQuote] = []
    @Published var isLoading = false
    @Published var error: String?
    @Published var watchlist: [String] {
        didSet { UserDefaults.standard.set(watchlist, forKey: watchlistKey) }
    }

    init() {
        let saved = UserDefaults.standard.stringArray(forKey: watchlistKey)
        watchlist = saved?.isEmpty == false ? saved! : ["AAPL", "GOOGL", "MSFT", "AMZN", "TSLA"]
    }

    func fetchQuotes() {
        guard !watchlist.isEmpty else { return }
        activeTask?.cancel()
        isLoading = true
        error = nil

        let symbols = watchlist.joined(separator: "%2C")
        let urlStr = "https://query1.finance.yahoo.com/v7/finance/quote?symbols=\(symbols)"
        guard let url = URL(string: urlStr) else { isLoading = false; return }

        var req = URLRequest(url: url, timeoutInterval: 15)
        req.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15",
                     forHTTPHeaderField: "User-Agent")

        activeTask = URLSession.shared.dataTask(with: req) { [weak self] data, _, err in
            DispatchQueue.main.async {
                guard let self else { return }
                self.isLoading = false
                if let err {
                    if (err as NSError).code != NSURLErrorCancelled {
                        self.error = err.localizedDescription
                    }
                    return
                }
                guard let data,
                      let resp = try? JSONDecoder().decode(YahooResponse.self, from: data)
                else { self.error = "Could not parse quote data"; return }

                self.quotes = resp.quoteResponse.result.map { r in
                    StockQuote(
                        id:            r.symbol,
                        symbol:        r.symbol,
                        companyName:   r.shortName ?? r.symbol,
                        price:         r.regularMarketPrice ?? 0,
                        change:        r.regularMarketChange ?? 0,
                        changePercent: r.regularMarketChangePercent ?? 0,
                        updatedAt:     Date()
                    )
                }
                self.error = nil
            }
        }
        activeTask?.resume()
    }

    func addSymbol(_ symbol: String) {
        let s = symbol.uppercased().trimmingCharacters(in: .whitespaces)
        guard !s.isEmpty, !watchlist.contains(s) else { return }
        watchlist.append(s)
    }

    func removeSymbols(at offsets: IndexSet) {
        watchlist.remove(atOffsets: offsets)
        quotes.removeAll { !watchlist.contains($0.symbol) }
    }
}

private struct YahooResponse: Decodable {
    let quoteResponse: QuoteResponse
    struct QuoteResponse: Decodable {
        let result: [QuoteResult]
    }
    struct QuoteResult: Decodable {
        let symbol: String
        let shortName: String?
        let regularMarketPrice: Double?
        let regularMarketChange: Double?
        let regularMarketChangePercent: Double?
    }
}
