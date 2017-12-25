import Photos
import CocoaLumberjackSwift


extension GalleryKeyboardViewController: UICollectionViewDelegateFlowLayout, UICollectionViewDelegate, UICollectionViewDataSource {
    fileprivate enum CameraKeyboardSection: UInt {
        case camera = 0, photos = 1
    }
    
    public func numberOfSections(in collectionView: UICollectionView) -> Int {
        return 2
    }
    
    public func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        switch CameraKeyboardSection(rawValue: UInt(section))! {
        case .camera:
            return 1
        case .photos:
            return Int(assetLibrary.count)
        }
    }
    
    public func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        switch CameraKeyboardSection(rawValue: UInt((indexPath as NSIndexPath).section))! {
        case .camera:
            let cell = collectionView.dequeueReusableCell(withReuseIdentifier: CameraCell.reuseIdentifier, for: indexPath) as! CameraCell
            cell.delegate = self
            return cell
        case .photos:
            let cell = collectionView.dequeueReusableCell(withReuseIdentifier: AssetCell.reuseIdentifier, for: indexPath) as! AssetCell
            if let asset = try? assetLibrary.asset(atIndex: UInt((indexPath as NSIndexPath).row)) {
                cell.asset = asset
            }
            return cell
        }
    }
    
    public func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, sizeForItemAt indexPath: IndexPath) -> CGSize {
        switch CameraKeyboardSection(rawValue: UInt((indexPath as NSIndexPath).section))! {
        case .camera:
            switch self.splitLayoutObservable.layoutSize {
            case .compact:
                return CGSize(width: self.view.bounds.size.width / 2, height: self.view.bounds.size.height)
            case .regularPortrait, .regularLandscape:
                return CGSize(width: self.splitLayoutObservable.leftViewControllerWidth, height: self.view.bounds.size.height)
            }
        case .photos:
            let photoSize = self.view.bounds.size.height / 2 - 0.5
            return CGSize(width: photoSize, height: photoSize)
        }
    }
    
    public func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        
        switch CameraKeyboardSection(rawValue: UInt((indexPath as NSIndexPath).section))! {
        case .camera:
            break
        case .photos:
            let asset = try! assetLibrary.asset(atIndex: UInt((indexPath as NSIndexPath).row))
            
            switch asset.mediaType {
            case .video:
                self.forwardSelectedVideoAsset(asset)
                
            case .image:
                self.forwardSelectedPhotoAsset(asset)
                
            default:
                // not supported
                break;
            }
        }
    }

    fileprivate func forwardSelectedPhotoAsset(_ asset: PHAsset) {
        let manager = PHImageManager.default()
        
        let options = PHImageRequestOptions()
        options.deliveryMode = .highQualityFormat
        options.isNetworkAccessAllowed = false
        options.isSynchronous = false
        manager.requestImageData(for: asset, options: options, resultHandler: { data, uti, orientation, info in
            guard let data = data else {
                let options = PHImageRequestOptions()
                options.deliveryMode = .highQualityFormat
                options.isNetworkAccessAllowed = true
                options.isSynchronous = false
                DispatchQueue.main.async(execute: {
                    self.showLoadingView = true
                })
                
                manager.requestImageData(for: asset, options: options, resultHandler: { data, uti, orientation, info in
                    DispatchQueue.main.async(execute: {
                        self.showLoadingView = false
                    })
                    guard let data = data else {
                        DDLogError("Failure: cannot fetch image")
                        return
                    }
                    
                    DispatchQueue.main.async(execute: {
                        let metadata = ImageMetadata()
                        metadata.camera = .none
                        metadata.method = ConversationMediaPictureTakeMethod.keyboard
                        metadata.source = ConversationMediaPictureSource.gallery
                        metadata.sketchSource = .none
                        
                        self.delegate?.cameraKeyboardViewController(self, didSelectImageData: data, metadata: metadata)
                    })
                })
                
                return
            }
            DispatchQueue.main.async(execute: {
                
                let metadata = ImageMetadata()
                metadata.camera = .none
                metadata.method = ConversationMediaPictureTakeMethod.keyboard
                metadata.source = ConversationMediaPictureSource.gallery
                metadata.sketchSource = .none
                
                self.delegate?.cameraKeyboardViewController(self, didSelectImageData: data, metadata: metadata)
            })
        })
    }
    
    fileprivate func forwardSelectedVideoAsset(_ asset: PHAsset) {
        let manager = PHImageManager.default()
        
        let options = PHVideoRequestOptions()
        options.deliveryMode = .highQualityFormat
        options.isNetworkAccessAllowed = true
        options.version = .current
        
        self.showLoadingView = true
        manager.requestExportSession(forVideo: asset, options: options, exportPreset: AVAssetExportPresetMediumQuality) { exportSession, info in
            
            DispatchQueue.main.async(execute: {
                
                guard let exportSession = exportSession else {
                    self.showLoadingView = false
                    return
                }
                
                let exportURL = URL(fileURLWithPath: (NSTemporaryDirectory() as NSString).appendingPathComponent("video-export.mp4"))
                
                if FileManager.default.fileExists(atPath: exportURL.path) {
                    do {
                        try FileManager.default.removeItem(at: exportURL)
                    }
                    catch let error {
                        DDLogError("Cannot remove \(exportURL): \(error)")
                    }
                }
                
                exportSession.outputURL = exportURL
                exportSession.outputFileType = AVFileTypeQuickTimeMovie
                exportSession.shouldOptimizeForNetworkUse = true
                exportSession.outputFileType = AVFileTypeMPEG4
                
                exportSession.exportAsynchronously {
                    self.showLoadingView = false
                    DispatchQueue.main.async(execute: {
                        self.delegate?.cameraKeyboardViewController(self, didSelectVideo: exportSession.outputURL!, duration: CMTimeGetSeconds(exportSession.asset.duration))
                    })
                }
            })
        }
    }

    public func collectionView(_ collectionView: UICollectionView, didEndDisplaying cell: UICollectionViewCell, forItemAt indexPath: IndexPath) {
        if cell is CameraCell {
            self.goBackButtonRevealed = true
        }
    }
    
    public func collectionView(_ collectionView: UICollectionView, willDisplay cell: UICollectionViewCell, forItemAt indexPath: IndexPath) {
        if cell is CameraCell {
            self.goBackButtonRevealed = false
        }
    }
}


extension GalleryKeyboardViewController: CameraCellDelegate {
    public func cameraCellWantsToOpenFullCamera(_ cameraCell: CameraCell) {
        self.delegate?.cameraKeyboardViewControllerWantsToOpenFullScreenCamera(self)
    }
    
    public func cameraCell(_ cameraCell: CameraCell, didPickImageData imageData: Data) {
        guard let cameraController = cameraCell.cameraController else {
            return
        }
        
        let isFrontCamera = cameraController.currentCamera == .front
        
        let camera: ConversationMediaPictureCamera = isFrontCamera ? ConversationMediaPictureCamera.front : ConversationMediaPictureCamera.back
        
        let metadata = ImageMetadata()
        metadata.camera = camera
        metadata.method = ConversationMediaPictureTakeMethod.keyboard
        metadata.source = ConversationMediaPictureSource.camera
        metadata.sketchSource = .none
        
        self.delegate?.cameraKeyboardViewController(self, didSelectImageData: imageData, metadata: metadata)
    }
}

