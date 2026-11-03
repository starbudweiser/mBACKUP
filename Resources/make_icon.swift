// Génère l'icône (1024 px) : carré arrondi sombre Socle, anneau fléché turquoise et deux disques empilés.
import Cocoa
let size: CGFloat = 1024
let img = NSImage(size: NSSize(width: size, height: size))
img.lockFocus()
NSColor(srgbRed: 0.13, green: 0.13, blue: 0.13, alpha: 1).setFill()
NSBezierPath(roundedRect: NSRect(x: 100, y: 100, width: size - 200, height: size - 200), xRadius: 185, yRadius: 185).fill()
let teal = NSColor(srgbRed: 0x2d/255, green: 0xd4/255, blue: 0xbf/255, alpha: 1)
let c = NSPoint(x: size / 2, y: size / 2), r: CGFloat = 270
// Anneau ouvert (de 40° à 330°, sens antihoraire) terminé par une pointe de flèche
let ring = NSBezierPath()
ring.appendArc(withCenter: c, radius: r, startAngle: 40, endAngle: 325, clockwise: false)
ring.lineWidth = 58; ring.lineCapStyle = .butt
teal.setStroke(); ring.stroke()
let a = 325 * CGFloat.pi / 180
let end = NSPoint(x: c.x + r * cos(a), y: c.y + r * sin(a))
let dir = a + CGFloat.pi / 2                       // tangente dans le sens du tracé
let ux = cos(dir), uy = sin(dir), px = -uy, py = ux
let head = NSBezierPath()
head.move(to: NSPoint(x: end.x + 105 * ux, y: end.y + 105 * uy))
head.line(to: NSPoint(x: end.x + 85 * px, y: end.y + 85 * py))
head.line(to: NSPoint(x: end.x - 85 * px, y: end.y - 85 * py))
head.close(); teal.setFill(); head.fill()
// Deux disques empilés
NSColor(white: 0.9, alpha: 1).setFill()
for dy in [-62.0, 62.0] {
    NSBezierPath(roundedRect: NSRect(x: c.x - 150, y: c.y + dy - 38, width: 300, height: 76), xRadius: 30, yRadius: 30).fill()
}
img.unlockFocus()
let rep = NSBitmapImageRep(data: img.tiffRepresentation!)!
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
