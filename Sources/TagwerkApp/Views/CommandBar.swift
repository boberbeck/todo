import SwiftUI
import TagwerkCore

/// Die Befehlszeile (⌘K): eine Zeile für alles, was man sonst über mehrere Knöpfe erledigt.
/// Man tippt in normalem Deutsch, was man tut; darunter steht, was ↩ macht. ↑↓ wählt, Esc schließt.
struct CommandBar: View {
    @Environment(AppModel.self) private var model
    @FocusState private var focused: Bool
    @State private var selected = 0
    @State private var hovered: String?

    private let examples = ["45m Telefonat", "seit 9:30 Angebot", "morgen Bericht 30m", "Mittag", "fertig", "Kalender"]

    var body: some View {
        @Bindable var model = model
        let suggestions = model.commandSuggestions(for: model.commandQuery)
        let shape = RoundedRectangle(cornerRadius: Theme.Radius.panel, style: .continuous)

        VStack(spacing: 0) {
            HStack(spacing: 12) {
                SunMark(size: 16)
                    .padding(.top, 6)
                TextField("", text: $model.commandQuery, prompt: Text("Was tust du gerade?").foregroundColor(Theme.tertiary))
                    .textFieldStyle(.plain)
                    .font(.system(size: 20))
                    .foregroundStyle(Theme.text)
                    .focused($focused)
                    .onSubmit { run(suggestions) }
                    .onKeyPress(.downArrow) {
                        selected = min(selected + 1, max(0, suggestions.count - 1))
                        return .handled
                    }
                    .onKeyPress(.upArrow) {
                        selected = max(selected - 1, 0)
                        return .handled
                    }
                    .onExitCommand { model.showsCommandBar = false }
                Text("esc")
                    .font(.caption.monospaced())
                    .foregroundStyle(Theme.tertiary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(Theme.border))
            }
            .padding(.horizontal, 20)
            .frame(height: 60)

            Rectangle().fill(Theme.border).frame(height: 1)

            if suggestions.isEmpty {
                Text("Nichts gefunden. Tipp einen Titel, eine Dauer wie „30m …“ oder „seit 9 Uhr …“.")
                    .font(.callout)
                    .foregroundStyle(Theme.tertiary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(20)
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(spacing: 2) {
                            ForEach(Array(suggestions.enumerated()), id: \.element.id) { index, suggestion in
                                CommandRow(suggestion: suggestion, selected: index == selected)
                                    .id(suggestion.id)
                                    .contentShape(Rectangle())
                                    .onTapGesture { model.perform(suggestion.action) }
                                    .onHover { inside in
                                        if inside { selected = index }
                                    }
                            }
                        }
                        .padding(8)
                    }
                    .frame(maxHeight: 400)
                    .fixedSize(horizontal: false, vertical: true)
                    .onChange(of: selected) {
                        if suggestions.indices.contains(selected) {
                            proxy.scrollTo(suggestions[selected].id)
                        }
                    }
                }
            }

            Rectangle().fill(Theme.border).frame(height: 1)

            // Beispiele: ein Klick füllt die Zeile
            HStack(spacing: 6) {
                Text("Probier")
                    .font(.caption)
                    .foregroundStyle(Theme.tertiary)
                ForEach(examples, id: \.self) { example in
                    Button {
                        model.commandQuery = example
                        focused = true
                    } label: {
                        Text(example)
                            .font(.caption.weight(.medium))
                            .foregroundStyle(Theme.secondary)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(Capsule().fill(Color.white.opacity(0.05)))
                            .overlay(Capsule().strokeBorder(Theme.border))
                    }
                    .buttonStyle(.plain)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
        .frame(width: 640)
        .background(shape.fill(Theme.surfaceFloating))
        .clipShape(shape)
        .surface(radius: Theme.Radius.panel, elevation: .floating, fill: Theme.surfaceFloating)
        .onAppear {
            selected = 0
            DispatchQueue.main.async { focused = true }
        }
        .onChange(of: model.commandQuery) { selected = 0 }
    }

    private func run(_ suggestions: [CommandSuggestion]) {
        guard suggestions.indices.contains(selected) else { return }
        model.perform(suggestions[selected].action)
    }
}

/// Eine Zeile in der Befehlszeile: Symbol, was passiert, und ↩ bei der gewählten.
struct CommandRow: View {
    let suggestion: CommandSuggestion
    let selected: Bool

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: suggestion.symbol)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(selected ? Theme.accent : Theme.secondary)
                .frame(width: 30, height: 30)
                .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.white.opacity(selected ? 0.08 : 0.04)))
            VStack(alignment: .leading, spacing: 2) {
                Text(suggestion.title)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Theme.text)
                    .lineLimit(1)
                Text(suggestion.detail)
                    .font(.caption)
                    .foregroundStyle(Theme.tertiary)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            if selected {
                Text("↩")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Theme.secondary)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(
            RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous)
                .fill(selected ? Theme.surfaceRaised : Color.clear)
        )
    }
}

/// Knopf in der Titelleiste: öffnet die Befehlszeile. Schmal (Lupe und ⌘K), damit Timer und Einstellungen
/// auch bei kleinem Fenster in der Leiste bleiben.
struct CommandBarButton: View {
    @Environment(AppModel.self) private var model
    @State private var hovering = false

    var body: some View {
        Button {
            model.openCommandBar()
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 12, weight: .medium))
                Text("⌘K")
                    .font(.system(size: 12, weight: .medium, design: .rounded))
            }
            .foregroundStyle(hovering ? Theme.text : Theme.secondary)
            .padding(.horizontal, 10)
            .frame(height: 28)
            .background(Capsule().fill(Color.white.opacity(hovering ? 0.08 : 0.04)))
            .overlay(Capsule().strokeBorder(Theme.border))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help("Was jetzt? Befehlszeile: starten, nachtragen, anlegen, Mittagspause, krank … in einer Zeile (⌘K)")
    }
}

/// Rückmeldung unten im Fenster, verschwindet von selbst.
struct ToastView: View {
    @Environment(AppModel.self) private var model
    let toast: Toast

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: toast.symbol)
                .foregroundStyle(Theme.accent)
            Text(toast.text)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Theme.text)
                .lineLimit(1)
        }
        .padding(.horizontal, 16)
        .frame(height: 38)
        .background(Capsule().fill(Theme.surfaceFloating))
        .overlay(Capsule().strokeBorder(Theme.borderStrong))
        .shadow(color: .black.opacity(0.45), radius: 18, y: 8)
        .onTapGesture { model.dismissToast() }
    }
}
