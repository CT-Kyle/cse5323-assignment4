//
//  OpenCVBridgeSub.m
//  ImageLab
//
//  Created by Eric Larson on 10/4/16.
//  Copyright © 2016 Eric Larson. All rights reserved.
//

#import "OpenCVBridgeSub.h"
#import "AVFoundation/AVFoundation.h"

#define BUFFER_SIZE 1024
#define WINDOW_SIZE 12


using namespace cv;

@interface OpenCVBridgeSub()
@property (nonatomic) cv::Mat image;
@property float lastVal;
@property float lastVal2;
@property bool upLast;
@end

@implementation OpenCVBridgeSub
@dynamic image;

-(void)processImage{
    cv::Mat image_copy;
    char text[50];
    Scalar avgPixelIntensity;
    cv::Mat image = self.image;
    
    cvtColor(image, image_copy, CV_BGRA2BGR); // get rid of alpha for processing
    avgPixelIntensity = cv::mean( image_copy );
    
    float rVal = ((float)avgPixelIntensity.val[2] + self.lastVal + self.lastVal2) / 3.0;
    float dif = rVal - self.lastVal;
    float noiseFilter = 0.02;
    if (fabsf(dif) < noiseFilter) {
        // Do nothing
    } else if (dif > 0.0) {
        NSLog(@"up");
        sprintf(text,"");
        cv::putText(image, text, cv::Point(100, 100), FONT_HERSHEY_PLAIN, 1.25, Scalar::all(255), 1, 2);
        self.upLast = true;
    } else {
        NSLog(@"down");
        if (self.upLast == true) {
            sprintf(text,"Ba-bump");
            cv::putText(image, text, cv::Point(100, 100), FONT_HERSHEY_PLAIN, 1.25, Scalar::all(255), 1, 2);
        }
        self.upLast = false;
    }
    
    self.lastVal2 = self.lastVal;
    self.lastVal = rVal;
    
    self.image = image;
}

-(instancetype) init {
    self = [super init];
    self.lastVal = 0.0;
    self.lastVal2 = 0.0;
    self.upLast = true;
    return self;
}

@end
