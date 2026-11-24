import AppKit
import ImageIO

enum PressImages {
    static func decoded(_ url: URL) -> CGImage? {
        guard let src = CGImageSourceCreateWithURL(url as CFURL,nil) else { return nil }
        let options = [kCGImageSourceShouldCacheImmediately:true] as CFDictionary
        return CGImageSourceCreateImageAtIndex(src,0,options)
    }
    static func photo(_ url: URL) -> NSImage? {
        decoded(url).map { NSImage(cgImage:$0,size:NSSize(width:$0.width,height:$0.height)) }
    }
    static func stamps(_ url: URL) -> [NSImage] {
        guard let sheet = decoded(url) else { return [] }
        let w = sheet.width/4, h = sheet.height/3
        return (0..<12).compactMap { i in
            let r = CGRect(x:(i%4)*w+2,y:(i/4)*h+2,width:w-4,height:h-4)
            guard let art = sheet.cropping(to:r) else { return nil }
            return NSImage(cgImage:art,size:NSSize(width:art.width,height:art.height))
        }
    }
}
