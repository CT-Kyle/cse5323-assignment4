//
//  VideoAnalgesic.swift
//  VideoAnalgesicTest
//
//  Created by Eric Larson on 2015.
//  Copyright (c) 2015 Eric Larson. All rights reserved.
//

import Foundation
import GLKit
import AVFoundation
import CoreImage


typealias ProcessBlock = ( _ imageInput : CIImage ) -> (CIImage)

class VideoAnalgesic: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate, AVCaptureAudioDataOutputSampleBufferDelegate {
    
    fileprivate var captureSessionQueue: DispatchQueue
    fileprivate var devicePosition: AVCaptureDevicePosition
    fileprivate var window:UIWindow??
    var videoPreviewView:GLKView
    var ciOrientation = 1
    fileprivate var _eaglContext:EAGLContext!
    fileprivate var ciContext:CIContext!
    fileprivate var videoPreviewViewBounds:CGRect = CGRect.zero
    fileprivate var processBlock:ProcessBlock? = nil
    fileprivate var videoDevice: AVCaptureDevice? = nil
    fileprivate var captureSession:AVCaptureSession? = nil
    fileprivate var preset:String? = AVCaptureSessionPresetMedium
    fileprivate var captureOrient:AVCaptureVideoOrientation? = nil
    fileprivate var _isRunning:Bool = false
    var transform : CGAffineTransform = CGAffineTransform.identity

    var isRunning:Bool {
        get {
            return self._isRunning
        }
    }
    
    // singleton method 
    class var sharedInstance: VideoAnalgesic {
        
        struct Static {
            static let instance: VideoAnalgesic = VideoAnalgesic()
        }
        return Static.instance
    }
    
    // for setting the filters pipeline (or whatever processing you are doing)
    func setProcessingBlock(_ newProcessBlock:@escaping ProcessBlock)
    {
        self.processBlock = newProcessBlock // to find out: does Swift do a deep copy??
    }
    
    // for setting the camera we should use
    func setCameraPosition(_ position: AVCaptureDevicePosition){
        // AVCaptureDevicePosition.Back
        // AVCaptureDevicePosition.Front
        if(position != self.devicePosition){
            self.devicePosition = position;
            if(self.isRunning){
                self.stop()
                self.start()
            }
        }
    }
    
    // for setting the camera we should use
    func toggleCameraPosition(){
        // AVCaptureDevicePosition.Back
        // AVCaptureDevicePosition.Front
        switch self.devicePosition{
        case AVCaptureDevicePosition.back:
            self.devicePosition = AVCaptureDevicePosition.front
        case AVCaptureDevicePosition.front:
            self.devicePosition = AVCaptureDevicePosition.back
        default:
            self.devicePosition = AVCaptureDevicePosition.front
        }
        
        if(self.isRunning){
            self.stop()
            self.start()
        }
    }
    
    // for setting the image quality
    func setPreset(_ preset: String){
        // AVCaptureSessionPresetPhoto
        // AVCaptureSessionPresetHigh
        // AVCaptureSessionPresetMedium <- default
        // AVCaptureSessionPresetLow
        // AVCaptureSessionPreset320x240
        // AVCaptureSessionPreset352x288
        // AVCaptureSessionPreset640x480
        // AVCaptureSessionPreset960x540
        // AVCaptureSessionPreset1280x720
        // AVCaptureSessionPresetiFrame960x540
        // AVCaptureSessionPresetiFrame1280x720
        if(preset != self.preset){
            self.preset = preset;
            if(self.isRunning){
                self.stop()
                self.start()
            }
        }
    }
    
    func getCIContext()->(CIContext?){
        if let context = self.ciContext{
            return context;
        }
        return nil;
    }
    
    func getImageOrientationFromUIOrientation(_ interfaceOrientation:UIInterfaceOrientation)->(Int){
        var ciOrientation = 1;
        
        switch interfaceOrientation{
        case UIInterfaceOrientation.portrait:
            ciOrientation = 5
        case UIInterfaceOrientation.portraitUpsideDown:
            ciOrientation = 7
        case UIInterfaceOrientation.landscapeLeft:
            ciOrientation = 1
        case UIInterfaceOrientation.landscapeRight:
            ciOrientation = 3
        default:
            ciOrientation = 1
        }
        
        return ciOrientation
    }
    
    func shutdown(){
        EAGLContext.setCurrent(self._eaglContext)
        self.processBlock = nil
        self.stop()
    }
    
