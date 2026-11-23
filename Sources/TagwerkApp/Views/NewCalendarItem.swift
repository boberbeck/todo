import AppKit
import SwiftUI
import TagwerkCore

/// Neue Aufgabe direkt im Kalender: erscheint nach Doppelklick in eine freie Stelle, der Titel wird gleich eingetippt.
/// ↩ legt an (vorbei: als erfasste Zeit, noch offen: als Zeitblock), Esc oder ein leeres Feld bricht ab,
/// „…“ öffnet „Zeit nachtragen“ für eine bestehende Aufgabe, einen Kunden oder genaue Zeiten.
struct NewCalendarItem: View {
    let slot: DateInterval
    let top: CGFloat
    let height: CGFloat
    let commit: (String) -> Void
    let cancel: () -> Void
    let more: (String) -> Void

    @State private var title = ""
    @State private var finished = false
    @State private var appeared = Date.distantFuture
    @FocusState private var focused: Bool

    private var isPast: Bool { slot.start < Date() }

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                TextField(isPast ? "Was gemacht?" : "Was steht an?", text: $title)
                    .textFieldStyle(.plain)
                    .font(.caption.weight(.semibold))
                    .focused($focused)
                    .onSubmit { finish() }
                    .onExitCommand { close(commit: false) }
                Button {
                    close(commit: false, more: true)
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .buttonStyle(.borderless)
                .foregroundStyle(Theme.secondary)
                .help("Bestehende Aufgabe wählen, Kunde oder genaue Zeit …")
            }
            Text("\(clock(slot.start))–\(clock(slot.end)) · ↩ \(isPast ? "erfassen" : "einplanen")")
                .font(.caption2.monospacedDigit())
                .foregroundStyle(Theme.secondary)
                .lineLimit(1)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .frame(minHeight: max(height, 40), alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: 4).fill(Theme.accent.opacity(0.25)))
        .background(RoundedRectangle(cornerRadius: 4).fill(Theme.surface))
        .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(Theme.accent, lineWidth: 1.5))
        .shadow(color: .black.opacity(0.35), radius: 6, y: 2)
        .offset(y: top)
        .onAppear {
            appeared = Date()
            DispatchQueue.main.async { focused = true }
        }
        // Anderer Reiter oder Tag: mit Titel anlegen, sonst verwerfen
        .onDisappear { finish() }
        .onChange(of: focused) {
            // Klick daneben: mit Titel anlegen, ohne Titel verwerfen (kurz warten, falls „…“ geklickt wurde)
            // Nicht beim kurzen Fokuswechsel direkt nach dem Erscheinen und nicht, wenn nur zu einer anderen App gewechselt wurde
            guard !focused else { return }
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(150))
                guard !focused, NSApp.isActive, Date().timeIntervalSince(appeared) > 0.6 else {
                    if NSApp.isActive, !finished { focused = true }
                    return
                }
                finish()
            }
        }
    }

    private func finish() {
        close(commit: !title.trimmingCharacters(in: .whitespaces).isEmpty)
    }

    private func close(commit shouldCommit: Bool, more showMore: Bool = false) {
        guard !finished else { return }
        finished = true
        if showMore {
            more(title)
        } else if shouldCommit {
            commit(title)
        } else {
            cancel()
        }
    }

    private func clock(_ date: Date) -> String {
        date.formatted(date: .omitted, time: .shortened)
    }
}
