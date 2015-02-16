
//  ViewController.m
//  Morse
//
//  Created by Dr. Gerolf Ziegenhain on 05.01.15.
//  Copyright (c) 2015 Dr. Gerolf Ziegenhain. All rights reserved.
//

#import "ViewController.h"
#import <AudioToolbox/AudioToolbox.h>
#import <AVFoundation/AVFoundation.h>
#import <netdb.h>
#import <netinet/in.h>
#import <netinet6/in6.h>
#import <arpa/inet.h>


#include "cwprotocol.h"
#include "cwcom.h"
#include "Bluetooth.h"
#include "Tone.h"


//#undef DEBUG
//#define DEBUG_NET
//#define DEBUG_TIMER
//#define DEBUG_TX
//#define SCROLLVIEWLOG
#define NOSIDETONE

//#define TUTI // AV player for sound

void ToneInterruptionListener(void *inClientData, UInt32 inInterruptionState)
{
    ViewController *vviewController = (__bridge ViewController *)inClientData;
    [vviewController stop];
}

@interface ViewController ()

@end

@implementation ViewController
@synthesize txt_server, txt_status, txt_channel, txt_id, txt_version;
@synthesize scr_view;
@synthesize webview;
@synthesize sw_connect, sw_circuit, sw_sounder;
@synthesize enter_id, enter_channel;
@synthesize mybutton;

//FIXME: This method can go into cwcom. - abstract from socket methods
// connect to server and send my id.
- (void)
identifyclient
{
    tx_sequence++;
    id_packet.sequence = tx_sequence;

    NSData *cc = [NSData dataWithBytes:&connect_packet length:sizeof(connect_packet)];
    NSData *ii = [NSData dataWithBytes:&id_packet length:sizeof(id_packet)];

    [udpSocket sendData:cc toHost:host port:port withTimeout:-1 tag:tx_sequence];
    [udpSocket sendData:ii toHost:host port:port withTimeout:-1 tag:tx_sequence];
}


//FIXME: This method can go into cwcom. - abstract from socket methods
- (void)connectMorse
{
    NSLog(@"Connect to server");
    
    char *id = (char *)[enter_id.text UTF8String];
    int channel = atoi([enter_channel.text UTF8String]);
    
    if (strcmp(id,"")==0 || channel == 0 ||channel > MAX_CHANNEL) {
        NSLog(@"Connect only with ID and channel");
        [self disconnectMorse];
        return;
    }
    
    prepare_id (&id_packet, id);
    prepare_tx (&tx_data_packet, id);
    connect_packet.channel = channel;
    
    txt_server.text = [NSString stringWithFormat:@"srv: %@:%d", host, port];
    
    udpSocket = [[GCDAsyncUdpSocket alloc] initWithDelegate:self delegateQueue:dispatch_get_main_queue()];
    
    NSError *error = nil;
    if (![udpSocket bindToPort:0 error:&error])
    {
        NSLog(@"error");
        return;
    }
    if (![udpSocket beginReceiving:&error])
    {
        NSLog(@"error");
        return;
    }
    
    [self identifyclient];
    
    // Start Keepalive timer
    myTimer = [NSTimer scheduledTimerWithTimeInterval: KEEPALIVE_CYCLE/1000 target: self selector: @selector(sendkeepalive:) userInfo: nil repeats: YES];
    
    connect = CONNECTED;
}

- (void)disconnectMorse
{
    NSLog(@"Disconnect from server");
    // Stop keepalive timer
    [myTimer invalidate]; //FIXME: This method can go into cwcom.
    txt_server.text = @"NONE";
    //udpSocket.finalize;
    connect = DISCONNECTED;
    [sw_connect setOn:false];
}

