//
//  OpenCVBridgeSub.m
//  ImageLab
//
//  Created by Eric Larson on 10/4/16.
//  Copyright © 2016 Eric Larson. All rights reserved.
//

#import "OpenCVBridgeSub.h"
#import "AVFoundation/AVFoundation.h"

#define NOISE_FILTER 0.02
#define BPM_DELTA_SECONDS 10.0
#define TREND_MIN 2
using namespace cv;

@interface OpenCVBridgeSub()
@property (nonatomic) cv::Mat image;
@property float lastVal;
@property float lastVal2;
@property int redTrend;
@property int downTrendCount;
@property bool upLast;
@property (strong, nonatomic) NSMutableArray* beatTimes;
@end

@implementation OpenCVBridgeSub
@synthesize beatTimes;
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
    
    bool didBeat = false;
    
    if (fabsf(dif) < NOISE_FILTER) {
        // Do nothing
    } else if (dif > 0.0) {
        NSLog(@"up");
        self.redTrend = self.redTrend < 0 ? 1 : self.redTrend += 1;
    } else {
        NSLog(@"down");
        
        if (self.redTrend >= TREND_MIN) {
            self.redTrend = -1;
        } else  if (self.redTrend < 0) {
            self.redTrend -= 1;
        } else {
            self.redTrend = 0;
        }
        
        if (self.redTrend == -TREND_MIN) {
            NSLog(@"ba-dump");
            didBeat = true;
            [self.beatTimes addObject:[NSDate date]];
        }
    }
    
    if (didBeat) {
        sprintf(text, "%.1f beat", [self getBPM]);
    } else {
        sprintf(text, "%.1f", [self getBPM]);
    }
    
    cv::putText(image, text, cv::Point(30, 30), FONT_HERSHEY_PLAIN, 0.80, Scalar::all(255), 1, 2);
    
    self.lastVal2 = self.lastVal;
    self.lastVal = rVal;
    
    self.image = image;
}

-(NSMutableArray*) beatTimes {
    if (beatTimes == nil) {
        beatTimes = [[NSMutableArray alloc] init];
    }
    return beatTimes;
}

-(float) getBPM {
    NSDate* lastBeat = self.beatTimes.lastObject;
    NSTimeInterval elapsedTime = 1.0;
    
    int i = (int)[self.beatTimes count] - 2;
    
    for (; i >= 0; --i) {
        elapsedTime = [lastBeat timeIntervalSinceDate:self.beatTimes[i]];
        if (elapsedTime > BPM_DELTA_SECONDS) {
            break;
        }
    }
    
    return ([self.beatTimes count] - i - 1) * 60.0 / elapsedTime;
}

-(instancetype) init {
    self = [super init];
    self.lastVal = 0.0;
    self.lastVal2 = 0.0;
    self.redTrend = 0;
    self.upLast = true;
    return self;
}

@end
