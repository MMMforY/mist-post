// Run with: swift Tools/Icon.swift Resources/Postage.jpg <temporary iconset directory>
import AppKit

let args = CommandLine.arguments
guard args.count == 3, let atlas = NSImage(contentsOfFile:args[1]) else { exit(2) }
let folder = URL(fileURLWithPath:args[2],isDirectory:true)
try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true)
let srgb = CGColorSpace(name:CGColorSpace.sRGB)!
let dark = CGColor(srgbRed:0.045,green:0.17,blue:0.18,alpha:1)
let sage = CGColor(srgbRed:0.14,green:0.33,blue:0.34,alpha:1)
let paper = CGColor(srgbRed:0.97,green:0.89,blue:0.72,alpha:1)
var src = CGRect(origin:.zero,size:atlas.size)
let art = atlas.cgImage(forProposedRect:&src,context:nil,hints:nil)!
let w = art.width/4, h = art.height/3
let plate = art.cropping(to:CGRect(x:3*w+3,y:2*h+3,width:w-6,height:h-6))!
for size in [16,32,128,256,512] {
    for ratio in [1,2] {
        let px = size*ratio
        let ctx = CGContext(data:nil,width:px,height:px,bitsPerComponent:8,bytesPerRow:0,
                            space:srgb,bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.scaleBy(x:CGFloat(px)/1024,y:CGFloat(px)/1024)
        ctx.interpolationQuality = .high
        let squircle = CGPath(roundedRect:CGRect(x:73,y:74,width:878,height:878),
                              cornerWidth:200,cornerHeight:200,transform:nil)
        ctx.saveGState()
        ctx.setShadow(offset:CGSize(width:0,height:-13),blur:22,color:dark)
        ctx.setFillColor(dark); ctx.addPath(squircle); ctx.fillPath()
        ctx.restoreGState()
        ctx.addPath(squircle); ctx.clip()
        let gradient = CGGradient(colorsSpace:srgb,colors:[sage,dark] as CFArray,locations:[0,1])!
        ctx.drawLinearGradient(gradient,start:CGPoint(x:150,y:949),end:CGPoint(x:905,y:90),options:[])
        ctx.translateBy(x:516,y:522)
        ctx.rotate(by:0.10)
        let stamp = CGRect(x:-283,y:-302,width:566,height:604)
        ctx.setFillColor(paper)
        ctx.fill(stamp)
        for x in stride(from:-275,through:275,by:35) {
            for y in [-302,302] { ctx.fillEllipse(in:CGRect(x:x-13,y:y-13,width:26,height:26)) }
        }
        for y in stride(from:-290,through:291,by:35) {
            for x in [-283,283] { ctx.fillEllipse(in:CGRect(x:x-13,y:y-13,width:26,height:26)) }
        }
        let field = stamp.insetBy(dx:26,dy:30)
        ctx.setStrokeColor(dark); ctx.setLineWidth(6); ctx.stroke(field)
        ctx.draw(plate,in:field.insetBy(dx:8,dy:8))
        let rep = NSBitmapImageRep(cgImage:ctx.makeImage()!)
        let file = "icon_\(size)x\(size)"+(ratio==2 ? "@2x" : "")+".png"
        try rep.representation(using:.png,properties:[:])!.write(to:folder.appendingPathComponent(file))
    }
}
