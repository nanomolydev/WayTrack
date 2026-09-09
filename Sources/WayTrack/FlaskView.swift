import SwiftUI

/// Геометрия полотна: перевод минут в точки вдоль главной оси.
/// Вертикаль — «колба» (капсула), горизонталь — обычная лента таймлайна.
struct Flask {
    var vertical: Bool
    var size: CGSize
    var range: Range<Int>

    var thickness: CGFloat { vertical ? size.width : size.height }
    /// В капсуле закруглённые концы съедают по радиусу с каждой стороны.
    var cap: CGFloat { vertical ? thickness / 2 : 0 }
    var length: CGFloat { max(1, (vertical ? size.height : size.width) - cap * 2) }
    var pointsPerMinute: CGFloat { length / CGFloat(max(1, range.count)) }

    func offset(_ minute: Int) -> CGFloat {
        cap + CGFloat(minute - range.lowerBound) * pointsPerMinute
    }

    func span(_ minutes: Int) -> CGFloat { CGFloat(minutes) * pointsPerMinute }

    func minutes(_ points: CGFloat) -> Int { Int((points / pointsPerMinute).rounded()) }

    /// Минута под точкой полотна — для тапа по пустому месту.
    func minute(at points: CGFloat) -> Int {
        range.lowerBound + Int(((points - cap) / pointsPerMinute).rounded())
    }

    func rect(start: Int, duration: Int, padding: CGFloat = 0) -> CGRect {
        let a = offset(max(range.lowerBound, start))
        let b = offset(min(range.upperBound, start + duration))
        return vertical
            ? CGRect(x: padding, y: a, width: size.width - padding * 2, height: max(2, b - a))
            : CGRect(x: a, y: padding, width: max(2, b - a), height: size.height - padding * 2)
    }

    /// Шаг подписей шкалы: чем крупнее масштаб, тем чаще деления.
    var ruleStep: Int {
        let perHour = pointsPerMinute * 60
        if perHour > 260 { return 15 }
        if perHour > 120 { return 30 }
        if perHour > 45 { return 60 }
        return 180
    }
}

struct FlaskShell<Content: View>: View {
    var flask: Flask
    @ViewBuilder var content: () -> Content

    private var shape: AnyShape {
        flask.vertical ? AnyShape(Capsule()) : AnyShape(RoundedRectangle(cornerRadius: 14))
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            shape.fill(Theme.flask)
            content()
        }
        .frame(width: flask.size.width, height: flask.size.height, alignment: .topLeading)
        .clipShape(shape)
        .overlay { shape.stroke(Theme.flaskEdge, lineWidth: 1) }
    }
}

/// Шкала времени: деления вдоль полотна с подписями.
struct TimeScale: View {
    var flask: Flask

    private var marks: [Int] {
        stride(from: flask.range.lowerBound - flask.range.lowerBound % flask.ruleStep,
               to: flask.range.upperBound, by: flask.ruleStep)
            .filter { $0 >= flask.range.lowerBound }
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            ForEach(marks, id: \.self) { minute in
                let hour = minute % 60 == 0
                if flask.vertical {
                    HStack(spacing: 6) {
                        Text(clockString(minute))
                            .font(.system(size: 10, design: .rounded))
                            .foregroundStyle(Theme.faint)
                            .frame(width: 36, alignment: .trailing)
                        Rectangle()
                            .fill(Theme.flaskEdge.opacity(hour ? 1 : 0.5))
                            .frame(height: 1)
                    }
                    .frame(width: flask.size.width + 42, alignment: .leading)
                    .offset(x: -42, y: flask.offset(minute))
                } else {
                    VStack(spacing: 3) {
                        Rectangle()
                            .fill(Theme.flaskEdge.opacity(hour ? 1 : 0.5))
                            .frame(width: 1)
                        Text(clockString(minute))
                            .font(.system(size: 10, design: .rounded))
                            .foregroundStyle(Theme.faint)
                            .fixedSize()
                    }
                    .frame(height: flask.size.height + 18, alignment: .top)
                    .offset(x: flask.offset(minute), y: 0)
                }
            }
        }
        .allowsHitTesting(false)
    }
}

/// Черта «сейчас».
struct NowRule: View {
    var flask: Flask
    var minute: Int

    var body: some View {
        let color = Color(hex: "FF375F")
        Group {
            if flask.vertical {
                Rectangle().fill(color).frame(width: flask.size.width, height: 1.5)
                    .offset(y: flask.offset(minute))
            } else {
                Rectangle().fill(color).frame(width: 1.5, height: flask.size.height)
                    .offset(x: flask.offset(minute))
            }
        }
        .allowsHitTesting(false)
    }
}
