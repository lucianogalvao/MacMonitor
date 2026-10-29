// Desenha o ícone do app em 1024x1024.
// Uso: swift Scripts/make-icon.swift <saida.png>   (ou rode Scripts/make-icon.sh)
import AppKit

let size = 1024
let output = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "icon.png"

let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
let ctx = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
                    space: colorSpace, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!

func rgb(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> CGColor {
    CGColor(colorSpace: colorSpace, components: [r, g, b, a])!
}

func degrees(_ value: CGFloat) -> CGFloat { value * .pi / 180 }

// Grade de ícones do macOS: forma de 824 pt centralizada, cantos de ~185 pt
let shape = CGRect(x: 100, y: 100, width: 824, height: 824)
let shapePath = CGPath(roundedRect: shape, cornerWidth: 185, cornerHeight: 185, transform: nil)

// Sombra
ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -12), blur: 28, color: rgb(0, 0, 0, 0.35))
ctx.addPath(shapePath)
ctx.setFillColor(rgb(0.06, 0.09, 0.2))
ctx.fillPath()
ctx.restoreGState()

ctx.saveGState()
ctx.addPath(shapePath)
ctx.clip()

// Fundo: azul-escuro, um pouco mais claro em cima
let background = CGGradient(colorsSpace: colorSpace,
                            colors: [rgb(0.15, 0.24, 0.45), rgb(0.04, 0.07, 0.17)] as CFArray,
                            locations: [0, 1])!
ctx.drawLinearGradient(background, start: CGPoint(x: 512, y: 924), end: CGPoint(x: 512, y: 100), options: [])

// Medidor: arco de 270°, de baixo-esquerda até baixo-direita passando pelo topo
let center = CGPoint(x: 512, y: 480)
let radius: CGFloat = 270
let lineWidth: CGFloat = 58
let startAngle = degrees(225)
let sweep = degrees(270)

ctx.setLineCap(.round)
ctx.setLineWidth(lineWidth)
ctx.setStrokeColor(rgb(1, 1, 1, 0.12))
ctx.addArc(center: center, radius: radius, startAngle: startAngle, endAngle: startAngle - sweep, clockwise: true)
ctx.strokePath()

// Parte preenchida: gradiente ciano → verde → laranja, desenhado em segmentos
let stops: [(CGFloat, (CGFloat, CGFloat, CGFloat))] = [
    (0.0, (0.25, 0.82, 1.0)),
    (0.5, (0.35, 0.9, 0.55)),
    (1.0, (1.0, 0.62, 0.22)),
]

func color(at t: CGFloat) -> CGColor {
    for i in 1..<stops.count where t <= stops[i].0 {
        let (t0, c0) = stops[i - 1], (t1, c1) = stops[i]
        let f = (t - t0) / (t1 - t0)
        return rgb(c0.0 + (c1.0 - c0.0) * f, c0.1 + (c1.1 - c0.1) * f, c0.2 + (c1.2 - c0.2) * f)
    }
    let last = stops[stops.count - 1].1
    return rgb(last.0, last.1, last.2)
}

let progress: CGFloat = 0.7
let segments = 160
for i in 0..<segments {
    let t0 = CGFloat(i) / CGFloat(segments)
    let t1 = CGFloat(i + 1) / CGFloat(segments)
    ctx.setStrokeColor(color(at: t0))
    ctx.addArc(center: center, radius: radius,
               startAngle: startAngle - sweep * progress * t0,
               endAngle: startAngle - sweep * progress * t1,
               clockwise: true)
    ctx.strokePath()
}

// Linha de pulso no centro do medidor
let pulse: [CGPoint] = [
    CGPoint(x: 342, y: 470), CGPoint(x: 432, y: 470), CGPoint(x: 470, y: 570),
    CGPoint(x: 522, y: 370), CGPoint(x: 566, y: 520), CGPoint(x: 594, y: 470),
    CGPoint(x: 682, y: 470),
]
ctx.setStrokeColor(rgb(1, 1, 1))
ctx.setLineWidth(30)
ctx.setLineJoin(.round)
ctx.addLines(between: pulse)
ctx.strokePath()

ctx.restoreGState()

let image = ctx.makeImage()!
let destination = CGImageDestinationCreateWithURL(URL(fileURLWithPath: output) as CFURL, "public.png" as CFString, 1, nil)!
CGImageDestinationAddImage(destination, image, nil)
CGImageDestinationFinalize(destination)
print("Ícone salvo em \(output)")