    override init() {
        
        captureSessionQueue = DispatchQueue(label: "capture_session_queue", attributes: [])
        devicePosition = AVCaptureDevicePosition.back
        self.window = UIApplication.shared.delegate?.window
        
        _eaglContext = EAGLContext(api: EAGLRenderingAPI.openGLES2)
        //        if _eaglContext==nil{
        //            NSLog("Attempting to fall back on OpenGL 2.0")
        //            _eaglContext = EAGLContext(API: EAGLRenderingAPI.OpenGLES2)
        //        }
        transform = CGAffineTransform.identity
        if _eaglContext != nil{
            videoPreviewView = GLKView(frame: window!!.bounds, context: _eaglContext)
            videoPreviewView.enableSetNeedsDisplay = false
            
            // because the native video image from the back camera is in UIDeviceOrientationLandscapeLeft (i.e. the home button is on the right), we need to apply a clockwise 90 degree transform so that we can draw the video preview as if we were in a landscape-oriented view; if you're using the front camera and you want to have a mirrored preview (so that the user is seeing themselves in the mirror), you need to apply an additional horizontal flip (by concatenating CGAffineTransformMakeScale(-1.0, 1.0) to the rotation transform)
            
            transform = transform.rotated(by: CGFloat(M_PI_2))
            if devicePosition == AVCaptureDevicePosition.front{
                transform = transform.concatenating(CGAffineTransform(scaleX: -1.0, y: 1.0))
            }
            videoPreviewView.transform = transform
            videoPreviewView.frame = window!!.bounds
            
            // we make our video preview view a subview of the window, and send it to the back; this makes FHViewController's view (and its UI elements) on top of the video preview, and also makes video preview unaffected by device rotation
            window!!.addSubview(videoPreviewView)
            window!!.sendSubview(toBack: videoPreviewView)
            
            
            // create the CIContext instance, note that this must be done after _videoPreviewView is properly set up
            ciContext = CIContext(eaglContext: _eaglContext)
            
            // bind the frame buffer to get the frame buffer width and height;
            // the bounds used by CIContext when drawing to a GLKView are in pixels (not points),
            // hence the need to read from the frame buffer's width and height;
            // in addition, since we will be accessing the bounds in another queue (_captureSessionQueue),
            // we want to obtain this piece of information so that we won't be
            // accessing _videoPreviewView's properties from another thread/queue
            videoPreviewView.bindDrawable()
            videoPreviewViewBounds = CGRect.zero
        }
        else{
            NSLog("Could not fall back on OpenGL 2.0, exiting")
            videoPreviewView = GLKView()
            videoPreviewViewBounds = CGRect.zero
        }

    
        super.init()
        

    }
    
    fileprivate func start_internal()->(){
        
        
        
        if (captureSession != nil){
            return; // we are already running, just return
        }
        
        NotificationCenter.default.addObserver(self,
            selector:#selector(VideoAnalgesic.updateOrientation),
            name:NSNotification.Name(rawValue: "UIApplicationDidChangeStatusBarOrientationNotification"),
            object:nil)
        
        captureSessionQueue.async{
            let error:NSError? = nil;
            
            // get the input device and also validate the settings
            let videoDevices = AVCaptureDeviceDiscoverySession(deviceTypes: [AVCaptureDeviceType.builtInWideAngleCamera],
                                                               mediaType: AVMediaTypeVideo,
                                                               position: self.devicePosition)
            
            
            let position = self.devicePosition;
            
            self.videoDevice = nil;
            for device in videoDevices!.devices {
                if ((device as AnyObject).position == position) {
                    self.videoDevice = device
                    break;
                }
            }
            
            // obtain device input
            let videoDeviceInput: AVCaptureDeviceInput = (try! AVCaptureDeviceInput(device: self.videoDevice))
            
            if (error != nil)
            {
                NSLog("Unable to obtain video device input, error: \(error)");
                return;
            }
            
            
            if (self.videoDevice?.supportsAVCaptureSessionPreset(self.preset!)==false)
            {
                NSLog("Capture session preset not supported by video device: \(self.preset)");
                return;
            }
            
            // CoreImage wants BGRA pixel format
            //var outputSettings = [kCVPixelBufferPixelFormatTypeKey:NSNumber.numberWithInteger(kCVPixelFormatType_32BGRA)]
            
            // create the capture session
            self.captureSession = AVCaptureSession()
            self.captureSession!.sessionPreset = self.preset;
            
            // create and configure video data output
            let videoDataOutput = AVCaptureVideoDataOutput()
            //videoDataOutput.videoSettings = outputSettings;
            videoDataOutput.alwaysDiscardsLateVideoFrames = true;
            videoDataOutput.setSampleBufferDelegate(self, queue:self.captureSessionQueue)
            
            // begin configure capture session
            if let capture = self.captureSession{
                capture.beginConfiguration()
                
                if (!capture.canAddOutput(videoDataOutput))
                {
                    return;
                }
                
                // connect the video device input and video data and still image outputs
                capture.addInput(videoDeviceInput as AVCaptureInput)
                capture.addOutput(videoDataOutput)
                
                capture.commitConfiguration()
                
                // then start everything
                capture.startRunning()
            }
        
            self.updateOrientation()
        }
    }
    