- (void)createToneUnit
{
    NSLog(@"Create tone Unit");
    // Configure the search parameters to find the default playback output unit
    // (called the kAudioUnitSubType_RemoteIO on iOS but
    // kAudioUnitSubType_DefaultOutput on Mac OS X)
    AudioComponentDescription defaultOutputDescription;
    defaultOutputDescription.componentType = kAudioUnitType_Output;
    defaultOutputDescription.componentSubType = kAudioUnitSubType_RemoteIO;
    defaultOutputDescription.componentManufacturer = kAudioUnitManufacturer_Apple;
    defaultOutputDescription.componentFlags = 0;
    defaultOutputDescription.componentFlagsMask = 0;
    
    // Get the default playback output unit
    AudioComponent defaultOutput = AudioComponentFindNext(NULL, &defaultOutputDescription);
    NSAssert(defaultOutput, @"Can't find default output");
    
    // Create a new unit based on this that we'll use for output
    OSErr err = AudioComponentInstanceNew(defaultOutput, &toneUnit);
    NSAssert1(toneUnit, @"Error creating unit: %hd", err);
    
    // Set our tone rendering function on the unit
    AURenderCallbackStruct input;
    input.inputProc = RenderTone;
    input.inputProcRefCon = (__bridge void *)(self);
    err = AudioUnitSetProperty(toneUnit,
                               kAudioUnitProperty_SetRenderCallback,
                               kAudioUnitScope_Input,
                               0,
                               &input,
                               sizeof(input));
    NSAssert1(err == noErr, @"Error setting callback: %hd", err);
    
    // Set the format to 32 bit, single channel, floating point, linear PCM
    const int four_bytes_per_float = 4;
    const int eight_bits_per_byte = 8;
    AudioStreamBasicDescription streamFormat;
    streamFormat.mSampleRate = SAMPLERATE;
    streamFormat.mFormatID = kAudioFormatLinearPCM;
    streamFormat.mFormatFlags =
    kAudioFormatFlagsNativeFloatPacked | kAudioFormatFlagIsNonInterleaved;
    streamFormat.mBytesPerPacket = four_bytes_per_float;
    streamFormat.mFramesPerPacket = 1;
    streamFormat.mBytesPerFrame = four_bytes_per_float;
    streamFormat.mChannelsPerFrame = 1;
    streamFormat.mBitsPerChannel = four_bytes_per_float * eight_bits_per_byte;
    err = AudioUnitSetProperty (toneUnit,
                                kAudioUnitProperty_StreamFormat,
                                kAudioUnitScope_Input,
                                0,
                                &streamFormat,
                                sizeof(AudioStreamBasicDescription));
    NSAssert1(err == noErr, @"Error setting stream format: %hd", err);
}

- (void)inittone
{
    NSLog(@"Starting tone Unit");

    [self createToneUnit];
    
    // Stop changing parameters on the unit
    OSErr err = AudioUnitInitialize(toneUnit);
    NSAssert1(err == noErr, @"Error initializing unit: %hd", err); // FIXME: we can use this for other quality stuff
}

- (void)stoptone
{
    NSLog(@"Stopping tone Unit");
    if (!toneUnit) return;
    AudioOutputUnitStop(toneUnit);
    AudioUnitUninitialize(toneUnit);
    AudioComponentInstanceDispose(toneUnit);
    toneUnit = nil;
}

- (void)beep:(double)duration_ms
{

    
    if (!toneUnit) [self inittone];

    if (sounder == true)
    {
        [self play_click];
        usleep(abs(duration_ms)*1000.);
        [self play_clack];
    }
    else
    {
#ifdef TUTI
        [audioPlayer play];
        usleep(abs(duration_ms)*1000.);
        [audioPlayer pause];
        return;
#endif
        OSErr err = AudioOutputUnitStart(toneUnit);
        NSAssert1(err == noErr, @"Error starting unit: %hd", err);
        usleep(abs(duration_ms)*1000.);
        AudioOutputUnitStop(toneUnit);
    }
}

//FIXME: This method can go into cwcom.
- (void)initCWvars
{
    NSLog(@"Init CW Vars");
    connect_packet.channel = DEFAULT_CHANNEL;
    connect_packet.command = CON;
    disconnect_packet.channel = 0;
    disconnect_packet.command = DIS;
    tx_sequence = 0;
    last_message = 0;
    tx_timeout = 0;
    last_message = 0;
    circuit = LATCHED;
    connect = DISCONNECTED;
    
    host = @SERVERNAME_MORSE; //@SERVERNAME_SOUNDER;
    port = PORT;

    // init id selector
    enter_id.placeholder = @"iOS/DG6FL, intl. Morse";
    enter_channel.placeholder = @"33";
    
    sounder = false;
    
}

