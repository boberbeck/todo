import Foundation

/// Ein Stück Text auf einer Webseite mit seiner Lage auf dem Bildschirm (in Punkten, oben links = 0/0).
public struct TextBox: Hashable, Sendable, Codable {
    public var text: String
    public var x: Double
    public var y: Double
    public var width: Double
    public var height: Double

    public init(text: String, x: Double, y: Double, width: Double, height: Double) {
        self.text = text
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }

    var midY: Double { y + height / 2 }
    var right: Double { x + width }
}

/// Baut aus Text-Schnipseln eine Tabelle, so wie ein Mensch sie auf dem Bildschirm sieht:
/// Schnipsel auf gleicher Höhe sind eine Zeile, die Spalten kommen aus der Lage der Überschriften.
/// So stört es nicht, wenn die Seite die Tabelle intern in mehrere Teile zerlegt (feste und scrollbare Spalten).
public enum LayoutTable {
    public static func cells(from boxes: [TextBox]) -> [[String]] {
        let clean = boxes
            .map { box -> TextBox in
                var copy = box
                copy.text = box.text
                    .replacingOccurrences(of: "\u{00A0}", with: " ")
                    .components(separatedBy: .whitespacesAndNewlines)
                    .filter { !$0.isEmpty }
                    .joined(separator: " ")
                return copy
            }
            .filter { !$0.text.isEmpty && $0.width > 0 && $0.height > 0 }
        guard !clean.isEmpty else { return [] }

        let lines = group(clean)
        guard let header = headerLine(in: lines) else {
            // Ohne Überschriften: jede Zeile in Zellen nach Abständen
            return lines.map { line in mergeByGap(line.boxes, factor: 0.5).map(\.text) }
        }

        let labels = mergeByGap(lines[header].boxes, factor: 0.5)
        let anchors = labels.map(\.x)
        var result: [[String]] = [labels.map(\.text)]
        var previousMidY: Double?
        var previousHasID = false
        for line in lines.dropFirst(header + 1) {
            var byColumn = Array(repeating: [TextBox](), count: anchors.count)
            for box in line.boxes {
                byColumn[column(of: box, anchors: anchors)].append(box)
            }
            let row = byColumn.map(joinedText)
            let hasID = row.contains { SAPImport.firstTaskID(in: $0) != nil }
            // Umbrochener Text gehört noch zur Zeile darüber.
            if !hasID, previousHasID, let previousMidY, line.midY - previousMidY < 1.3 * line.height, var last = result.popLast() {
                for (index, value) in row.enumerated() where !value.isEmpty {
                    last[index] = last[index].isEmpty ? value : last[index] + " " + value
                }
                result.append(last)
                previousMidY = line.midY
                continue
            }
            result.append(row)
            previousMidY = line.midY
            previousHasID = hasID
        }
        return result
    }

    struct Line {
        var boxes: [TextBox]
        var midY: Double
        var height: Double
    }

    /// Schnipsel auf gleicher Höhe zu Zeilen zusammenfassen, von oben nach unten.
    static func group(_ boxes: [TextBox]) -> [Line] {
        var lines: [Line] = []
        for box in boxes.sorted(by: { $0.midY < $1.midY }) {
            if var last = lines.last, abs(box.midY - last.midY) <= max(3, 0.5 * min(box.height, last.height)) {
                last.boxes.append(box)
                last.midY = last.boxes.map(\.midY).reduce(0, +) / Double(last.boxes.count)
                last.height = last.boxes.map(\.height).sorted()[last.boxes.count / 2]
                lines[lines.count - 1] = last
            } else {
                lines.append(Line(boxes: [box], midY: box.midY, height: box.height))
            }
        }
        return lines
    }

    /// Die Zeile mit den meisten bekannten Spaltenüberschriften (Task ID, Activity, Aufgabenname …).
    static func headerLine(in lines: [Line]) -> Int? {
        var best: (index: Int, score: Int)?
        for (index, line) in lines.enumerated() {
            let labels = mergeByGap(line.boxes, factor: 0.5).map(\.text)
            guard labels.count >= 2, !labels.contains(where: { SAPImport.firstTaskID(in: $0) != nil }) else { continue }
            let columns = SAPImport.Columns(header: labels)
            let score = columns.recognized + (columns.code != nil ? 1 : 0)
            guard columns.recognized >= 2 || columns.code != nil else { continue }
            if score > (best?.score ?? 0) { best = (index, score) }
        }
        return best?.index
    }

    /// Spalte eines Schnipsels: die letzte Überschrift, die links davon beginnt (mit etwas Spielraum,
    /// falls Überschriften etwas eingerückt sind).
    static func column(of box: TextBox, anchors: [Double]) -> Int {
        var result = 0
        for index in anchors.indices {
            let previousWidth = index > 0 ? anchors[index] - anchors[index - 1] : 40
            let tolerance = max(6, min(0.4 * previousWidth, 60))
            if box.x >= anchors[index] - tolerance { result = index }
        }
        return result
    }

    /// Text einer Zelle von links nach rechts; direkt aneinanderstoßende Stücke ohne Leerzeichen.
    static func joinedText(_ boxes: [TextBox]) -> String {
        var text = ""
        var previous: TextBox?
        for box in boxes.sorted(by: { $0.x < $1.x }) {
            if let previous {
                text += box.x - previous.right <= 1.5 ? box.text : " " + box.text
            } else {
                text = box.text
            }
            previous = box
        }
        return text
    }

    /// Nebeneinander liegende Schnipsel mit kleinem Abstand gehören zu einer Zelle („CPSO“ + „8643-6“).
    static func mergeByGap(_ boxes: [TextBox], factor: Double) -> [TextBox] {
        var result: [TextBox] = []
        for box in boxes.sorted(by: { $0.x < $1.x }) {
            if var last = result.last {
                let gap = box.x - last.right
                if gap <= 1.5 {
                    last.text += box.text
                } else if gap < factor * min(box.height, last.height) {
                    last.text += " " + box.text
                } else {
                    result.append(box)
                    continue
                }
                let right = max(last.right, box.right)
                last.width = right - last.x
                result[result.count - 1] = last
            } else {
                result.append(box)
            }
        }
        return result
    }
}