    func updateOrientation(){
        if !self._isRunning{
            return
        }
        
        DispatchQueue.main.async{
            
            switch (UIDevice.current.orientation, self.videoDevice!.position){
            case (UIDeviceOrientation.landscapeRight, AVCaptureDevicePosition.back):
                self.ciOrientation = 3
                self.transform = CGAffineTransform(rotationAngle: CGFloat(M_PI))
            case (UIDeviceOrientation.landscapeLeft, AVCaptureDevicePosition.back):
                self.ciOrientation = 1
                self.transform = CGAffineTransform.identity
            case (UIDeviceOrientation.landscapeLeft, AVCaptureDevicePosition.front):
                self.ciOrientation = 3
                self.transform = CGAffineTransform(rotationAngle: CGFloat(M_PI))
                self.transform = self.transform.concatenating(CGAffineTransform(scaleX: -1.0, y: 1.0))
            case (UIDeviceOrientation.landscapeRight, AVCaptureDevicePosition.front):
                self.ciOrientation = 1
                self.transform = CGAffineTransform.identity
                self.transform = self.transform.concatenating(CGAffineTransform(scaleX: -1.0, y: 1.0))
            case (UIDeviceOrientation.portraitUpsideDown, AVCaptureDevicePosition.back):
                self.ciOrientation = 7
                self.transform = CGAffineTransform(rotationAngle: CGFloat(3*M_PI_2))
            case (UIDeviceOrientation.portraitUpsideDown, AVCaptureDevicePosition.front):
                self.ciOrientation = 7
                self.transform = CGAffineTransform(rotationAngle: CGFloat(3*M_PI_2))
                self.transform = self.transform.concatenating(CGAffineTransform(scaleX: -1.0, y: 1.0))
            case (UIDeviceOrientation.portrait, AVCaptureDevicePosition.back):
                self.ciOrientation = 5
                self.transform = CGAffineTransform(rotationAngle: CGFloat(M_PI_2))
            case (UIDeviceOrientation.portrait, AVCaptureDevicePosition.front):
                self.ciOrientation = 5
                self.transform = CGAffineTransform(rotationAngle: CGFloat(-M_PI_2))
                self.transform = self.transform.concatenating(CGAffineTransform(scaleX: -1.0, y: -1.0))
            default:
                self.ciOrientation = 5
                self.transform = CGAffineTransform(rotationAngle: CGFloat(M_PI_2))
            }
            
            self.videoPreviewView.transform = self.transform
            self.videoPreviewView.frame = self.window!!.bounds
        }
    }
    
    func start(){
        
        self.videoPreviewViewBounds.size.width = CGFloat(self.videoPreviewView.drawableWidth)
        self.videoPreviewViewBounds.size.height = CGFloat(self.videoPreviewView.drawableHeight)
        
        
        // see if we have any video device
        let videoDevices = AVCaptureDeviceDiscoverySession(deviceTypes: [AVCaptureDeviceType.builtInWideAngleCamera],
                                                           mediaType: AVMediaTypeVideo,
                                                           position: self.devicePosition)
        if (videoDevices!.devices.count > 0)
        {
            self.start_internal()
            self._isRunning = true
        }
        else{
            NSLog("Could not start Analgesic video manager");
            NSLog("Be sure that you are running from an iOS device, not the simulator")
            self._isRunning = false;
        }
        
    }
    
    func stop(){
        if (self.captureSession==nil || self.captureSession!.isRunning==false){
            return
        }
        
        self.captureSession!.stopRunning()
        
        NotificationCenter.default.removeObserver(self,
            name: NSNotification.Name(rawValue: "UIApplicationDidChangeStatusBarOrientationNotification"), object: nil)
        
        self.captureSessionQueue.sync{
                NSLog("waiting for capture session to end")
        }
        NSLog("Done!")
        
        self.captureSession = nil
        self.videoDevice = nil
        self._isRunning = false
        
    }
    
