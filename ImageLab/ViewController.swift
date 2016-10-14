//
//  ViewController.swift
//  ImageLab
//
//  Created by Eric Larson
//  Copyright © 2016 Eric Larson. All rights reserved.
//

import UIKit
import AVFoundation

class ViewController: UIViewController   {

    //MARK: Class Properties
    var filters : [CIFilter]! = nil
    var videoManager:VideoAnalgesic! = nil
    let pinchFilterIndex = 2
    var detector:CIDetector! = nil
    let bridge = OpenCVBridgeSub()
    
    //MARK: ViewController Hierarchy
    override func viewDidLoad() {
        super.viewDidLoad()
        
        self.view.backgroundColor = nil
        
        self.bridge.loadHaarCascade(withFilename: "nose")
        
        self.videoManager = VideoAnalgesic.sharedInstance
        self.videoManager.setCameraPosition(AVCaptureDevicePosition.front)
        self.videoManager.setPreset("AVCaptureSessionPresetHigh")
        
        // create dictionary for face detection
        // HINT: you need to manipulate these proerties for better face detection efficiency
        let optsDetector = [CIDetectorAccuracy:CIDetectorAccuracyLow,CIDetectorTracking:true] as [String : Any]
        
        // setup a face detector in swift
        self.detector = CIDetector(ofType: CIDetectorTypeFace,
                                  context: self.videoManager.getCIContext(), // perform on the GPU is possible
                                  options: (optsDetector as [String : AnyObject]))
        
        self.videoManager.setProcessingBlock(self.processImage)
        
        if !videoManager.isRunning{
            videoManager.start()
        }
    
    }
    
    //MARK: Process image output
    func processImage(_ inputImage:CIImage) -> CIImage{
        
        // detect faces
        let f = getFaces(inputImage)
        
        // if no faces, just return original image
        if f.count == 0 { return inputImage }
        
        //otherwise apply the filters to the faces
        return applyFiltersToFaces(inputImage, features: f)
    }

    
    //MARK: Apply filters and apply feature detectors
    func applyFiltersToFaces(_ inputImage:CIImage,features:[CIFaceFeature])->CIImage{
        var retImage = inputImage
        let pic = CIImage(image: UIImage(named: "Triangle")!)
        let pic2 = CIImage(image: UIImage(named: "Mouth")!)
        
        for f in features {
            if (f.hasLeftEyePosition) {
                
                var leftEyeImage = pic
                let scale = CGAffineTransform(scaleX: 0.40, y: 0.40)
                let translation = CGAffineTransform(translationX: f.leftEyePosition.x - 140, y: f.leftEyePosition.y - 100)
                let affineMatrix = scale.concatenating(translation)

                let transformFilter = CIFilter(name: "CIAffineTransform")!
                transformFilter.setValue(leftEyeImage, forKey: "inputImage")
                transformFilter.setValue(NSValue(cgAffineTransform: affineMatrix), forKey: "inputTransform")
                leftEyeImage = transformFilter.outputImage!
                
                let filterEye = CIFilter(name:"CISourceOverCompositing")!
                filterEye.setValue(leftEyeImage, forKey: kCIInputImageKey)
                filterEye.setValue(retImage, forKey: kCIInputBackgroundImageKey)
                retImage = filterEye.outputImage!
                
                
                NSLog("Left eye %g %g", f.leftEyePosition.x, f.leftEyePosition.y);
            }
            if (f.hasRightEyePosition) {
                var rightEyeImage = pic
                let scale = CGAffineTransform(scaleX: 0.40, y: 0.40)
                let translation = CGAffineTransform(translationX: f.rightEyePosition.x - 140, y: f.rightEyePosition.y - 100)
                let affineMatrix = scale.concatenating(translation)
                
                let transformFilter = CIFilter(name: "CIAffineTransform")!
                transformFilter.setValue(rightEyeImage, forKey: "inputImage")
                transformFilter.setValue(NSValue(cgAffineTransform: affineMatrix), forKey: "inputTransform")
                rightEyeImage = transformFilter.outputImage!
                
                let filterEye = CIFilter(name:"CISourceOverCompositing")!
                filterEye.setValue(rightEyeImage, forKey: kCIInputImageKey)
                filterEye.setValue(retImage, forKey: kCIInputBackgroundImageKey)
                retImage = filterEye.outputImage!
                
                
                NSLog("Right eye %g %g", f.rightEyePosition.x, f.rightEyePosition.y);
            }
            if (f.hasMouthPosition) {
                var mouthImage = pic2
                let scale = CGAffineTransform(scaleX: 0.75, y: 0.75)
                let translation = CGAffineTransform(translationX: f.mouthPosition.x - 140, y: f.mouthPosition.y - 225)
                let affineMatrix = scale.concatenating(translation)
                
                let transformFilter = CIFilter(name: "CIAffineTransform")!
                transformFilter.setValue(mouthImage, forKey: "inputImage")
                transformFilter.setValue(NSValue(cgAffineTransform: affineMatrix), forKey: "inputTransform")
                mouthImage = transformFilter.outputImage!
                
                let filterMouth = CIFilter(name:"CISourceOverCompositing")!
                filterMouth.setValue(mouthImage, forKey: kCIInputImageKey)
                filterMouth.setValue(retImage, forKey: kCIInputBackgroundImageKey)
                retImage = filterMouth.outputImage!
                
                
                NSLog("Mouth %g %g", f.mouthPosition.x, f.mouthPosition.y);
            }
        }
        return retImage
    }
    
    func getFaces(_ img:CIImage) -> [CIFaceFeature]{
        // this ungodly mess makes sure the image is the correct orientation
        let optsFace = [CIDetectorImageOrientation:self.videoManager.ciOrientation]
        // get Face Features
        return self.detector.features(in: img, options: optsFace) as! [CIFaceFeature]
        
    }
}

