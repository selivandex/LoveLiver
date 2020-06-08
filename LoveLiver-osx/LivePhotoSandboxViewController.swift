//
//  LivePhotoSandboxViewController.swift
//  LoveLiver
//
//  Created by BAN Jun on 2016/03/21.
//  Copyright © 2016年 mzp. All rights reserved.
//

import Cocoa
import AVFoundation
import AVKit
import NorthLayout
import Ikemen
import Accelerate

private let livePhotoDuration: TimeInterval = 3
private let outputDir = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Pictures/LoveLiver")

@available(OSX 10.12.2, *)
fileprivate extension NSTouchBarItem.Identifier {
    static let overview = NSTouchBarItem.Identifier("jp.mzp.loveliver.overview")
}

private func label() -> NSTextField {
    return NSTextField() ※ { tf in
        tf.isBezeled = false
        tf.isEditable = false
        tf.drawsBackground = false
        tf.textColor = NSColor.gray
        tf.font = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: NSFont.Weight.regular)
    }
}

class LivePhotoSandboxViewController: NSViewController, NSTouchBarDelegate {
    fileprivate let baseFilename: String
    fileprivate lazy var exportButton: NSButton = NSButton() ※ { b in
        b.bezelStyle = .regularSquare
        b.title = "Create Live Photo"
        b.target = self
        b.action = #selector(self.export)
    }
    fileprivate var exportSession: AVAssetExportSession?

    fileprivate lazy var closeButton: NSButton = NSButton() ※ { b in
        b.bezelStyle = .regularSquare
        b.title = "Close"
        b.target = self
        b.action = #selector(self.close)
    }
    var closeAction: (() -> Void)?

    fileprivate func updateButtons() {
        exportButton.isEnabled = (exportSession == nil)
    }

    fileprivate let player: AVPlayer
    fileprivate let playerView: AVPlayerView = AVPlayerView() ※ { v in
        v.controlsStyle = .none
    }
    fileprivate let overview: MovieOverviewControl

    fileprivate let startFrameView = NSImageView()
    fileprivate let endFrameView = NSImageView()
    fileprivate let imageGenerator: AVAssetImageGenerator
    fileprivate func updateImages() {
        imageGenerator.cancelAllCGImageGeneration()
        imageGenerator.generateCGImagesAsynchronously(forTimes: [startTime, endTime].map {NSValue(time: $0)}) { (requestedTime, cgImage, actualTime, result, error) in
            guard let cgImage = cgImage, result == .succeeded else { return }

            DispatchQueue.main.async {
                if requestedTime == self.startTime {
                    self.startFrameView.image = NSImage(cgImage: cgImage, size: NSZeroSize)
                }
                if requestedTime == self.endTime {
                    self.endFrameView.image = NSImage(cgImage: cgImage, size: NSZeroSize)
                }
            }
        }
    }

    var startTime: CMTime {
        didSet {
            updateLabels()
            updateScope()
        }
    }
    var posterTime: CMTime { didSet { updateLabels() } }
    var endTime: CMTime {
        didSet {
            updateLabels()
            updateScope()
        }
    }

    private var trimRange = CMTimeRange() {
        didSet {
            overview.trimRange = trimRange
            touchBarItemProvider?.trimRange = trimRange
        }
    }

    private var scopeRange = CMTimeRange() {
        didSet {
            overview.scopeRange = scopeRange
            touchBarItemProvider?.scopeRange = scopeRange
        }
    }

    private let touchBarItemProvider : OverviewTouchBarItemProviderType?