    // video buffer delegate
    func captureOutput(_ captureOutput: AVCaptureOutput!, didOutputSampleBuffer sampleBuffer: CMSampleBuffer!, from connection: AVCaptureConnection!) {
        
        let imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer)
        let sourceImage = CIImage(cvPixelBuffer: imageBuffer! as CVPixelBuffer, options:nil)
        
        // run through a filter
        var filteredImage:CIImage! = nil;
        
        if(self.processBlock != nil){
            filteredImage=self.processBlock!(sourceImage)
        }
        
        let sourceExtent:CGRect = sourceImage.extent
        
        let sourceAspect = sourceExtent.size.width / sourceExtent.size.height;
        let previewAspect = self.videoPreviewViewBounds.size.width  / self.videoPreviewViewBounds.size.height;
        
        // we want to maintain the aspect ratio of the screen size, so we clip the video image
        var drawRect = sourceExtent
        if (sourceAspect > previewAspect)
        {
            // use full height of the video image, and center crop the width
            drawRect.origin.x += (drawRect.size.width - drawRect.size.height * previewAspect) / 2.0;
            drawRect.size.width = drawRect.size.height * previewAspect;
        }
        else
        {
            // use full width of the video image, and center crop the height
            drawRect.origin.y += (drawRect.size.height - drawRect.size.width / previewAspect) / 2.0;
            drawRect.size.height = drawRect.size.width / previewAspect;
        }
        
        if (filteredImage != nil)
        {
            DispatchQueue.main.async{
                
                self.videoPreviewView.bindDrawable()
                
                if (self._eaglContext != EAGLContext.current()){
                    EAGLContext.setCurrent(self._eaglContext)
                }
                
                // clear eagl view to grey
                glClearColor(0.5, 0.5, 0.5, 1.0);
                glClear(GLbitfield(GL_COLOR_BUFFER_BIT))
                
                // set the blend mode to "source over" so that CI will use that
                glEnable(GLenum(GL_BLEND))
                glBlendFunc(GLenum(GL_ONE), GLenum(GL_ONE_MINUS_SRC_ALPHA))
                
                
                if (filteredImage != nil){
                    self.ciContext.draw(filteredImage, in:self.videoPreviewViewBounds, from:drawRect)
                }
            
                self.videoPreviewView.display()
            }
        }

    }
    
    func toggleFlash()->(Bool){
        var isOn = false
        if let device = self.videoDevice{
            if (device.hasTorch && self.devicePosition == AVCaptureDevicePosition.back) {
                do {
                    try device.lockForConfiguration()
                } catch _ {
                }
                if (device.torchMode == AVCaptureTorchMode.on) {
                    device.torchMode = AVCaptureTorchMode.off
                } else {
                    do {
                        try device.setTorchModeOnWithLevel(1.0)
                        isOn = true
                    } catch _ {
                        isOn = false
                    }
                }
                device.unlockForConfiguration()
            }
        }
        return isOn
    }
    
    func setFPS(){
        if let device = self.videoDevice{
            if (self.devicePosition == AVCaptureDevicePosition.back) {
                do {
                    try device.lockForConfiguration()
                } catch _ {
                }
                
                // set to 120FPS
                device.activeVideoMaxFrameDuration = CMTimeMake(10, 600)
                device.activeVideoMinFrameDuration = CMTimeMake(10, 600)
                device.unlockForConfiguration()
            }
        }

    }


    func turnOnFlashwithLevel(_ level:Float) -> (Bool){
        var isOverHeating = false
        if let device = self.videoDevice{
            if (device.hasTorch && self.devicePosition == AVCaptureDevicePosition.back && level>0 && level<=1) {
                do {
                    try device.lockForConfiguration()
                } catch _ {
                }
                do {
                    try device.setTorchModeOnWithLevel(level)
                    isOverHeating = true
                } catch _ {
                    isOverHeating = false
                }
                device.unlockForConfiguration()
            }
        }
        return isOverHeating
    }
    
    
    func turnOffFlash(){
        if let device = self.videoDevice{
            if (device.hasTorch && device.torchMode == AVCaptureTorchMode.on) {
                do {
                    try device.lockForConfiguration()
                } catch _ {
                }
                device.torchMode = AVCaptureTorchMode.off
                device.unlockForConfiguration()
            }
        }
    }
    
    
}
