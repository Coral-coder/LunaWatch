import Foundation
import UIKit
import SwiftUI

enum ClockMode: String, CaseIterable, Codable {
    case digital = "Digital"
    case analog  = "Analog"
}

struct WatchFaceSettings: Codable {
    var clockMode: ClockMode = .digital
    var invertDisplay: Bool = false
    var backgroundPhotoData: Data?
    var showWeather: Bool = true
    var showDate: Bool = true
}

class WatchFaceManager: ObservableObject {
    private let settingsKey = "luna.watchface.v1"

    @Published var settings: WatchFaceSettings {
        didSet { save() }
    }

    init() {
        if let data = UserDefaults.standard.data(forKey: settingsKey),
           let decoded = try? JSONDecoder().decode(WatchFaceSettings.self, from: data) {
            settings = decoded
        } else {
            settings = WatchFaceSettings()
        }
    }

    private func save() {
        if let encoded = try? JSONEncoder().encode(settings) {
            UserDefaults.standard.set(encoded, forKey: settingsKey)
        }
    }

    // Renders a 160×160 pt UIImage of the watch face suitable for pushing to the hardware.
    func renderFaceImage(weatherText: String? = nil) -> UIImage {
        let size = CGSize(width: 160, height: 160)
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { _ in
            let rect = CGRect(origin: .zero, size: size)
            if let data = settings.backgroundPhotoData, let photo = UIImage(data: data) {
                photo.draw(in: rect)
                UIColor.black.withAlphaComponent(0.45).setFill()
                UIRectFill(rect)
            } else {
                (settings.invertDisplay ? UIColor.white : UIColor.black).setFill()
                UIRectFill(rect)
            }
            let fg = settings.invertDisplay ? UIColor.black : UIColor.white
            switch settings.clockMode {
            case .digital: renderDigital(size: size, fg: fg, weatherText: weatherText)
            case .analog:  renderAnalog(size: size, fg: fg, weatherText: weatherText)
            }
        }
    }

    private func renderDigital(size: CGSize, fg: UIColor, weatherText: String?) {
        let now = Date()
        let fmt = DateFormatter()
        fmt.dateFormat = "HH:mm"
        let time = fmt.string(from: now)
        fmt.dateFormat = "EEE d MMM"
        let date = fmt.string(from: now).uppercased()

        let timeFont = UIFont.monospacedDigitSystemFont(ofSize: 52, weight: .thin)
        let timeAttr: [NSAttributedString.Key: Any] = [.font: timeFont, .foregroundColor: fg]
        let ts = time.size(withAttributes: timeAttr)
        time.draw(at: CGPoint(x: (size.width - ts.width) / 2, y: 42), withAttributes: timeAttr)

        if settings.showDate {
            let dateFont = UIFont.systemFont(ofSize: 12, weight: .medium)
            let dateAttr: [NSAttributedString.Key: Any] = [.font: dateFont,
                .foregroundColor: fg.withAlphaComponent(0.7)]
            let ds = date.size(withAttributes: dateAttr)
            date.draw(at: CGPoint(x: (size.width - ds.width) / 2, y: 106), withAttributes: dateAttr)
        }

        if settings.showWeather, let wt = weatherText {
            let wFont = UIFont.systemFont(ofSize: 11)
            let wAttr: [NSAttributedString.Key: Any] = [.font: wFont,
                .foregroundColor: fg.withAlphaComponent(0.55)]
            let ws = wt.size(withAttributes: wAttr)
            wt.draw(at: CGPoint(x: (size.width - ws.width) / 2, y: 124), withAttributes: wAttr)
        }
    }

    private func renderAnalog(size: CGSize, fg: UIColor, weatherText: String?) {
        let center = CGPoint(x: size.width / 2, y: size.height / 2)
        let cal = Calendar.current
        let now = Date()
        let hour   = CGFloat(cal.component(.hour, from: now) % 12)
        let minute = CGFloat(cal.component(.minute, from: now))
        let second = CGFloat(cal.component(.second, from: now))

        fg.setStroke()
        for i in 0..<60 {
            let angle = CGFloat(i) * 6 * .pi / 180 - .pi / 2
            let outer: CGFloat = 72
            let inner: CGFloat = i % 5 == 0 ? 62 : 67
            let p1 = CGPoint(x: center.x + cos(angle) * inner, y: center.y + sin(angle) * inner)
            let p2 = CGPoint(x: center.x + cos(angle) * outer, y: center.y + sin(angle) * outer)
            let path = UIBezierPath()
            path.move(to: p1); path.addLine(to: p2)
            path.lineWidth = i % 5 == 0 ? 2.5 : 1
            path.stroke()
        }

        drawHand(center: center, angle: (hour + minute / 60) * 30 - 90,
                 length: 42, width: 5, color: fg)
        drawHand(center: center, angle: (minute + second / 60) * 6 - 90,
                 length: 60, width: 3, color: fg)
        drawHand(center: center, angle: second * 6 - 90,
                 length: 64, width: 1.5, color: .systemRed)

        let dot = UIBezierPath(arcCenter: center, radius: 4,
                               startAngle: 0, endAngle: .pi * 2, clockwise: true)
        fg.setFill(); dot.fill()

        if settings.showWeather, let wt = weatherText {
            let wFont = UIFont.systemFont(ofSize: 10)
            let wAttr: [NSAttributedString.Key: Any] = [.font: wFont,
                .foregroundColor: fg.withAlphaComponent(0.6)]
            let ws = wt.size(withAttributes: wAttr)
            wt.draw(at: CGPoint(x: (size.width - ws.width) / 2, y: 126), withAttributes: wAttr)
        }
    }

    private func drawHand(center: CGPoint, angle: CGFloat, length: CGFloat,
                          width: CGFloat, color: UIColor) {
        let rad = angle * .pi / 180
        let end  = CGPoint(x: center.x + cos(rad) * length,       y: center.y + sin(rad) * length)
        let tail = CGPoint(x: center.x - cos(rad) * length * 0.18, y: center.y - sin(rad) * length * 0.18)
        let path = UIBezierPath()
        path.move(to: tail); path.addLine(to: end)
        path.lineWidth = width; path.lineCapStyle = .round
        color.setStroke(); path.stroke()
    }
}
