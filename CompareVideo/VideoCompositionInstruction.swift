//
//  VideoCompositionInstruction.swift
//  CompareVideo
//
//  Created by RX on 11/10/20.
//  Copyright © 2020 RX. All rights reserved.
//

import Foundation
import AVFoundation
import CoreGraphics
import CoreImage

class VideoCompositionInstruction: AVMutableVideoCompositionInstruction {

    let trackID: [CMPersistentTrackID]

    override var requiredSourceTrackIDs: [NSValue] {
        get {
            var tracks:[NSNumber] = [NSNumber]()
            for __id in self.trackID {
                tracks.append(NSNumber(value: Int(__id)))
            }
            return tracks
        }
    }
    
    override var containsTweening: Bool{get{return false}}

    init(trackID: [CMPersistentTrackID]){
        self.trackID = trackID
        
        super.init()
        
        self.enablePostProcessing = true
    }
    
    required init?(coder aDecoder: NSCoder){
        fatalError("init(coder:) has not been implemented")
    }
}
