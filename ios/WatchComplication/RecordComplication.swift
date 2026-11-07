import SwiftUI
import WidgetKit

/// A watch-face button that opens Clear Notes and starts recording.
@main
struct ClearNotesComplications: WidgetBundle {
    var body: some Widget {
        RecordComplication()
    }
}

struct RecordComplication: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "ClearNotesRecord", provider: RecordProvider()) { _ in
            RecordComplicationView()
        }
        .configurationDisplayName("Record")
        .description("Starts a Clear Notes recording on your watch.")
        .supportedFamilies([.accessoryCircular, .accessoryCorner, .accessoryRectangular, .accessoryInline])
    }
}

struct RecordEntry: TimelineEntry {
    let date: Date
}

/// The button never changes, so there's one entry and no updates.
struct RecordProvider: TimelineProvider {
    func placeholder(in context: Context) -> RecordEntry {
        RecordEntry(date: .now)
    }

    func getSnapshot(in context: Context, completion: @escaping (RecordEntry) -> Void) {
        completion(RecordEntry(date: .now))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<RecordEntry>) -> Void) {
        completion(Timeline(entries: [RecordEntry(date: .now)], policy: .never))
    }
}

struct RecordComplicationView: View {
    @Environment(\.widgetFamily) private var family

    var body: some View {
        content
            .widgetURL(URL(string: "clearnotes-watch://record"))
            .containerBackground(for: .widget) { Color.clear }
    }

    @ViewBuilder
    private var content: some View {
        switch family {
        case .accessoryCorner:
            Image(systemName: "mic.fill")
                .font(.title2)
                .widgetLabel("Record")
        case .accessoryInline:
            Label("Record", systemImage: "mic.fill")
        case .accessoryRectangular:
            HStack(spacing: 8) {
                Image(systemName: "mic.circle.fill")
                    .font(.title)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Clear Notes")
                        .font(.headline)
                    Text("Tap to record")
                        .font(.caption)
                }
                Spacer(minLength: 0)
            }
        default:
            ZStack {
                AccessoryWidgetBackground()
                Image(systemName: "mic.fill")
                    .font(.title3)
            }
        }
    }
}