    fileprivate let startLabel = label()
    fileprivate let beforePosterLabel = label()
    fileprivate let posterLabel = label()
    fileprivate let afterPosterLabel = label()
    fileprivate let endLabel = label()
    fileprivate func updateLabels() {
        startLabel.stringValue = startTime.stringInmmssSS
        beforePosterLabel.stringValue = " ~ \(CMTimeSubtract(posterTime, startTime).stringInsSS) ~ "
        posterLabel.stringValue = posterTime.stringInmmssSS
        afterPosterLabel.stringValue = " ~ \(CMTimeSubtract(endTime, posterTime).stringInsSS) ~ "
        endLabel.stringValue = endTime.stringInmmssSS
    }
    fileprivate func updateScope() {
        let duration = player.currentItem?.duration ?? CMTime.zero

        if CMTimeMaximum(CMTime.zero, startTime) == CMTime.zero {
            // scope is clipped by zero. underflow scope start by subtracting from end
            scopeRange = CMTimeRange(start: CMTimeSubtract(endTime, CMTime(seconds: livePhotoDuration, preferredTimescale: posterTime.timescale)), end: endTime)
        } else if CMTimeMinimum(duration, endTime) == duration {
            // scope is clipped by movie end. overflow scope end by adding to start
            scopeRange = CMTimeRange(start: startTime, end: CMTimeAdd(startTime, CMTime(seconds: livePhotoDuration, preferredTimescale: posterTime.timescale)))
        } else {
            scopeRange = CMTimeRange(start: startTime, end: endTime)
        }
    }

    init!(player: AVPlayer, baseFilename: String) {
        guard let asset = player.currentItem?.asset else { return nil }
        let item = AVPlayerItem(asset: asset)

        self.baseFilename = baseFilename
        posterTime = CMTimeConvertScale(player.currentTime(), timescale: max(600, player.currentTime().timescale), method: .default) // timescale = 1 (too inaccurate) when posterTime = 0
        let duration = item.duration
        let offset = CMTime(seconds: livePhotoDuration / 2, preferredTimescale: posterTime.timescale)
        startTime = CMTimeMaximum(CMTime.zero, CMTimeSubtract(posterTime, offset))
        endTime = CMTimeMinimum(CMTimeAdd(posterTime, offset), duration)

        self.player = AVPlayer(playerItem: item)

        imageGenerator = AVAssetImageGenerator(asset: asset) ※ { g -> Void in
            g.requestedTimeToleranceBefore = .zero
            g.requestedTimeToleranceAfter = .zero
            g.maximumSize = CGSize(width: 128 * 2, height: 128 * 2)
        }

        overview = MovieOverviewControl(player: self.player, playerItem: item)
        overview.draggingMode = .scope
        overview.imageGeneratorTolerance = .zero

        if #available(OSX 10.12.2, *) {
            touchBarItemProvider = OverviewTouchBarItemProvider(player: self.player, playerItem: item)
        } else {
            touchBarItemProvider = nil
        }

        super.init(nibName: nil, bundle: nil)

        self.player.volume = player.volume
        self.player.actionAtItemEnd = .pause
        self.playerView.player = self.player

