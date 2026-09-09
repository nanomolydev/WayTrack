import SwiftUI

/// Геометрия «колбы»: перевод минут в точки вдоль главной оси.
struct Flask {
    var vertical: Bool
    var size: CGSize
    var range: Range<Int>

    var thickness: CGFloat { vertical ? size.width : size.height }
    /// Полезная длина: закруглённые концы капсулы занимают по радиусу с каждой стороны.
    var cap: CGFloat { thickness / 2 }
    var length: CGFloat { max(1, (vertical ? size.height : size.width) - cap * 2) }
    var pointsPerMinute: CGFloat { length / CGFloat(max(1, range.count)) }

    func offset(_ minute: Int) -> CGFloat {
        cap + CGFloat(minute - range.lowerBound) * pointsPerMinute
    }

    func span(_ minutes: Int) -> CGFloat { CGFloat(minutes) * pointsPerMinute }

    func minutes(_ points: CGFloat) -> Int { Int((points / pointsPerMinute).rounded()) }

    /// Прямоугольник отрезка внутри колбы.
    func rect(start: Int, duration: Int, padding: CGFloat = 0) -> CGRect {
        let a = offset(max(range.lowerBound, start))
        let b = offset(min(range.upperBound, start + duration))
        return vertical
            ? CGRect(x: padding, y: a, width: size.width - padding * 2, height: max(1, b - a))
            : CGRect(x: a, y: padding, width: max(1, b - a), height: size.height - padding * 2)
    }
}

/// Вертикальный режим — «колба жизни»: капсула с закруглёнными концами,
/// метки начала и конца дня — линиями поперёк (см. эскиз).
struct FlaskShell<Content: View>: View {
    var flask: Flask
    @ViewBuilder var content: () -> Content

    var body: some View {
        ZStack(alignment: .topLeading) {
            Capsule().fill(Theme.flask)
            content()
            Capsule().strokeBorder(Theme.flaskEdge, lineWidth: 1)
        }
        .frame(width: flask.size.width, height: flask.size.height)
        .clipShape(Capsule())
        .overlay { Capsule().strokeBorder(Theme.flaskEdge, lineWidth: 1) }
    }
}

/// Черта с подписью времени, выходящая за колбу — граница дня или «сейчас».
struct TimeRule: View {
    var flask: Flask
    var minute: Int
    var color: Color = Theme.faint
    var bold = false

    var body: some View {
        let position = flask.offset(minute)
        Group {
            if flask.vertical {
                HStack(spacing: 6) {
                    Text(clockString(minute))
                        .font(.system(size: 11, weight: bold ? .semibold : .regular, design: .rounded))
                        .foregroundStyle(color)
                        .frame(width: 34, alignment: .trailing)
                    Rectangle().fill(color).frame(height: bold ? 1.5 : 1)
                }
                .frame(width: flask.size.width + 40)
                .offset(x: -40, y: position)
            } else {
                VStack(spacing: 4) {
                    Text(clockString(minute))
                        .font(.system(size: 11, weight: bold ? .semibold : .regular, design: .rounded))
                        .foregroundStyle(color)
                    Rectangle().fill(color).frame(width: bold ? 1.5 : 1)
                }
                .frame(height: flask.size.height + 26)
                .offset(x: position, y: -26)
            }
        }
        .allowsHitTesting(false)
    }
}
