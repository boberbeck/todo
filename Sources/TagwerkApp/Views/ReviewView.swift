import SwiftUI
import TagwerkCore

/// Wochenrückblick: Stunden je Tag und je Kunde.
struct ReviewView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let monday = model.today.startOfWeek()
        let days = (0..<7).map { monday.adding(days: $0) }
        let byCustomer = model.trackedByCustomer(from: monday, through: monday.adding(days: 6))
        let weekTotal = byCustomer.reduce(0) { $0 + $1.seconds }

        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Wochenrückblick")
                        .font(.title2.weight(.semibold))
                    Text("Woche ab \(monday.startDate().formatted(date: .abbreviated, time: .omitted)) · \(TimeMath.format(weekTotal)) h erfasst")
                        .foregroundStyle(.secondary)
                }

                GroupBox("Nach Tag") {
                    Grid(alignment: .leading, horizontalSpacing: 24, verticalSpacing: 8) {
                        ForEach(days, id: \.self) { day in
                            GridRow {
                                Text(day.startDate().formatted(.dateTime.weekday(.wide)))
                                    .fontWeight(day == model.today ? .semibold : .regular)
                                Text("\(TimeMath.format(model.tracked(on: day))) h")
                                    .monospacedDigit()
                                Text("\(model.doneCount(on: day)) erledigt")
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(8)
                }

                GroupBox("Nach Kunde") {
                    if byCustomer.isEmpty {
                        Text("Diese Woche ist noch keine Zeit erfasst.")
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(8)
                    } else {
                        Grid(alignment: .leading, horizontalSpacing: 24, verticalSpacing: 8) {
                            ForEach(byCustomer, id: \.customerID) { row in
                                let customer = model.customer(row.customerID)
                                GridRow {
                                    HStack(spacing: 6) {
                                        CustomerDot(colorIndex: customer?.colorIndex ?? 0)
                                            .opacity(customer == nil ? 0 : 1)
                                        Text(customer?.name ?? "Ohne Kunde")
                                    }
                                    Text("\(TimeMath.format(row.seconds)) h")
                                        .monospacedDigit()
                                }
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(8)
                    }
                }
            }
            .padding(24)
            .frame(maxWidth: 720, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .navigationTitle("Rückblick")
    }
}
