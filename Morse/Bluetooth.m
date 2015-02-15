//
//  Bluetooth.m
//  Morse
//
//  Created by Dr. Gerolf Ziegenhain on 14.02.15.
//  Copyright (c) 2015 Dr. Gerolf Ziegenhain. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "Bluetooth.h"

//#define DEBUG_BT

@interface BTDiscovery ()
@property (strong, nonatomic) CBCentralManager *centralManager;
@property (strong, nonatomic) CBPeripheral *peripheralBLE;
@end

@implementation BTDiscovery

+ (instancetype)sharedInstance {
    static BTDiscovery *this = nil;
    static dispatch_once_t onceToken;
    
    dispatch_once(&onceToken, ^{
        this = [[BTDiscovery alloc] init];
    });
    
    return this;
}

- (instancetype)init {
    self = [super init];
    NSLog(@"bt discovery init");
    if (self) {
        dispatch_queue_t centralQueue = dispatch_queue_create("com.ziegenhain", DISPATCH_QUEUE_SERIAL);
        self.centralManager = [[CBCentralManager alloc] initWithDelegate:self queue:centralQueue options:nil];
        
        self.bleService = nil;
    }
    return self;
}

- (void)startScanning {
    NSLog(@"start scanning");
    [self.centralManager scanForPeripheralsWithServices:@[UART_SERVICE_UUID] options:nil];
}

- (void)setBleService:(BTService *)bleService {
    // Using a setter so the service will be properly started and reset
    if (_bleService) {
        [_bleService reset];
        _bleService = nil;
    }
    
    _bleService = bleService;
    if (_bleService) {
        [_bleService startDiscoveringServices];
    }
}

- (void)centralManager:(CBCentralManager *)central didDiscoverPeripheral:(CBPeripheral *)peripheral advertisementData:(NSDictionary *)advertisementData RSSI:(NSNumber *)RSSI {
    // Be sure to retain the peripheral or it will fail during connection.
    
    // Validate peripheral information
    if (!peripheral || !peripheral.name || ([peripheral.name isEqualToString:@""])) {
        return;
    }
    
    // If not already connected to a peripheral, then connect to this one
    if (!self.peripheralBLE || (self.peripheralBLE.state == CBPeripheralStateDisconnected)) {
        // Retain the peripheral before trying to connect
        self.peripheralBLE = peripheral;
        
        // Reset service
        self.bleService = nil;
        
        // Connect to peripheral
        NSLog(@"Connect to my device");
        [self.centralManager connectPeripheral:peripheral options:nil];
    }
}

- (void)centralManager:(CBCentralManager *)central didConnectPeripheral:(CBPeripheral *)peripheral {
    NSLog(@"i did connect");
    if (!peripheral) {
        return;
    }
    
    NSLog(@"Peripheral Connected");
    
    
    
    // Create new service class
    if (peripheral == self.peripheralBLE) {
        self.bleService = [[BTService alloc] initWithPeripheral:peripheral];
    }
    
    // Stop scanning for new devices
    [self.centralManager stopScan];
}

- (void)centralManager:(CBCentralManager *)central didDisconnectPeripheral:(CBPeripheral *)peripheral error:(NSError *)error {
    NSLog(@"disconnecting");
    if (!peripheral) {
        return;
    }
    
    // See if it was our peripheral that disconnected
    if (peripheral == self.peripheralBLE) {
        self.bleService = nil;
        self.peripheralBLE = nil;
    }
    
    // Start scanning for new devices
    [self startScanning];
}

- (void)clearDevices {
    self.bleService = nil;
    self.peripheralBLE = nil;
}

- (void)centralManagerDidUpdateState:(CBCentralManager *)central {
    
    switch (self.centralManager.state) {
        case CBCentralManagerStatePoweredOff:
        {
            [self clearDevices];
            
            break;
        }
            
        case CBCentralManagerStateUnauthorized:
        {
            // Indicate to user that the iOS device does not support BLE.
            break;
        }
            
        case CBCentralManagerStateUnknown:
        {
            // Wait for another event
            break;
        }
            
        case CBCentralManagerStatePoweredOn:
        {
            [self startScanning];
            
            break;
        }
            
        case CBCentralManagerStateResetting:
        {
            [self clearDevices];
            break;
        }
            
        case CBCentralManagerStateUnsupported:
        {
            break;
        }
            
        default:
            break;
    }
    
}

@end


@interface BTService()
@property (strong, nonatomic) CBPeripheral *peripheral;
@property (strong, nonatomic) CBCharacteristic *rxCharacteristic;
@property (strong, nonatomic) CBCharacteristic *txCharacteristic;
@end

@implementation BTService

