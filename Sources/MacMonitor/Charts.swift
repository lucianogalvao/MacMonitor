import SwiftUI
import Charts

/// Gráfico de linha compacto para históricos (sem eixos).
struct Sparkline: View {
    let values: [Double]
    var maxValue: Double? = nil
    var color: Color = .accentColor
    var height: CGFloat = 36

    var body: some View {
        Chart(Array(values.enumerated()), id: \.offset) { item in
            AreaMark(x: .value("t", item.offset), y: .value("v", item.element))
                .foregroundStyle(color.opacity(0.2))
                .interpolationMethod(.monotone)
            LineMark(x: .value("t", item.offset), y: .value("v", item.element))
                .foregroundStyle(color)
                .lineStyle(StrokeStyle(lineWidth: 1.5))
                .interpolationMethod(.monotone)
        }
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
        .chartXScale(domain: 0...(SystemMonitor.historyLength - 1))
        .chartYScale(domain: 0...(maxValue ?? max(values.max() ?? 1, 1)))
        .frame(height: height)
    }
}

/// Duas séries na mesma escala (download em verde, upload em laranja).
struct DualSparkline: View {
    let first: [Double]
    let second: [Double]

    var body: some View {
        let peak = max(first.max() ?? 0, second.max() ?? 0, 1)
        Chart {
            ForEach(Array(first.enumerated()), id: \.offset) { item in
                LineMark(x: .value("t", item.offset), y: .value("v", item.element), series: .value("s", "down"))
                    .foregroundStyle(.green)
            }
            ForEach(Array(second.enumerated()), id: \.offset) { item in
                LineMark(x: .value("t", item.offset), y: .value("v", item.element), series: .value("s", "up"))
                    .foregroundStyle(.orange)
            }
        }
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
        .chartXScale(domain: 0...(SystemMonitor.historyLength - 1))
        .chartYScale(domain: 0...peak)
        .frame(height: 36)
    }
}
