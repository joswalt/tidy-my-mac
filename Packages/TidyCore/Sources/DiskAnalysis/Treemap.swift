import CoreGraphics
import Foundation

/// Squarified treemap layout (Bruls, Huizing and van Wijk, 2000), our own code (build spec §6.8).
/// Each value gets a rectangle whose area is proportional to it, with aspect ratios kept close to 1.
public enum Treemap {
    /// Rectangles in the same order as `values`. Zero or negative values get `.zero`.
    public static func layout(_ values: [Double], in rect: CGRect) -> [CGRect] {
        var out = [CGRect](repeating: .zero, count: values.count)
        let order = values.indices.filter { values[$0] > 0 }.sorted { values[$0] > values[$1] }
        let total = order.reduce(0.0) { $0 + values[$1] }
        guard total > 0, rect.width > 0, rect.height > 0 else { return out }
        let scale = Double(rect.width * rect.height) / total
        let areas = order.map { values[$0] * scale }

        var remaining = rect
        var start = 0
        while start < areas.count {
            let side = Double(min(remaining.width, remaining.height))
            var end = start + 1
            var current = worst(areas[start..<end], side: side)
            while end < areas.count {
                let next = worst(areas[start...end], side: side)
                if next > current { break }
                current = next
                end += 1
            }
            let row = areas[start..<end]
            let rowArea = row.reduce(0, +)
            if remaining.width >= remaining.height {
                // A column on the left.
                let w = side > 0 ? min(Double(remaining.width), rowArea / Double(remaining.height)) : 0
                var y = Double(remaining.minY)
                for (k, a) in row.enumerated() {
                    let h = w > 0 ? a / w : 0
                    let isLast = k == row.count - 1
                    let height = isLast ? Double(remaining.maxY) - y : h
                    out[order[start + k]] = CGRect(x: Double(remaining.minX), y: y, width: w, height: max(0, height))
                    y += h
                }
                remaining = CGRect(x: remaining.minX + w, y: remaining.minY, width: max(0, remaining.width - w), height: remaining.height)
            } else {
                // A row along the top.
                let h = side > 0 ? min(Double(remaining.height), rowArea / Double(remaining.width)) : 0
                var x = Double(remaining.minX)
                for (k, a) in row.enumerated() {
                    let w = h > 0 ? a / h : 0
                    let isLast = k == row.count - 1
                    let width = isLast ? Double(remaining.maxX) - x : w
                    out[order[start + k]] = CGRect(x: x, y: Double(remaining.minY), width: max(0, width), height: h)
                    x += w
                }
                remaining = CGRect(x: remaining.minX, y: remaining.minY + h, width: remaining.width, height: max(0, remaining.height - h))
            }
            start = end
        }
        return out
    }

    /// The worst aspect ratio in a row laid along a side of length `side`.
    static func worst(_ row: ArraySlice<Double>, side: Double) -> Double {
        let s = row.reduce(0, +)
        guard s > 0, side > 0, let mx = row.max(), let mn = row.min(), mn > 0 else { return .infinity }
        let side2 = side * side, s2 = s * s
        return max(side2 * mx / s2, s2 / (side2 * mn))
    }
}
