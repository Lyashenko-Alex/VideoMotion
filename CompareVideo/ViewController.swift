//
//  ViewController.swift
//  CompareVideo
//
//  Created by RX on 11/9/20.
//  Copyright © 2020 RX. All rights reserved.
//

import UIKit
import AVFoundation
import AVKit

class ViewController: UIViewController {

    override func viewDidLoad() {
        super.viewDidLoad()
        // Do any additional setup after loading the view.
        guard let url1 = Bundle.main.url(forResource: "test", withExtension: "mov") else { return }
        guard let url2 = Bundle.main.url(forResource: "test", withExtension: "mov") else { return }
        let targetSize = CGSize(width: 1920, height: 1080)
        
        exportFinalVideo(url1, url2, targetSize: targetSize) { [weak self] (url) in
            guard let weakSelf = self else { return }
            DispatchQueue.main.async {
                weakSelf.playVideo(url: url)
            }
        }
    }

    private func playVideo(url: URL) {
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default, options: [])
        } catch {
            // report for an error
            print(error)
        }
        
        let player = AVPlayer(url: url)
        let playerController = AVPlayerViewController()
        playerController.player = player
        present(playerController, animated: true) {
            player.play()
        }
    }
    
    private func exportFinalVideo(_ first: URL, _ second: URL, targetSize: CGSize, completion: @escaping (_ final: URL) -> Void) {
        let halfSize = CGSize(width: targetSize.width / 2, height: targetSize.height)
        resizeVideo(first, halfSize, targetFileName: "firstResize.mp4") { [weak self] (url1) in
            guard let weakSelf = self else { return }
            weakSelf.resizeVideo(second, halfSize, targetFileName: "secondResize.mp4") { [weak self] (url2) in
                guard let weakSelf = self else { return }
                weakSelf.mergeTwoResizedVideo(url1, url2, targetSize, targetFileName: "compare.mp4") { (final) in
                    completion(final)
                }
            }
        }
    }
    
    private func resizeVideo(_ url: URL, _ targeSize: CGSize, targetFileName: String, completion: @escaping (_ final: URL) -> Void) {
        
        let asset = AVAsset(url: url)
        let videoTrack = asset.tracks(withMediaType: AVMediaType.video)[0]
        let assetInfo = orientationFromTransform(transform: videoTrack.preferredTransform)
        var naturalSize = videoTrack.naturalSize
        
        if assetInfo.isPortrait == true {
            naturalSize.width = videoTrack.naturalSize.height
            naturalSize.height = videoTrack.naturalSize.width
        }
        
        let scaledSize = scaledSizeToAspectFill(naturalSize, targeSize)
        let scaleFactor = scaledSize.width / naturalSize.width
        
        let videoComposition = AVMutableVideoComposition()
        videoComposition.renderSize = targeSize
        videoComposition.frameDuration = CMTimeMake(value: 1, timescale: 30)

        let transformer = AVMutableVideoCompositionLayerInstruction(assetTrack: videoTrack)
        var transform = videoTrack.preferredTransform
        if assetInfo.isPortrait {
            if assetInfo.orientation == .right {
                transform = transform.concatenating(CGAffineTransform(translationX: -videoTrack.preferredTransform.tx, y: -videoTrack.preferredTransform.ty))
                transform = transform.concatenating(CGAffineTransform(translationX: videoTrack.naturalSize.height / 2, y: -videoTrack.naturalSize.width / 2))
                transform = transform.concatenating(CGAffineTransform(scaleX: scaleFactor, y: scaleFactor))
                transform = transform.concatenating(CGAffineTransform(translationX: scaledSize.width / 2, y: scaledSize.height / 2))
            }
            
            if assetInfo.orientation == .left {
                transform = transform.concatenating(CGAffineTransform(translationX: -videoTrack.preferredTransform.tx, y: -videoTrack.preferredTransform.ty))
                transform = transform.concatenating(CGAffineTransform(translationX: -videoTrack.naturalSize.height / 2, y: videoTrack.naturalSize.width / 2))
                transform = transform.concatenating(CGAffineTransform(scaleX: scaleFactor, y: scaleFactor))
                transform = transform.concatenating(CGAffineTransform(translationX: scaledSize.width / 2, y: scaledSize.height / 2))
            }
            
        } else {
            let posX = scaledSize.width / 2 - (videoTrack.naturalSize.width * scaleFactor) / 2
            let posY = scaledSize.height / 2 - (videoTrack.naturalSize.height * scaleFactor) / 2
            let moveFactor = CGAffineTransform(translationX: posX, y: posY)
            
            transform = transform.concatenating(CGAffineTransform(scaleX: scaleFactor, y: scaleFactor))
            transform = transform.concatenating(moveFactor)
        }
        transformer.setTransform(transform, at: CMTime.zero)

        let instruction = AVMutableVideoCompositionInstruction()
        instruction.timeRange = CMTimeRangeMake(start: .zero, duration: asset.duration)

        instruction.layerInstructions = [transformer]
        videoComposition.instructions = [instruction]

        let directory = NSTemporaryDirectory() as NSString
        let videoPath = directory.appendingPathComponent(targetFileName)
        let outputURL = URL(fileURLWithPath: videoPath)
        
        do {
            if FileManager.default.fileExists(atPath: videoPath) {
                try FileManager.default.removeItem(atPath: videoPath)
            }
        } catch {
            print(error.localizedDescription)
        }
        
        guard let videoExporter = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetHighestQuality) else {
            completion(url)
            return
        }
        
        videoExporter.outputURL = outputURL
        videoExporter.outputFileType = AVFileType.mp4
        videoExporter.shouldOptimizeForNetworkUse = true
        videoExporter.videoComposition = videoComposition
        
        videoExporter.exportAsynchronously() {
            let exportedURL = videoExporter.status == AVAssetExportSession.Status.completed ? outputURL : url
            completion(exportedURL)
        }
    }
    
    private func mergeTwoResizedVideo(_ url1: URL, _ url2: URL, _ targeSize: CGSize, targetFileName: String, completion: @escaping (_ final: URL) -> Void) {
        let asset1 = AVAsset(url: url1)
        let asset2 = AVAsset(url: url2)
        
        let mixComposition = AVMutableComposition()
        guard let videoCompositionTrack1 = mixComposition.addMutableTrack(withMediaType: AVMediaType.video, preferredTrackID: Int32(kCMPersistentTrackID_Invalid)) else { return }
        guard let videoCompositionTrack2 = mixComposition.addMutableTrack(withMediaType: AVMediaType.video, preferredTrackID: Int32(kCMPersistentTrackID_Invalid)) else { return }
        guard let audioCompositionTrack = mixComposition.addMutableTrack(withMediaType: AVMediaType.audio, preferredTrackID: Int32(kCMPersistentTrackID_Invalid)) else { return }

        let videoTrack1 = asset1.tracks(withMediaType: AVMediaType.video)[0]
        let audioTrack1 = asset1.tracks(withMediaType: AVMediaType.audio)[0]
        let videoTrack2 = asset2.tracks(withMediaType: AVMediaType.video)[0]
        
        do {
            try videoCompositionTrack1.insertTimeRange(CMTimeRangeMake(start: .zero, duration: asset1.duration), of: videoTrack1, at: .zero)
            try videoCompositionTrack2.insertTimeRange(CMTimeRangeMake(start: .zero, duration: asset2.duration), of: videoTrack2, at: .zero)
            try audioCompositionTrack.insertTimeRange(CMTimeRangeMake(start: .zero, duration: asset1.duration), of: audioTrack1, at: .zero)
        } catch {
            print(error.localizedDescription)
        }
        

        let mainInstruction = VideoCompositionInstruction(trackID: [videoCompositionTrack1.trackID, videoCompositionTrack2.trackID])
        mainInstruction.timeRange = CMTimeRangeMake(start: .zero, duration: asset1.duration)

        
        let transformer1 = AVMutableVideoCompositionLayerInstruction(assetTrack: videoCompositionTrack1)
        let transform1 = videoTrack1.preferredTransform
        transformer1.setTransform(transform1, at: CMTime.zero)

        let transformer2 = AVMutableVideoCompositionLayerInstruction(assetTrack: videoCompositionTrack2)
        var transform2 = videoTrack2.preferredTransform
        transform2 = transform2.concatenating(CGAffineTransform(translationX: videoTrack2.naturalSize.width, y: 0))
        transformer2.setTransform(transform2, at: CMTime.zero)

        
        mainInstruction.layerInstructions = [transformer1, transformer2]

        
        let videoComposition = AVMutableVideoComposition()
        videoComposition.renderSize = targeSize
        videoComposition.frameDuration = CMTimeMake(value: 1, timescale: 30)
        videoComposition.instructions = [mainInstruction]

        
        let directory = NSTemporaryDirectory() as NSString
        let videoPath = directory.appendingPathComponent(targetFileName)
        let outputURL = URL(fileURLWithPath: videoPath)
        
        do {
            if FileManager.default.fileExists(atPath: videoPath) {
                try FileManager.default.removeItem(atPath: videoPath)
            }
        } catch {
            print(error.localizedDescription)
        }
        
        guard let videoExporter = AVAssetExportSession(asset: mixComposition, presetName: AVAssetExportPresetHighestQuality) else {
            completion(url1)
            return
        }
        
        videoExporter.outputURL = outputURL
        videoExporter.outputFileType = AVFileType.mp4
        videoExporter.shouldOptimizeForNetworkUse = true
        videoExporter.videoComposition = videoComposition
        
        videoExporter.exportAsynchronously() {
            let exportedURL = videoExporter.status == AVAssetExportSession.Status.completed ? outputURL : url1
            completion(exportedURL)
        }
    }
    
    private func scaledSizeToAspectFill(_ size: CGSize, _ target: CGSize) -> CGSize {
        var scaledSize = size
        
        let ws = target.width / size.width;
        let hs = target.height / size.height;

        if (hs > ws) {
            scaledSize.height = target.height
            scaledSize.width = target.height * size.width / size.height;
        } else {
            scaledSize.width = target.width
            scaledSize.height = target.width * size.height / size.width;
        }
        
        return scaledSize
    }
    
    fileprivate func orientationFromTransform(transform: CGAffineTransform) -> (orientation: UIImage.Orientation, isPortrait: Bool) {
        var assetOrientation = UIImage.Orientation.up
        var isPortrait = false
        if transform.a == 0 && transform.b == 1.0 && transform.c == -1.0 && transform.d == 0 {
            assetOrientation = .right
            isPortrait = true
        } else if transform.a == 0 && transform.b == 1.0 && transform.c == 1.0 && transform.d == 0 {
            assetOrientation = .rightMirrored
            isPortrait = true
        } else if transform.a == 0 && transform.b == -1.0 && transform.c == 1.0 && transform.d == 0 {
            assetOrientation = .left
            isPortrait = true
        } else if transform.a == 0 && transform.b == -1.0 && transform.c == -1.0 && transform.d == 0 {
            assetOrientation = .leftMirrored
            isPortrait = true
        } else if transform.a == 1.0 && transform.b == 0 && transform.c == 0 && transform.d == 1.0 {
            assetOrientation = .up
        } else if transform.a == -1.0 && transform.b == 0 && transform.c == 0 && transform.d == -1.0 {
            assetOrientation = .down
        }
        return (assetOrientation, isPortrait)
    }
}