- (instancetype)initWithPeripheral:(CBPeripheral *)peripheral {
    self = [super init];
    if (self) {
        self.peripheral = peripheral;
        [self.peripheral setDelegate:self];
    }
    return self;
}

- (void)dealloc {
    [self reset];
}

- (void)startDiscoveringServices {
    NSLog(@"Start discovering...");
    
    [self.peripheral discoverServices:@[UART_SERVICE_UUID]];
}

- (void)reset {
    
    if (self.peripheral) {
        self.peripheral = nil;
    }
    
    // Deallocating therefore send notification
    [self sendBTServiceNotificationWithIsBluetoothConnected:NO];
}

- (void)peripheral:(CBPeripheral *)peripheral didDiscoverServices:(NSError *)error {
    NSArray *services = nil;
    NSArray *uuidsForBTService = @[RX_CHARACTERISTIC_UUID, TX_CHARACTERISTIC_UUID];
    
    NSLog(@"discover devices");
    
    if (peripheral != self.peripheral) {
        NSLog(@"Wrong Peripheral.\n");
        return ;
    }
    
    if (error != nil) {
        NSLog(@"Error %@\n", error);
        return ;
    }
    
    services = [peripheral services];
    if (!services || ![services count]) {
        NSLog(@"No Services");
        return ;
    }
    
    for (CBService *service in services) {
        if ([[service UUID] isEqual:UART_SERVICE_UUID]) {
            NSLog(@"found my service (uart)");
            [peripheral discoverCharacteristics:uuidsForBTService forService:service];
            NSLog(@"discovering done (uart)");
        }
    }
}

- (void)peripheral:(CBPeripheral *)peripheral didDiscoverCharacteristicsForService:(CBService *)service error:(NSError *)error {
    NSArray     *characteristics    = [service characteristics];
    NSLog(@"did discover characterstics");
    
    if (peripheral != self.peripheral) {
        NSLog(@"Wrong Peripheral.\n");
        return ;
    }
    
    if (error != nil) {
        NSLog(@"Error %@\n", error);
        return ;
    }
    
    for (CBCharacteristic *characteristic in characteristics) {
        NSLog(@"chk charac");
        if ([[characteristic UUID] isEqual:RX_CHARACTERISTIC_UUID]) {
            NSLog(@"Rx characteristic found");
            self.rxCharacteristic = characteristic;
            [self.peripheral setNotifyValue:TRUE forCharacteristic:characteristic];
            // Send notification that Bluetooth is connected and all required characteristics are discovered
            [self sendBTServiceNotificationWithIsBluetoothConnected:YES];
        }
        if ([[characteristic UUID] isEqual:TX_CHARACTERISTIC_UUID]) {
            NSLog(@"Tx characteristic found");
            self.txCharacteristic = characteristic;
        }
    }
    
    if (self.rxCharacteristic != nil && self.txCharacteristic != nil) {
        NSLog(@"found both rx and tx");
    }
}



- (void)peripheral:(CBPeripheral *)peripheral didUpdateNotificationStateForCharacteristic:(CBCharacteristic *)characteristic error:(NSError *)error
{
    if (error) {
        NSLog(@"Error changing notification state: %@", error.localizedDescription);
        return;
    }
    
    // Notification has started
    if (characteristic.isNotifying) {
        NSLog(@"Notification began on %@", characteristic);
    }
    
    NSLog(@"recv: event");
    if (characteristic == self.rxCharacteristic) {
        NSLog(@"input");
    }
}

- (void)peripheral:(CBPeripheral *)peripheral didUpdateValueForCharacteristic:(CBCharacteristic *)characteristic error:(NSError *)error {
    if (error) {
        NSLog(@"Error reading characteristics: %@", [error localizedDescription]);
        return;
    }
    
    if (characteristic.value != nil) {
        NSData *data = characteristic.value;
        NSString* ss = [NSString stringWithUTF8String:[data bytes]];

        //value here.
#ifdef DEBUG_BT
        //NSLog(@"there is data");
        NSLog(ss);
#endif
        NSDictionary *stuff = @{@"data": ss};
        [[NSNotificationCenter defaultCenter] postNotificationName:THERE_IS_DATA object:self userInfo:stuff];
    }
}


- (void)sendBTServiceNotificationWithIsBluetoothConnected:(BOOL)isBluetoothConnected {
    NSLog(@"connected...");
    NSDictionary *connectionDetails = @{@"isConnected": @(isBluetoothConnected)};
    [[NSNotificationCenter defaultCenter] postNotificationName:RWT_BLE_SERVICE_CHANGED_STATUS_NOTIFICATION object:self userInfo:connectionDetails];
}

@end





