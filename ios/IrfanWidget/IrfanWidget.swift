import WidgetKit
import SwiftUI

// Общий App Group, куда Flutter (home_widget) кладёт времена намаза.
let appGroup = "group.kg.irfan.irfan"

struct PrayerRow: Identifiable {
    let id = UUID()
    let key: String
    let label: String
    let time: String
    let mins: Int
    let isPrayer: Bool
}

struct IrfanEntry: TimelineEntry {
    let date: Date
    let city: String
    let dateLabel: String
    let rows: [PrayerRow]
    let nextKey: String?
}

struct Provider: TimelineProvider {
    private let order = ["fajr", "sunrise", "dhuhr", "asr", "maghrib", "isha"]

    func placeholder(in context: Context) -> IrfanEntry {
        IrfanEntry(date: Date(), city: "Бишкек", dateLabel: "",
                   rows: sample(), nextKey: "dhuhr")
    }

    func getSnapshot(in context: Context, completion: @escaping (IrfanEntry) -> Void) {
        completion(readEntry())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<IrfanEntry>) -> Void) {
        let entry = readEntry()
        // Обновляем каждые 10 минут, чтобы подсветка «следующего» шла вперёд.
        let next = Calendar.current.date(byAdding: .minute, value: 10, to: Date())!
        completion(Timeline(entries: [entry], policy: .after(next)))
    }

    private func readEntry() -> IrfanEntry {
        let d = UserDefaults(suiteName: appGroup)
        var rows: [PrayerRow] = []
        for k in order {
            let label = d?.string(forKey: "\(k)_label") ?? ""
            let time = d?.string(forKey: "\(k)_time") ?? "—"
            let mins = d?.integer(forKey: "\(k)_mins") ?? 0
            rows.append(PrayerRow(key: k, label: label.isEmpty ? fallbackLabel(k) : label,
                                  time: time, mins: mins, isPrayer: k != "sunrise"))
        }
        let city = d?.string(forKey: "city") ?? "Ирфан"
        let dateLabel = d?.string(forKey: "date") ?? ""
        let nowMins = currentMinutes()
        // Ближайший намаз сегодня; после Иши — Фаджр (наступит завтра,
        // время почти то же, поэтому показываем его как следующий).
        let next = rows.first(where: { $0.isPrayer && $0.mins > nowMins })?.key
            ?? rows.first(where: { $0.isPrayer })?.key
        return IrfanEntry(date: Date(), city: city, dateLabel: dateLabel,
                          rows: rows, nextKey: next)
    }

    private func currentMinutes() -> Int {
        let c = Calendar.current.dateComponents([.hour, .minute], from: Date())
        return (c.hour ?? 0) * 60 + (c.minute ?? 0)
    }

    private func fallbackLabel(_ k: String) -> String {
        ["fajr": "Фаджр", "sunrise": "Восход", "dhuhr": "Зухр",
         "asr": "Аср", "maghrib": "Магриб", "isha": "Иша"][k] ?? k
    }

    private func sample() -> [PrayerRow] {
        [PrayerRow(key: "fajr", label: "Фаджр", time: "03:36", mins: 216, isPrayer: true),
         PrayerRow(key: "sunrise", label: "Восход", time: "05:41", mins: 341, isPrayer: false),
         PrayerRow(key: "dhuhr", label: "Зухр", time: "13:09", mins: 789, isPrayer: true),
         PrayerRow(key: "asr", label: "Аср", time: "18:19", mins: 1099, isPrayer: true),
         PrayerRow(key: "maghrib", label: "Магриб", time: "20:34", mins: 1234, isPrayer: true),
         PrayerRow(key: "isha", label: "Иша", time: "22:29", mins: 1349, isPrayer: true)]
    }
}

// Цвета под дизайн приложения.
private let gold = Color(red: 0.88, green: 0.75, blue: 0.44)
private let bgTop = Color(red: 0.06, green: 0.12, blue: 0.10)
private let bgBottom = Color(red: 0.08, green: 0.30, blue: 0.25)
private let cardGreen = Color(red: 0.12, green: 0.42, blue: 0.27)

struct IrfanWidgetEntryView: View {
    @Environment(\.widgetFamily) var family
    var entry: IrfanEntry

    var body: some View {
        Group {
            if family == .systemSmall {
                smallView
            } else {
                mediumView
            }
        }
        .widgetBackground(LinearGradient(colors: [bgTop, bgBottom],
                                         startPoint: .top, endPoint: .bottom))
    }

    private var nextRow: PrayerRow? {
        entry.rows.first(where: { $0.key == entry.nextKey })
    }

    private var smallView: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                Image(systemName: "location.fill").font(.system(size: 9))
                Text(entry.city).font(.system(size: 12, weight: .semibold))
            }.foregroundColor(gold)
            Spacer(minLength: 2)
            Text("Следующий намаз")
                .font(.system(size: 11)).foregroundColor(.white.opacity(0.7))
            Text(nextRow?.label ?? "—")
                .font(.system(size: 20, weight: .bold)).foregroundColor(.white)
            Text(nextRow?.time ?? "—")
                .font(.system(size: 26, weight: .heavy)).foregroundColor(gold)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .padding(14)
    }

    private var mediumView: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                HStack(spacing: 4) {
                    Image(systemName: "location.fill").font(.system(size: 10))
                    Text(entry.city).font(.system(size: 13, weight: .semibold))
                }.foregroundColor(gold)
                Spacer()
                Text(entry.dateLabel)
                    .font(.system(size: 12)).foregroundColor(.white.opacity(0.7))
            }
            HStack(spacing: 6) {
                ForEach(entry.rows) { row in
                    let isNext = row.key == entry.nextKey
                    VStack(spacing: 4) {
                        Text(row.label)
                            .font(.system(size: 10, weight: isNext ? .bold : .regular))
                            .foregroundColor(isNext ? .white : .white.opacity(0.7))
                            .lineLimit(1).minimumScaleFactor(0.7)
                        Text(row.time)
                            .font(.system(size: 14, weight: .bold))
                            .foregroundColor(isNext ? gold : .white)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 10)
                            .fill(isNext ? cardGreen.opacity(0.9) : Color.black.opacity(0.25))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(isNext ? gold : Color.clear, lineWidth: 1.2)
                    )
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .padding(14)
    }
}

extension View {
    @ViewBuilder
    func widgetBackground(_ bg: some View) -> some View {
        if #available(iOSApplicationExtension 17.0, *) {
            containerBackground(for: .widget) { bg }
        } else {
            background(bg)
        }
    }
}

struct IrfanWidget: Widget {
    let kind = "IrfanWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: Provider()) { entry in
            IrfanWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("Времена намаза")
        .description("Времена намаза на сегодня и ближайший намаз.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

@main
struct IrfanWidgetBundle: WidgetBundle {
    var body: some Widget {
        IrfanWidget()
    }
}
