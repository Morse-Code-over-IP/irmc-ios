//
//  Bluetooth.h
//  Morse
//
//  Created by Dr. Gerolf Ziegenhain on 14.02.15.
//  Copyright (c) 2015 Dr. Gerolf Ziegenhain. All rights reserved.
//
//  Contains code from a low energy bluetooth tutorial by Owen Lacy Brown


//  The stuff below depends on nRF8001 arduino code in another repo ;)


#ifndef Morse_Bluetooth_h
#define Morse_Bluetooth_h

#import <Foundation/Foundation.h>
#import <CoreBluetooth/CoreBluetooth.h>

/* Services & Characteristics UUIDs for nRF8001 */

// icd: https://github.com/michaelkroll/BLE-Shield/blob/master/firmware/BLE-Shield-v2.0.0/BLE-Shield_gatt.xml
// icd nrf8001: https://devzone.nordicsemi.com/documentation/nrf51/6.0.0/s110/html/a00066.html

#define UART_SERVICE_UUID           [CBUUID UUIDWithString:@"6E400001-B5A3-F393-E0A9-E50E24DCCA9E"]
#define TX_CHARACTERISTIC_UUID      [CBUUID UUIDWithString:@"6E400002-B5A3-F393-E0A9-E50E24DCCA9E"]
#define RX_CHARACTERISTIC_UUID      [CBUUID UUIDWithString:@"6E400003-B5A3-F393-E0A9-E50E24DCCA9E"]

/* Notifications */
static NSString* const RWT_BLE_SERVICE_CHANGED_STATUS_NOTIFICATION = @"kBLEServiceChangedStatusNotification";
static NSString* const THERE_IS_DATA = @"Thereisdata";



@interface BTService : NSObject <CBPeripheralDelegate>

- (instancetype)initWithPeripheral:(CBPeripheral *)peripheral;
- (void)reset;
- (void)startDiscoveringServices;

@end


@interface BTDiscovery : NSObject <CBCentralManagerDelegate>
+ (instancetype)sharedInstance;
@property (strong, nonatomic) BTService *bleService;
@end



#endif