// This method is called once we click inside the textField
-(void)textFieldDidBeginEditing:(UITextField *)ff{
#ifdef DEBUG
    NSLog(@"Text field did begin editing");
#endif
    [self disconnectMorse];
}

// This method is called once we complete editing
-(void)textFieldDidEndEditing:(UITextField *)ff{
#ifdef DEBUG
    NSLog(@"Text field ended editing");
#endif
    [sw_connect setOn:true];
    [self connectMorse];
}

// This method enables or disables the processing of return key
-(BOOL) textFieldShouldReturn:(UITextField *)ff{
    [ff resignFirstResponder];
    return YES;
}

- (void)switchcircuit
{
    if (circuit == LATCHED)
    {
        [self unlatch];
    }
    else
    {
        [self latch];
    }
}

-(void) switchconnect
{
    if (connect == CONNECTED)
    {
        [self disconnectMorse];
    }
    else
    {
        [self connectMorse];
    }
}

-(void) switchsounder
{
    NSLog(@"switch sounder");
    if (sounder == true)
    {
        sounder = false;
        UIImage *image2 = [UIImage imageNamed:@"key.png"];
        [mybutton setBackgroundImage:image2 forState:UIControlStateNormal];
      //  [self disconnectMorse]; // FIXME: switch servers
     //   host = @SERVERNAME_MORSE;
      //  [self connectMorse];
    }
    else
    {
        sounder = true;
        UIImage *image2 = [UIImage imageNamed:@"kob2.png"];
        [mybutton setBackgroundImage:image2 forState:UIControlStateNormal];
      //  [self disconnectMorse];
      //  host = @SERVERNAME_SOUNDER;
      //  [self connectMorse];
    }
}

- (void)viewDidLoad {
    NSLog(@"Load View");
    
    [super viewDidLoad];
    // Do any additional setup after loading the view, typically from a nib.
    
#pragma GCC diagnostic push // I know that this does not work!
#pragma GCC diagnostic ignored "-Wdeprecated"
    OSStatus result = AudioSessionInitialize(NULL, NULL, ToneInterruptionListener, (__bridge void *)(self));
    if (result == kAudioSessionNoError)
    {
        UInt32 sessionCategory = kAudioSessionCategory_MediaPlayback;
        AudioSessionSetProperty(kAudioSessionProperty_AudioCategory, sizeof(sessionCategory), &sessionCategory);
    }
    
    // set the buffer duration to 5 ms
    // set preferred buffer size
    Float32 preferredBufferSize = 5./1000.; // in seconds
    result = AudioSessionSetProperty(kAudioSessionProperty_PreferredHardwareIOBufferDuration, sizeof(preferredBufferSize), &preferredBufferSize);
    
    // get actual buffer size
    Float32 audioBufferSize;
    UInt32 size = sizeof (audioBufferSize);
    result = AudioSessionGetProperty(kAudioSessionProperty_CurrentHardwareIOBufferDuration, &size, &audioBufferSize);
    
    AudioSessionSetActive(true);
#pragma GCC diagnostic pop

    // Key text button
    UIImage *image2 = [UIImage imageNamed:@"key.png"];
    [mybutton setBackgroundImage:image2 forState:UIControlStateNormal];
    [mybutton addTarget:self action:@selector(buttonIsDown) forControlEvents:UIControlEventTouchDown];
    [mybutton addTarget:self action:@selector(buttonWasReleased) forControlEvents:UIControlEventTouchUpInside];
    
    // (Un-)Latch text switch
    [sw_circuit addTarget:self action:@selector(switchcircuit) forControlEvents:UIControlEventValueChanged];

    // Connect to server switch
    [sw_connect addTarget:self action:@selector(switchconnect) forControlEvents:UIControlEventValueChanged];
    [sw_connect setOn:false];
    
    // sounder switch
    [sw_sounder addTarget:self action:@selector(switchsounder) forControlEvents:UIControlEventValueChanged];
    [sw_sounder setOn:false];
    
    // initialize vars
    [self initCWvars];
    [self inittone];
    [self displaywebstuff];

    // Starting bluetooth for external key
    NSLog(@"Starting bluetooth");
    // Watch Bluetooth connection
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(btconnectionChanged:) name:RWT_BLE_SERVICE_CHANGED_STATUS_NOTIFICATION object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(btdata:) name:THERE_IS_DATA object:nil];
    // Start the Bluetooth discovery process
    [BTDiscovery sharedInstance];
    
