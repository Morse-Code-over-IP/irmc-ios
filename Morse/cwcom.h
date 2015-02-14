//
//  cwcom.h
//  Morse
//
//  Created by Dr. Gerolf Ziegenhain on 14.02.15.
//  Copyright (c) 2015 Dr. Gerolf Ziegenhain. All rights reserved.
//

#ifndef Morse_cwcom_h
#define Morse_cwcom_h

#define SERVERNAME_MORSE "morsecode.dyndns.org"
#define SERVERNAME_SOUNDER "mtc-kob.dyndns.org"
#define PORT 7890

#define TX_WAIT  5000
#define TX_TIMEOUT 240.0

#define KEEPALIVE_CYCLE 100 //msec
#define NUMSEND 5

#define MAXDATASIZE 1024 // max number of bytes we can get at once
#define LATCHED 0
#define UNLATCHED 1
#define CONNECTED 0
#define DISCONNECTED 1


@interface cwcom : NSObject
@end

#endif
