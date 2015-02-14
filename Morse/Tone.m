//
//  Tone.m
//  Morse
//
//  Created by Dr. Gerolf Ziegenhain on 14.02.15.
//  Copyright (c) 2015 Dr. Gerolf Ziegenhain. All rights reserved.
//

#import <Foundation/Foundation.h>

#import <AudioToolbox/AudioToolbox.h>
#import <AVFoundation/AVFoundation.h>

#include "Tone.h"


OSStatus RenderTone(
                    void *inRefCon,
                    AudioUnitRenderActionFlags 	*ioActionFlags,
                    const AudioTimeStamp 		*inTimeStamp,
                    UInt32 						inBusNumber,
                    UInt32 						inNumberFrames,
                    AudioBufferList 			*ioData)

{
    // Fixed amplitude is good enough for our purposes
    const double amplitude = 0.25;
    
    double theta;
    double theta_increment = 2.0 * M_PI * FREQUENCY / SAMPLERATE;
    
    // This is a mono tone generator so we only need the first buffer
    const int channel = 0;
    Float32 *buffer = (Float32 *)ioData->mBuffers[channel].mData;
    
    // Generate the samples
    for (UInt32 frame = 0; frame < inNumberFrames; frame++)
    {
        buffer[frame] = sin(theta) * amplitude;
        
        theta += theta_increment;
        if (theta > 2.0 * M_PI)
        {
            theta -= 2.0 * M_PI;
        }
    }
    
    return noErr;
}