        self.player.addObserver(self, forKeyPath: "rate", options: [], context: nil)
        play()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        player.removeObserver(self, forKeyPath: "rate")
    }

    override func loadView() {
        view = NSView(frame: NSRect(x: 0, y: 0, width: 500, height: 500))

        let autolayout = view.northLayoutFormat(["p": 8], [
            "export": exportButton,
            "close": closeButton,
            "player": playerView,
            "overview": overview,
            "startFrame": startFrameView,
            "startLabel": startLabel,
            "beforePosterLabel": beforePosterLabel,
            "posterLabel": posterLabel,
            "afterPosterLabel": afterPosterLabel,
            "endFrame": endFrameView,
            "endLabel": endLabel,
            "spacerLL": NSView(),
            "spacerLR": NSView(),
            "spacerRL": NSView(),
            "spacerRR": NSView(),
            ])
        autolayout("H:|-p-[close]-(>=p)-[export]-p-|")
        autolayout("H:|-p-[player]-p-|")
        autolayout("H:|-p-[startFrame]-(>=p)-[endFrame(==startFrame)]-p-|")
    autolayout("H:|-p-[startLabel][spacerLL][beforePosterLabel][spacerLR(==spacerLL)][posterLabel][spacerRL(==spacerLL)][afterPosterLabel][spacerRR(==spacerLL)][endLabel]-p-|")
        autolayout("H:|-p-[overview]-p-|")
        autolayout("V:|-p-[export]-p-[player]")
        autolayout("V:|-p-[close]-p-[player]")
        autolayout("V:[player(==400)][overview(==64)]")
        autolayout("V:[overview]-p-[startFrame(==128)][startLabel]-p-|")
        autolayout("V:[startFrame][beforePosterLabel]")
        autolayout("V:[startFrame][posterLabel]")
        autolayout("V:[startFrame][afterPosterLabel]")
        autolayout("V:[overview]-p-[endFrame(==startFrame)][endLabel]-p-|")

        if let videoSize = player.currentItem?.naturalSize {
            playerView.addConstraint(NSLayoutConstraint(item: playerView, attribute: .height, relatedBy: .equal,
                toItem: playerView, attribute: .width, multiplier: videoSize.height / videoSize.width, constant: 0))

            startFrameView.addConstraint(NSLayoutConstraint(item: startFrameView, attribute: .width, relatedBy: .equal, toItem: startFrameView, attribute: .height, multiplier: videoSize.width / videoSize.height, constant: 0))
        }

        if #available(OSX 10.12.2, *) {
            touchBar = NSTouchBar() ※ { bar in
                bar.defaultItemIdentifiers = [.overview]
                bar.delegate = self
            }
        }

        updateLabels()
        updateImages()
    }

    override func viewDidLayout() {
        super.viewDidLayout()

        let trimStart = CMTimeSubtract(posterTime, CMTime(seconds: livePhotoDuration, preferredTimescale: posterTime.timescale))
        let trimEnd = CMTimeAdd(posterTime, CMTime(seconds: livePhotoDuration, preferredTimescale: posterTime.timescale))
        trimRange = CMTimeRange(start: trimStart, end: trimEnd)

        overview.shouldUpdateScopeRange = shouldUpdateScopeRange
        overview.onScopeChange = {[weak self] in
            guard let `self` = self else { return }
            self.onScopeChange(self.overview)
        }

        touchBarItemProvider?.shouldUpdateScopeRange = shouldUpdateScopeRange
        touchBarItemProvider?.onScopeChange = {[weak self] (overview) in
            guard let `self` = self else { return }
            self.onScopeChange(overview)
        }

        updateScope()

        // hook playerView click
        let playerViewClickGesture = NSClickGestureRecognizer(target: self, action: #selector(playOrPause))
        playerView.addGestureRecognizer(playerViewClickGesture)
    }

    func onScopeChange(_ overview : MovieOverviewControl) {
        guard let s = overview.scopeRange?.start,
            let e = overview.scopeRange?.end else { return }
        startTime = CMTimeMaximum(.zero, s)
        endTime = CMTimeMinimum(player.currentItem?.duration ?? .zero, e)

        if !((touchBarItemProvider?.dragging ?? false) || self.overview.dragging) {
            updateImages()
        }
    }

    @objc fileprivate func export() {
        guard let asset = player.currentItem?.asset else { return }
        
        let imageGenerator = AVAssetImageGenerator(asset: asset) ※ {
            $0.requestedTimeToleranceBefore = .zero
            $0.requestedTimeToleranceAfter = .zero
        }
        guard let image = imageGenerator.copyImage(at: posterTime) else { return }
        guard let _ = try? FileManager.default.createDirectory(atPath: outputDir.path, withIntermediateDirectories: true, attributes: nil) else { return }

        let assetIdentifier = UUID().uuidString
        let basename = [
            baseFilename,
            posterTime.stringInmmmsssSS,
            assetIdentifier].joined(separator: "-")
        let tmpImagePath = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("\(basename).tiff").path
        let tmpMoviePath = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("\(basename).mov").path
        let imagePath = outputDir.appendingPathComponent("\(basename).JPG").path
        let moviePath = outputDir.appendingPathComponent("\(basename).MOV").path
        
        let paths = [tmpImagePath, tmpMoviePath, imagePath, moviePath]

        for path in paths {
            guard !FileManager.default.fileExists(atPath: path) else { return }
        }

        guard let imageData = image.tiffRepresentation, let jpegData = NSBitmapImageRep(data: imageData)?.representation(using: .jpeg, properties: [.compressionFactor : 1.0]) else { return }
        
        guard let _ = try? jpegData.write(to: URL(fileURLWithPath: tmpImagePath), options: [.atomic]) else { return }
        
        // create AVAssetExportSession each time because it cannot be reused after export completion
        guard let session = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetPassthrough) else { return }
        session.outputFileType = AVFileType(rawValue: "com.apple.quicktime-movie")
        session.outputURL = URL(fileURLWithPath: tmpMoviePath)
        session.timeRange = CMTimeRange(start: startTime, end: endTime)
//        session.shouldOptimizeForNetworkUse = true
        session.exportAsynchronously {
            DispatchQueue.main.async {
                switch session.status {
                case .completed:
                    JPEG(path: tmpImagePath).write(imagePath, assetIdentifier: assetIdentifier)
                    NSLog("%@", "LivePhoto JPEG created: \(imagePath)")

                    QuickTimeMov(path: tmpMoviePath).write(moviePath, assetIdentifier: assetIdentifier)
                    NSLog("%@", "LivePhoto MOV created: \(moviePath)")
                    
                    self.exportLightVersion(asset, completion: { (lightMoviePath, lightImagePath, success) in
                        if success {
                            self.showInFinderAndOpenInPhotos([imagePath, moviePath, lightMoviePath!, lightImagePath!].map{URL(fileURLWithPath: $0)})
                        }
                    })
                    
                case .cancelled, .exporting, .failed, .unknown, .waiting:
                    NSLog("%@", "exportAsynchronouslyWithCompletionHandler = \(session.status)")
                }

                for path in [tmpImagePath, tmpMoviePath] {
                    let _ = try? FileManager.default.removeItem(atPath: path)
                }
                self.exportSession = nil
                self.updateButtons()
            }
        }
        exportSession = session
        updateButtons()
    }
    
    fileprivate func exportLightVersion(_ asset: AVAsset, completion handler: @escaping (_ moviePath: String?, _ imagePath: String?, _ success: Bool) -> ()) {
        let assetIdentifier = UUID().uuidString
        let basename = [
            baseFilename,
            posterTime.stringInmmmsssSS,
            assetIdentifier].joined(separator: "-")
        
        let imageGenerator = AVAssetImageGenerator(asset: asset) ※ {
            $0.requestedTimeToleranceBefore = .zero
            $0.requestedTimeToleranceAfter = .zero
        }
        guard let image = imageGenerator.copyImage(at: posterTime) else { return }
        
        let tmpTiffLightImagePath = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("light_\(basename).tiff").path
        let tmpLightImagePath = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("light_\(basename).JPG").path
        let tmpLightMoviePath = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("light_\(basename).MOV").path
        let lightImagePath = outputDir.appendingPathComponent("light_\(basename).JPG").path
        let lightMoviePath = outputDir.appendingPathComponent("light_\(basename).MOV").path
        
        let paths = [tmpLightImagePath, tmpLightMoviePath, lightImagePath, lightMoviePath]
        
        for path in paths {
            guard !FileManager.default.fileExists(atPath: path) else { return }
        }

        let ratio = image.height / image.width
        let height: CGFloat = 1000
        let width = round(height / ratio)
        let size: NSSize = .init(width: width, height: height)
        
        let resizedImage = image.resizedImage(to: size)
        
        guard let img = resizedImage, let data = img.tiffRepresentation, let _ = try? data.write(to: URL(fileURLWithPath: tmpTiffLightImagePath), options: [.atomic]) else { return }
        
        guard let session = AVAssetExportSession(asset: asset, presetName: AVAssetExportPreset1280x720) else { return }
        session.outputFileType = .mov
        session.outputURL = URL(fileURLWithPath: tmpLightMoviePath)
        session.timeRange = CMTimeRange(start: startTime, end: endTime)
        session.exportAsynchronously {
            DispatchQueue.main.async {
                switch session.status {
                case .completed:
                    JPEG(path: tmpTiffLightImagePath).write(lightImagePath, assetIdentifier: assetIdentifier)
                    NSLog("%@", "LivePhoto Light JPEG created: \(lightImagePath)")
                    
                    QuickTimeMov(path: tmpLightMoviePath).write(lightMoviePath, assetIdentifier: assetIdentifier)
                    NSLog("%@", "LivePhoto Light MOV created: \(lightMoviePath)")
                    
                    handler(lightMoviePath, lightImagePath, true)
                case .cancelled, .exporting, .failed, .unknown, .waiting:
                    NSLog("%@", "exportAsynchronouslyWithCompletionHandler = \(session.status)")
                    handler(lightMoviePath, lightImagePath, false)
                }
                
                for path in [tmpLightImagePath, tmpLightMoviePath] {
                    let _ = try? FileManager.default.removeItem(atPath: path)
                }
            }
        }
    }

    fileprivate func showInFinderAndOpenInPhotos(_ fileURLs: [URL]) {
        NSWorkspace.shared.activateFileViewerSelecting(fileURLs)

        // wait until Finder is active or timed out,
        // to avoid openURLs overtaking Finder activation
        DispatchQueue.global(qos: .default).async {
            let start = Date()
            while NSWorkspace.shared.frontmostApplication?.bundleIdentifier != "com.apple.finder" && Date().timeIntervalSince(start) < 5 {
                Thread.sleep(forTimeInterval: 0.1)
            }
//            NSWorkspace.shared.open(fileURLs, withAppBundleIdentifier: "com.apple.Photos", options: [], additionalEventParamDescriptor: nil, launchIdentifiers: nil)
        }
    }

    private func shouldUpdateScopeRange(scopeRange : CMTimeRange?) -> Bool {
        guard let scopeRange = scopeRange else { return false }
        return CMTimeRangeContainsTime(scopeRange, time: self.posterTime)
    }

    @objc fileprivate func close() {
        closeAction?()
    }

    @objc fileprivate func play() {
        player.seek(to: startTime, toleranceBefore: CMTime.zero, toleranceAfter: CMTime.zero)
        player.play()
    }

    @objc fileprivate func pause() {
        player.pause()
    }

    @objc fileprivate func playOrPause() {
        if player.rate == 0 {
            play()
        } else {
            pause()
        }
    }

    override func observeValue(forKeyPath keyPath: String?, of object: Any?, change: [NSKeyValueChangeKey : Any]?, context: UnsafeMutableRawPointer?) {
        switch (object, keyPath) {
        case (is AVPlayer, _):
            let stopped = (player.rate == 0)
            if stopped {
                player.seek(to: posterTime, toleranceBefore: CMTime.zero, toleranceAfter: CMTime.zero)
            }
            break
        default:
            super.observeValue(forKeyPath: keyPath, of: object, change: change, context: context)
        }
    }

    @available(OSX 10.12.2, *)
    func touchBar(_ touchBar: NSTouchBar, makeItemForIdentifier identifier: NSTouchBarItem.Identifier) -> NSTouchBarItem? {
        if identifier == .overview {
            return touchBarItemProvider?.makeTouchbarItem(identifier: identifier)
        } else {
            return nil
        }
    }
}
