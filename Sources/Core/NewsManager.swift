import Foundation

struct NewsArticle: Identifiable {
    let id: String
    let title: String
    let summary: String
    let url: URL?
    let source: String
    let publishedAt: Date?

    var timeAgo: String {
        guard let date = publishedAt else { return "" }
        let interval = Date().timeIntervalSince(date)
        if interval < 3600   { return "\(Int(interval / 60))m ago" }
        if interval < 86400  { return "\(Int(interval / 3600))h ago" }
        return "\(Int(interval / 86400))d ago"
    }
}

enum NewsFeed: String, CaseIterable {
    case headlines  = "Headlines"
    case technology = "Technology"
    case business   = "Business"
    case sports     = "Sports"

    var feedURL: URL {
        switch self {
        case .headlines:  return URL(string: "https://feeds.bbci.co.uk/news/rss.xml")!
        case .technology: return URL(string: "https://feeds.bbci.co.uk/news/technology/rss.xml")!
        case .business:   return URL(string: "https://feeds.bbci.co.uk/news/business/rss.xml")!
        case .sports:     return URL(string: "https://feeds.bbci.co.uk/sport/rss.xml")!
        }
    }
}

class NewsManager: NSObject, ObservableObject, XMLParserDelegate {
    static let shared = NewsManager()

    @Published var articles: [NewsArticle] = []
    @Published var isLoading = false
    @Published var error: String?
    @Published var selectedFeed: NewsFeed = .headlines

    private var parseBuffer: [NewsArticle] = []
    private var currentElement = ""
    private var currentTitle = ""
    private var currentDesc = ""
    private var currentLink = ""
    private var currentDate = ""
    private var inItem = false

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "EEE, dd MMM yyyy HH:mm:ss Z"
        return f
    }()

    func fetch(feed: NewsFeed? = nil) {
        let target = feed ?? selectedFeed
        isLoading = true
        error = nil
        URLSession.shared.dataTask(with: target.feedURL) { [weak self] data, _, err in
            guard let self else { return }
            guard let data, err == nil else {
                DispatchQueue.main.async {
                    self.isLoading = false
                    self.error = err?.localizedDescription ?? "Fetch failed"
                }
                return
            }
            self.parseBuffer = []
            let parser = XMLParser(data: data)
            parser.delegate = self
            parser.parse()
            let result = Array(self.parseBuffer.prefix(30))
            DispatchQueue.main.async {
                self.articles = result
                self.isLoading = false
            }
        }.resume()
    }

    // MARK: - XMLParserDelegate

    func parser(_ parser: XMLParser, didStartElement name: String,
                namespaceURI: String?, qualifiedName: String?,
                attributes: [String: String] = [:]) {
        currentElement = name
        if name == "item" {
            inItem = true
            currentTitle = ""; currentDesc = ""; currentLink = ""; currentDate = ""
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        guard inItem else { return }
        switch currentElement {
        case "title":       currentTitle += string
        case "description": currentDesc  += string
        case "link":        currentLink  += string
        case "pubDate":     currentDate  += string
        default: break
        }
    }

    func parser(_ parser: XMLParser, didEndElement name: String,
                namespaceURI: String?, qualifiedName: String?) {
        guard name == "item", inItem else { return }
        inItem = false
        let link = currentLink.trimmingCharacters(in: .whitespacesAndNewlines)
        parseBuffer.append(NewsArticle(
            id:          link.isEmpty ? UUID().uuidString : link,
            title:       currentTitle.trimmingCharacters(in: .whitespacesAndNewlines),
            summary:     currentDesc.trimmingCharacters(in: .whitespacesAndNewlines),
            url:         URL(string: link),
            source:      "BBC News",
            publishedAt: Self.dateFormatter.date(
                from: currentDate.trimmingCharacters(in: .whitespacesAndNewlines))
        ))
    }
}
