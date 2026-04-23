import SwiftUI

struct DataFeedsView: View {
    @EnvironmentObject var weather: WeatherManager
    @EnvironmentObject var stocks: StocksManager
    @EnvironmentObject var news: NewsManager

    @State private var tab = 0
    private let dark  = Color(red: 0.07, green: 0.07, blue: 0.10)
    private let accent = Color(red: 0.38, green: 0.49, blue: 1.0)

    var body: some View {
        NavigationStack {
            ZStack {
                dark.ignoresSafeArea()
                VStack(spacing: 0) {
                    Picker("Feed", selection: $tab) {
                        Text("WEATHER").tag(0)
                        Text("STOCKS").tag(1)
                        Text("NEWS").tag(2)
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal).padding(.top, 8)

                    switch tab {
                    case 0: WeatherPanel()
                    case 1: StocksPanel()
                    default: NewsPanel()
                    }
                }
            }
            .navigationTitle("Feeds")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.dark, for: .navigationBar)
        }
    }
}

// MARK: - Weather

struct WeatherPanel: View {
    @EnvironmentObject var weather: WeatherManager
    private let accent = Color(red: 0.38, green: 0.49, blue: 1.0)

    var body: some View {
        ScrollView {
            if weather.isLoading {
                ProgressView().tint(accent).padding(60)
            } else if let c = weather.condition {
                VStack(spacing: 16) {
                    // Hero
                    VStack(spacing: 12) {
                        HStack(spacing: 16) {
                            Image(systemName: c.symbolName)
                                .font(.system(size: 52))
                                .foregroundColor(accent)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(c.tempDisplay)
                                    .font(.system(size: 52, weight: .thin, design: .rounded))
                                Text(c.description)
                                    .font(.title3).foregroundColor(.secondary)
                            }
                        }
                        Text(c.city)
                            .font(.headline).foregroundColor(.secondary)
                        Text("Updated \(c.updatedAt.formatted(date: .omitted, time: .shortened))")
                            .font(.caption).foregroundColor(.secondary.opacity(0.6))
                    }
                    .padding(24)
                    .frame(maxWidth: .infinity)
                    .background(Color.white.opacity(0.05))
                    .cornerRadius(18)

                    // Detail grid
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                        WeatherTile(label: "Feels Like",
                                    value: "\(Int(c.feelsLike.rounded()))°F",
                                    icon: "thermometer.medium")
                        WeatherTile(label: "Wind Speed",
                                    value: "\(Int(c.windspeed.rounded())) mph",
                                    icon: "wind")
                    }

                    Button {
                        weather.requestLocationAndFetch()
                    } label: {
                        Label("Refresh", systemImage: "arrow.clockwise")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(accent)
                    }
                    .padding(.top, 4)
                }
                .padding()
            } else {
                VStack(spacing: 20) {
                    Image(systemName: "location.slash")
                        .font(.system(size: 44)).foregroundColor(.secondary)
                    Text(weather.error ?? "Tap to load weather")
                        .multilineTextAlignment(.center)
                        .foregroundColor(.secondary)
                    Button("Enable Location & Fetch") { weather.requestLocationAndFetch() }
                        .font(.headline).foregroundColor(accent)
                }
                .padding(50)
            }
        }
    }
}

struct WeatherTile: View {
    let label: String; let value: String; let icon: String
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 22))
                .foregroundColor(.secondary)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(label).font(.caption).foregroundColor(.secondary)
                Text(value).font(.headline)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color.white.opacity(0.05))
        .cornerRadius(14)
    }
}

// MARK: - Stocks

struct StocksPanel: View {
    @EnvironmentObject var stocks: StocksManager
    @State private var newSymbol = ""
    private let accent = Color(red: 0.38, green: 0.49, blue: 1.0)

    var body: some View {
        List {
            // Add ticker row
            HStack(spacing: 8) {
                TextField("Add symbol  (e.g. NVDA)", text: $newSymbol)
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
                Button("Add") {
                    stocks.addSymbol(newSymbol)
                    newSymbol = ""
                    stocks.fetchQuotes()
                }
                .foregroundColor(accent)
                .disabled(newSymbol.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .listRowBackground(Color.white.opacity(0.05))

            if stocks.isLoading {
                HStack { Spacer(); ProgressView().tint(accent); Spacer() }
                    .listRowBackground(Color.clear)
            }

            ForEach(stocks.quotes) { quote in
                StockRow(quote: quote).listRowBackground(Color.white.opacity(0.03))
            }
            .onDelete { stocks.removeSymbols(at: $0) }

            if stocks.quotes.isEmpty && !stocks.isLoading {
                Button("Load Quotes") { stocks.fetchQuotes() }
                    .foregroundColor(accent)
                    .listRowBackground(Color.clear)
            }

            if let err = stocks.error {
                Text(err).font(.caption).foregroundColor(.red)
                    .listRowBackground(Color.clear)
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .refreshable { stocks.fetchQuotes() }
        .onAppear { if stocks.quotes.isEmpty { stocks.fetchQuotes() } }
    }
}

struct StockRow: View {
    let quote: StockQuote
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(quote.symbol)
                    .font(.system(.headline, design: .monospaced))
                Text(quote.companyName)
                    .font(.caption).foregroundColor(.secondary).lineLimit(1)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(quote.priceDisplay)
                    .font(.system(.headline, design: .monospaced))
                Text(quote.changeDisplay)
                    .font(.caption2)
                    .foregroundColor(quote.isPositive ? .green : .red)
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - News

struct NewsPanel: View {
    @EnvironmentObject var news: NewsManager
    private let accent = Color(red: 0.38, green: 0.49, blue: 1.0)

    var body: some View {
        VStack(spacing: 0) {
            // Category pills
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(NewsFeed.allCases, id: \.self) { feed in
                        let selected = news.selectedFeed == feed
                        Button(feed.rawValue) {
                            news.selectedFeed = feed
                            news.fetch(feed: feed)
                        }
                        .font(.system(size: 12, weight: selected ? .bold : .regular))
                        .padding(.horizontal, 14).padding(.vertical, 7)
                        .background(selected ? accent.opacity(0.2) : Color.white.opacity(0.05))
                        .foregroundColor(selected ? accent : .secondary)
                        .cornerRadius(20)
                        .overlay(RoundedRectangle(cornerRadius: 20)
                            .stroke(selected ? accent.opacity(0.5) : Color.clear, lineWidth: 1))
                    }
                }
                .padding(.horizontal).padding(.vertical, 8)
            }

            if news.isLoading {
                Spacer()
                ProgressView().tint(accent)
                Spacer()
            } else if let err = news.error {
                VStack(spacing: 12) {
                    Image(systemName: "wifi.slash").font(.system(size: 36)).foregroundColor(.secondary)
                    Text(err).foregroundColor(.secondary).multilineTextAlignment(.center)
                    Button("Retry") { news.fetch() }.foregroundColor(accent)
                }
                .padding(40)
            } else {
                List(news.articles) { article in
                    ArticleRow(article: article).listRowBackground(Color.white.opacity(0.03))
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .refreshable { news.fetch() }
            }
        }
        .onAppear { if news.articles.isEmpty { news.fetch() } }
    }
}

struct ArticleRow: View {
    let article: NewsArticle
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(article.title)
                .font(.system(size: 14, weight: .semibold))
                .lineLimit(3)
            HStack {
                Text(article.source).font(.caption2).foregroundColor(.secondary)
                Spacer()
                Text(article.timeAgo).font(.caption2).foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 6)
        .contentShape(Rectangle())
        .onTapGesture {
            if let url = article.url { UIApplication.shared.open(url) }
        }
    }
}