#ifdef TUTI
    [self initsound]; // gz now
#endif
    
    enter_id.delegate = self;
    enter_channel.delegate = self;

#ifdef SCROLLVIEWLOG
    scr_view.editable = false;
    scr_view.text = @" ";
    scr_view.scrollEnabled = true;
#endif
    NSString * appVersionString = [[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleShortVersionString"];
    NSString * appBuildString = [[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleVersion"];

    txt_version.text = [NSString stringWithFormat:@"Version: %@ (%@)", appVersionString, appBuildString];
}

- (void)btconnectionChanged:(NSNotification *)notification {
    // Connection status changed. Indicate on GUI.
    // some stuff could be done here...
    
}



-(void)displaywebstuff
{
    NSString *urlAddress = host;
#ifdef DEBUG
    NSLog(@"Webview:");
    //NSLog(host);
#endif
    NSURL *url = [NSURL URLWithString:urlAddress];
    NSURLRequest *requestObj = [NSURLRequest requestWithURL:url];
    [webview loadRequest:requestObj];
}

//FIXME: This method can go into cwcom.
- (void) message:(int) msg
{
    switch(msg){
        case 1:
            if(last_message == msg) return;
            if(last_message == 2) NSLog(@"\n");
            last_message = msg;
            txt_status.text =[NSString stringWithFormat:@"Transmitting\n"];
            break;
        case 2:
            if(last_message == msg && strncmp(last_sender, rx_data_packet.id, 3) == 0) return;
            else {
                if(last_message == 2) NSLog(@"\n");
                last_message = msg;
                strncpy(last_sender, rx_data_packet.id, 3);
                txt_status.text = [NSString stringWithFormat:@"recv: (%s).\n",rx_data_packet.id];
            }
            break;
        case 3:
            txt_status.text = [NSString stringWithFormat:@"latched by %s.\n",rx_data_packet.id];
            break;
        case 4:
            txt_status.text = [NSString stringWithFormat:@"unlatched by %s.\n",rx_data_packet.id];
            break;
        default:
            break;
    }
#ifdef SCROLLVIEWLOG
    scr_view.text = [txt_status.text stringByAppendingString:scr_view.text];
#endif
}

// FIXME: can go to sound
-(void)initsound
{
    NSError *error;
    NSURL *audioPath = [[NSBundle mainBundle] URLForResource:@"tut" withExtension:@"wav"];
    audioPlayer = [[AVAudioPlayer alloc] initWithContentsOfURL:audioPath error:&error];
    audioPlayer.numberOfLoops = -1;
    [audioPlayer prepareToPlay];
    //http://developer.limneos.net/?framework=AVFoundation.framework&header=AVPlayer.h
 
}

// FIXME: can go to sound
- (void)play_clack
{
    NSLog(@"play clack");
    SystemSoundID completeSound;
    NSURL *audioPath = [[NSBundle mainBundle] URLForResource:@"clack48" withExtension:@"wav"];
    AudioServicesCreateSystemSoundID((__bridge CFURLRef)audioPath, &completeSound);
    AudioServicesPlaySystemSound (completeSound);
}
// FIXME: can go to sound
- (void)play_click
{
    NSLog(@"play click");
    SystemSoundID completeSound;
    NSURL *audioPath = [[NSBundle mainBundle] URLForResource:@"click48" withExtension:@"wav"];
    AudioServicesCreateSystemSoundID((__bridge CFURLRef)audioPath, &completeSound);
    AudioServicesPlaySystemSound (completeSound);
}

//FIXME: This method can go into cwcom. - modify for (a) recv (b) process
- (void)udpSocket:(GCDAsyncUdpSocket *)sock didReceiveData:(NSData *)data fromAddress:(NSData *)address
withFilterContext:(id)filterContext
{
    int i;
    int translate = 0;
    int audio_status = 1;
    
    [data getBytes:&rx_data_packet length:sizeof(rx_data_packet)];
#ifdef DEBUG_NET
    NSLog(@"length: %i\n", rx_data_packet.length);
    NSLog(@"id: %s\n", rx_data_packet.id);
    NSLog(@"sequence no.: %i\n", rx_data_packet.sequence);
    NSLog(@"version: %s\n", rx_data_packet.status);
    NSLog(@"n: %i\n", rx_data_packet.n);
    NSLog(@"code:\n");
    for(i = 0; i < SIZE_CODE; i++)NSLog(@"%i ", rx_data_packet.code[i]); NSLog(@"\n");
#endif
    txt_status.text = [NSString stringWithFormat:@"recv from: %s\n", rx_data_packet.id];
#ifdef SCROLLVIEWLOG
    scr_view.text = [txt_status.text stringByAppendingString:scr_view.text];
#endif
        if(rx_data_packet.n > 0 && rx_sequence != rx_data_packet.sequence){
            [self message:2];
            if(translate == 1){
                txt_status.text = [NSString stringWithFormat:@"%s\n",rx_data_packet.status];
#ifdef SCROLLVIEWLOG
                scr_view.text = [txt_status.text stringByAppendingString:scr_view.text];
#endif
            }
            rx_sequence = rx_data_packet.sequence;
            for(i = 0; i < rx_data_packet.n; i++){
                switch(rx_data_packet.code[i]){
                    case 1:
                        [self message:3];
                        break;
                    case 2:
                        [self message:4];
                        break;
                    default:
                        if(audio_status == 1)
                        {
                            int length = rx_data_packet.code[i];
                            if(length == 0 || abs(length) > 2000) { // FIXME: magic number
                            }
                            else
                            {
                                if(length < 0) {
                                    usleep(abs(length)*1000.); // pause
                                }
                                else
                                {
                                    [self beep:(abs(length))];
                                }
                            }
                        }
                        break;
                }
            }
        }
}


- (void)didReceiveMemoryWarning {
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}

- (void)stop
{
    [self disconnectMorse];
    [self stoptone];
}

- (void)viewDidUnload {
    [self stop];
    AudioSessionSetActive(false);
    
}

- (void)viewDidAppear:(BOOL)animated {
}

- (void)dealloc {
    //FIXME: NAME RWT_BLE_SERVICE_CHANGED_STATUS_NOTIFICATION
    [[NSNotificationCenter defaultCenter] removeObserver:self name:THERE_IS_DATA object:nil];
    [[NSNotificationCenter defaultCenter] removeObserver:self name:RWT_BLE_SERVICE_CHANGED_STATUS_NOTIFICATION object:nil];

}

- (void)viewWillDisappear:(BOOL)animated
{
}

//#define BEEPI


- (void)btdata:(NSNotification *)notification {
    NSString* ss = (notification.userInfo)[@"data"];
    //NSLog(ss);
    
    if ([ss isEqualToString:@"v"]) {
        key_press_t1 = fastclock();
#ifndef NOSIDETONE
#ifdef TUTI
        [audioPlayer play];
#else
    if (sounder == true)
        [self play_click];
    else
        AudioOutputUnitStart(toneUnit);
#endif
#endif
        
        tx_timeout = 0;
        int timing = (int) ((key_press_t1 - key_release_t1) * -1); // negative timing
        if (timing > TX_WAIT) timing = TX_WAIT; // limit to timeout
        tx_data_packet.n++;
        tx_data_packet.code[tx_data_packet.n - 1] = timing;
#ifdef DEBUG_TX
        NSLog(@"timing: %d", timing);
#endif
        [self message:1];
        
        
    }
    if ([ss isEqualToString:@"k"])
    {
        
        key_release_t1 = fastclock();
#ifndef NOSIDETONE
#ifdef TUTI
        [audioPlayer pause];
#else
        if (sounder == true)
            [self play_clack];
        else
            AudioOutputUnitStop(toneUnit);
#endif
#endif
        int timing =(int) ((key_release_t1 - key_press_t1) * 1); // positive timing
        if (abs(timing) > TX_WAIT) timing = -TX_WAIT; // limit to timeout FIXME this is the negative part
        if (tx_data_packet.n == SIZE_CODE) NSLog(@"warning: packet is full");
        tx_data_packet.n++;
        tx_data_packet.code[tx_data_packet.n - 1] = timing;
#ifdef DEBUG_TX
        NSLog(@"timing: %d", timing);
#endif
        
        [self send_data];
    }
}

//FIXME: This method can go into cwcom. - modify for buttonup
-(void)buttonIsDown
{
    key_press_t1 = fastclock();

    if (sounder == true)
        [self play_click];
    else
        AudioOutputUnitStart(toneUnit);
    
    tx_timeout = 0;
    int timing = (int) ((key_press_t1 - key_release_t1) * -1); // negative timing
    if (timing > TX_WAIT) timing = TX_WAIT; // limit to timeout
    tx_data_packet.n++;
    tx_data_packet.code[tx_data_packet.n - 1] = timing;
#ifdef DEBUG_TX
    NSLog(@"timing: %d", timing);
#endif
    [self message:1];
}

//FIXME: This method can go into cwcom. - modify for buttondown
-(void)buttonWasReleased
{
    key_release_t1 = fastclock();
    if (sounder == true)
        [self play_clack];
    else
        AudioOutputUnitStop(toneUnit);

    int timing =(int) ((key_release_t1 - key_press_t1) * 1); // positive timing
    if (abs(timing) > TX_WAIT) timing = -TX_WAIT; // limit to timeout FIXME this is the negative part
    if (tx_data_packet.n == SIZE_CODE) NSLog(@"warning: packet is full");
    tx_data_packet.n++;
    tx_data_packet.code[tx_data_packet.n - 1] = timing;
#ifdef DEBUG_TX
    NSLog(@"timing: %d", timing);
#endif

    [self send_data];
}

//FIXME: This method can go into cwcom.
-(void) send_data
{
#ifdef DEBUG_TX
    NSLog(@"Send udp data");
#endif
    if (connect == DISCONNECTED) return; // do not continue when disconnected
    //if (tx_data_packet.code[0]>0) return; // assert first pause

    //if(tx_data_packet.n == 2 ) {NSLog(@"tx_data.n eq 2");return;} // assert only two packages // FIXME??
    if (tx_data_packet.n <= 1) {return;}
    
    tx_sequence++;
    tx_data_packet.sequence = tx_sequence;

    [self send_tx_packet];
    tx_data_packet.n = 0;
}

//FIXME: This method can go into cwcom.
- (void) send_tx_packet
{
    int i;
    NSData *cc = [NSData dataWithBytes:&tx_data_packet length:sizeof(tx_data_packet)];
    for(i = 0; i < CW_SEND_RETRIES; i++) [udpSocket sendData:cc toHost:host port:port withTimeout:-1 tag:tx_sequence];
#ifdef DEBUG_NET
    NSLog(@"sent seq %d n %d (%d,%d).", tx_sequence, tx_data_packet.n,
          tx_data_packet.code[0] ,
          tx_data_packet.code[1]
          );
#endif
}

//FIXME: This method can go into cwcom.
- (void)latch
{
    NSLog(@"latch");

    tx_sequence++; // FIXME: This is a special packet an can go into networking.
    tx_data_packet.sequence = tx_sequence;
    tx_data_packet.code[0] = -1;
    tx_data_packet.code[1] = 1;
    tx_data_packet.n = 2;
    
    [self send_tx_packet];
    
    tx_data_packet.n = 0;
    circuit = LATCHED;
    [self play_click];

#ifdef NOTIFICATIONS //TODO not implemented yet
    //[ postNotification:@"Hello World"];
#endif
}

//FIXME: This method can go into cwcom.
-(void) unlatch
{
    NSLog(@"unlatch");

    tx_sequence++;
    tx_data_packet.sequence = tx_sequence;
    tx_data_packet.code[0] = -1;
    tx_data_packet.code[1] = 2;
    tx_data_packet.n = 2;
    
    [self send_tx_packet];
    
    tx_data_packet.n = 0;
    
    circuit = UNLATCHED;
    [self play_clack];
}

-(void) sendkeepalive:(NSTimer*)t
{
#ifdef DEBUG_TIMER
    NSLog(@"Keepalive");
#endif
    [self identifyclient];
}

-(void) calli
{
    NSLog(@"Calli");
}


 /*
  
  http://kob.sdf.org/morsekob/interface.htm#portpins
  RS232     DB9     Function    
  DTR       4       Manual Key / paddle common
  DSR       6       Manual key / dot paddle
  CTS       8       Dash paddle
  RTS       7       Sounder output
  SG        5       Sounder ground
 
 */

@end
