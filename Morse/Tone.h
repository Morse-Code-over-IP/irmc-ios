//
//  Tone.h
//  Morse
//
//  Created by Dr. Gerolf Ziegenhain on 14.02.15.
//  Copyright (c) 2015 Dr. Gerolf Ziegenhain. All rights reserved.
//

#ifndef Morse_Tone_h
#define Morse_Tone_h


#define FREQUENCY ((double)800)
#define SAMPLERATE ((double)44100)

OSStatus RenderTone(
                    void *inRefCon,
                    AudioUnitRenderActionFlags 	*ioActionFlags,
                    const AudioTimeStamp 		*inTimeStamp,
                    UInt32 						inBusNumber,
                    UInt32 						inNumberFrames,
                    AudioBufferList 			*ioData);



#endif


