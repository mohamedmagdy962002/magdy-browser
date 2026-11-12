import SwiftUI
import WidgetKit

struct MagdyEntry: TimelineEntry {
    let date: Date
}

struct MagdyWidgetView: View {
    let entry: MagdyEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Magdy Browser")
                .font(.headline)
            Text("Free · Unlimited · No subscription")
                .font(.caption2)
                .foregroundColor(.secondary)
            Spacer(minLength: 0)
            Text("Open Magdy")
                .font(.caption)
                .foregroundColor(.accentColor)
        }
        .widgetURL(URL(string: "magdy://open"))
    }
}

struct MagdyWidget: Widget {
    let kind = "MagdyWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: Provider()) { entry in
            MagdyWidgetView(entry: entry)
        }
        .configurationDisplayName("Magdy Browser")
        .description("Quick access to Magdy Browser.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }

    struct Provider: TimelineProvider {
        func placeholder(in context: Context) -> MagdyEntry {
            MagdyEntry(date: Date())
        }

        func getSnapshot(in context: Context, completion: @escaping (MagdyEntry) -> Void) {
            completion(MagdyEntry(date: Date()))
        }

        func getTimeline(in context: Context, completion: @escaping (Timeline<MagdyEntry>) -> Void) {
            completion(Timeline(entries: [MagdyEntry(date: Date())], policy: .never))
        }
    }
}

@main
struct MagdyWidgetBundle: WidgetBundle {
    var body: some Widget {
        MagdyWidget()
    }
}
