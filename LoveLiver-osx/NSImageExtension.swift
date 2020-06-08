//
//  NSImageExtension.swift
//  LoveLiver-osx
//
//  Created by Alexander Selivanov on 29/04/2019.
//  Copyright © 2019 mzp. All rights reserved.
//

import Cocoa
import Accelerate

import CoreImage

enum RadiusCalculator {
    
    static func radius(value: Double, max: Double, imageExtent: CGRect) -> Double {
        
        let base = Double(sqrt(pow(imageExtent.width,2) + pow(imageExtent.height,2)))
        let c = base / 20
        return c * value / max
    }
}


public protocol Filtering {
    func apply(to image: CIImage, sourceImage: CIImage) -> CIImage
}

extension NSImage {
    var width: CGFloat {
        return self.size.width
    }
    
    var height: CGFloat {
        return self.size.height
    }
    
    func resizedImage(to newSize: NSSize) -> NSImage? {
        let representation = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(newSize.width), pixelsHigh: Int(newSize.height), bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .calibratedRGB, bytesPerRow: 0, bitsPerPixel: 0)
        representation?.size = newSize
        
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: representation!)
        self.draw(in: NSRect(x: 0, y: 0, width: newSize.width, height: newSize.height), from: NSZeroRect, operation: .copy, fraction: 1.0)
        NSGraphicsContext.restoreGraphicsState()
        
        let newImage = NSImage(size: newSize)
        newImage.addRepresentation(representation!)
        return newImage.applyFilter()
    }
    
    func applyFilter() -> NSImage? {
        guard let data = self.tiffRepresentation, let img = CIImage(data: data) else { return nil }
        let _radius = RadiusCalculator.radius(value: 10, max: 100, imageExtent: img.extent)
        
        let filteredImg = img.applyingFilter("CISharpenLuminance", parameters: [
            "inputRadius" : _radius,
            "inputSharpness": 0.2,
            ])
        let rep = NSCIImageRep(ciImage: filteredImg)
        let newImg = NSImage(size: size)
        newImg.addRepresentation(rep)
        
        return newImg
    }
}
