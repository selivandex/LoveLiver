//
//  MovieManager.swift
//  LoveLiver-osx
//
//  Created by Alexander Selivanov on 29/04/2019.
//  Copyright © 2019 mzp. All rights reserved.
//

import Foundation
import AVFoundation
import CoreGraphics

class MovieManager {
    var asset: AVAsset
    
    init(_ asset: AVAsset) {
        self.asset = asset
    }
    
    var videoComposition: AVVideoComposition {
        //---------------
        //  composition
        //---------------
        let composition = AVMutableVideoComposition()
        
        //---------------
        //  instruction
        //---------------
        let instruction = AVMutableVideoCompositionInstruction()
        instruction.timeRange = CMTimeRangeMake( start: .zero, duration: self.asset.duration )
        
        //-------------------------
        //  transform instruction
        //-------------------------
        let videoTracks = self.asset.tracks( withMediaType: .video )
        let assetTrack = videoTracks[0]
        
        let naturalSize = assetTrack.naturalSize
        let heightRatio = naturalSize.height / naturalSize.width
        let size: CGFloat = 720
        let width: CGFloat = size * heightRatio
        composition.renderSize = .init(width: width, height: size)
        composition.frameDuration = CMTime(value: 1, timescale: CMTimeScale(assetTrack.nominalFrameRate))
        
//
//        let layerInstruction = AVMutableVideoCompositionLayerInstruction( assetTrack: assetTrack )
//        let transform = CGAffineTransform(a: 1.5, b: 0.0, c: 0.0, d: 2.0, tx: -100.0, ty: -100.0)
//        layerInstruction.setTransformRamp(fromStart: transform, toEnd: transform, timeRange: CMTimeRange(start: .zero, duration: asset.duration) )
//        instruction.layerInstructions = [ layerInstruction ]
//
        composition.instructions = [ instruction ]
        return composition
    }
}
