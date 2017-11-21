//
//  ViewController.m
//  BleCarControl
//
//  Created by Manuel Schreiner on 13.02.16.
//  Copyright © 2016 io-expert.com. All rights reserved.
//

#import "ViewController.h"
#import <UIKit/UIKit.h>
#import <CoreMotion/CoreMotion.h>
#import <CoreBluetooth/CoreBluetooth.h>

#define TRANSFER_SERVICE_RX_UUID           @"00000010-0000-1000-8000-00805F9B34FB"
#define TRANSFER_SERVICE_TX_UUID           @"00000000-0000-1000-8000-00805F9B34FB"
#define TRANSFER_CHARACTERISTIC_RX_UUID    @"00000011-0000-1000-8000-00805F9B34FB"
#define TRANSFER_CHARACTERISTIC_TX_UUID    @"00000001-0000-1000-8000-00805F9B34FB"

#define STATUS_DISCONNECTED              0
#define STATUS_SCAN_STARTED              1
#define STATUS_CONNECTED                 2
#define STATUS_SERVICEFOUND              4
#define STATUS_CHARACTERISTIC_FOUND      8

double currentMaxAccelX;
double currentMaxAccelY;
double currentMaxAccelZ;
double currentMaxRotX;
double currentMaxRotY;
double currentMaxRotZ;
int drivefb = 0;
int drivelr = 0;
int drivelr_touch = 0;
int olddrivefb = 0;
int olddrivelr = 0;
uint32_t Status;
Boolean DiscoverComplete;
volatile uint32_t connectTimeout;

@interface ViewController () <CBCentralManagerDelegate, CBPeripheralDelegate>

@property (strong, nonatomic) CBCentralManager      *centralManager;
@property (strong, nonatomic) CBPeripheral          *discoveredPeripheral;
@property (strong, nonatomic) NSMutableData         *data;
@property (strong, nonatomic) CBService* TxService;
@property (strong, nonatomic) CBCharacteristic* TxCharacteristics;
@property (strong, nonatomic) CBService* RxService;
@property (strong, nonatomic) CBCharacteristic* RxCharacteristics;
@property (strong, nonatomic) NSTimer* periodicUpdateTimer;

@property (strong, nonatomic) NSTimer* sendingUpdateTimer;
@property (strong, nonatomic) NSTimer* sendingUpdateTimerSlow;

@end

@implementation ViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    // Do any additional setup after loading the view, typically from a nib.
    
    currentMaxAccelX = 0;
    currentMaxAccelY = 0;
    currentMaxAccelZ = 0;
    
    currentMaxRotX = 0;
    currentMaxRotY = 0;
    currentMaxRotZ = 0;
    
    Status = STATUS_DISCONNECTED;
    connectTimeout = 5000;
    
    self.motionManager = [[CMMotionManager alloc] init];
    self.motionManager.accelerometerUpdateInterval = 1.0f/32;
    self.motionManager.gyroUpdateInterval = .2;
    
    [self.motionManager startAccelerometerUpdatesToQueue:[NSOperationQueue currentQueue]
                                             withHandler:^(CMAccelerometerData  *accelerometerData, NSError *error) {
                                                 [self outputAccelertionData:accelerometerData.acceleration];
                                                 if(error){
                                                     
                                                     NSLog(@"%@", error);
                                                 }
                                             }];
    
    [self.motionManager startGyroUpdatesToQueue:[NSOperationQueue currentQueue]
                                    withHandler:^(CMGyroData *gyroData, NSError *error) {
                                        [self outputRotationData:gyroData.rotationRate];
                                    }];
    self.sendingUpdateTimer = [NSTimer scheduledTimerWithTimeInterval:1.0f/16 target:self selector:@selector(updateTimer) userInfo:nil repeats:YES];
    self.sendingUpdateTimerSlow = [NSTimer scheduledTimerWithTimeInterval:1.0f/2 target:self selector:@selector(updateTimerSlow) userInfo:nil repeats:YES];
    
    self.periodicUpdateTimer = [NSTimer scheduledTimerWithTimeInterval:1.0f/1000 target:self selector:@selector(periodUpdate) userInfo:nil repeats:YES];
    
    _discoveredPeripheral = nil;
    _TxService = nil;
    _TxCharacteristics = nil;
    _RxService = nil;
    _RxCharacteristics = nil;

    _centralManager = [[CBCentralManager alloc] initWithDelegate:self queue:nil];
    
    // And somewhere to store the incoming data
    self.data = [[NSMutableData alloc] init];
    

}

-(void) periodUpdate
{
    if (connectTimeout == 0)
    {
        if ((Status & STATUS_SCAN_STARTED) == 0)
        {
            NSLog(@"Restart scanning...");
            
            if (self.discoveredPeripheral != nil)
            {
                [self.centralManager cancelPeripheralConnection:self.discoveredPeripheral];
                self.discoveredPeripheral = nil;
            }
            //[self cleanup];
            connectTimeout = 5000;
            
            // We're disconnected, so start scanning again
            [self scan];
        }
        else
        {
            [self cleanup];
            [self scan];
        }
    } else
    {
        connectTimeout--;
        
    }
}


- (void)viewWillDisappear:(BOOL)animated
{
    // Don't keep it going while we're not showing.
    [self.centralManager stopScan];
    NSLog(@"Scanning stopped");
    
    [super viewWillDisappear:animated];
}


- (void)cleanup
{
    // Don't do anything if we're not connected
    if (!self.discoveredPeripheral.isAccessibilityElement) {
        return;
    }
    Status = 0;
    _TxService = nil;
    _TxCharacteristics = nil;
    _RxService = nil;
    _RxCharacteristics = nil;
    DiscoverComplete = false;
    // See if we are subscribed to a characteristic on the peripheral
    if (self.discoveredPeripheral.services != nil) {
        for (CBService *service in self.discoveredPeripheral.services) {
            if (service.characteristics != nil) {
                for (CBCharacteristic *characteristic in service.characteristics) {
                    if ([characteristic.UUID isEqual:[CBUUID UUIDWithString:TRANSFER_CHARACTERISTIC_RX_UUID]]) {
                        if (characteristic.isNotifying) {
                            // It is notifying, so unsubscribe
                            [self.discoveredPeripheral setNotifyValue:NO forCharacteristic:characteristic];
                            
                            // And we're done.
                            return;
                        }
                    }
                }
            }
        }
    }
    
    // If we've got this far, we're connected, but we're not subscribed, so we just disconnect
    [self.centralManager cancelPeripheralConnection:self.discoveredPeripheral];
}

/** centralManagerDidUpdateState is a required protocol method.
 *  Usually, you'd check for other states to make sure the current device supports LE, is powered on, etc.
 *  In this instance, we're just using it to wait for CBCentralManagerStatePoweredOn, which indicates
 *  the Central is ready to be used.
 */
- (void)centralManagerDidUpdateState:(CBCentralManager *)central
{
    if (central.state != CBCentralManagerStatePoweredOn) {
        // In a real app, you'd deal with all the states correctly
        return;
    }
    // The state must be CBCentralManagerStatePoweredOn...
    connectTimeout = 5000;
    Status = STATUS_SCAN_STARTED | STATUS_CONNECTED;
    // ... so start scanning
    [self scan];
}

/** Scan for peripherals - specifically for our service's 128bit CBUUID
 */
- (void)scan
{
    connectTimeout = 5000;
    DiscoverComplete = false;
    Status = STATUS_SCAN_STARTED;
    [self.centralManager scanForPeripheralsWithServices:@[[CBUUID UUIDWithString:TRANSFER_SERVICE_RX_UUID],[CBUUID UUIDWithString:TRANSFER_SERVICE_TX_UUID]]
                                                options:@{ CBCentralManagerScanOptionAllowDuplicatesKey : @NO }];
    
    NSLog(@"Scanning started");
}

/** This callback comes whenever a peripheral that is advertising the TRANSFER_SERVICE_UUID is discovered.
 *  We check the RSSI, to make sure it's close enough that we're interested in it, and if it is,
 *  we start the connection process
 */
- (void)centralManager:(CBCentralManager *)central didDiscoverPeripheral:(CBPeripheral *)peripheral advertisementData:(NSDictionary *)advertisementData RSSI:(NSNumber *)RSSI
{
    
    
    // Reject any where the value is above reasonable range
    NSLog(@"Discovered %@ at %@", peripheral.name, RSSI);
    
    
    
    connectTimeout = 5000;
    
    NSString* sName = peripheral.name;
    
    // Ok, it's in range - have we already seen it?
    if ((self.discoveredPeripheral != peripheral) && ([sName isEqualToString:@"pattern"] )){
        
        // Save a local copy of the peripheral, so CoreBluetooth doesn't get rid of it
        self.discoveredPeripheral = peripheral;
        
        [self.centralManager cancelPeripheralConnection:peripheral];
        
        // And connect
        NSLog(@"Connecting to peripheral %@", peripheral);
        [self.centralManager connectPeripheral:peripheral options:nil];
    }
}

/** If the connection fails for whatever reason, we need to deal with it.
 */
- (void)centralManager:(CBCentralManager *)central didFailToConnectPeripheral:(CBPeripheral *)peripheral error:(NSError *)error
{
    NSLog(@"Failed to connect to %@. (%@)", peripheral, [error localizedDescription]);
    [self cleanup];
}

/** We've connected to the peripheral, now we need to discover the services and characteristics to find the 'transfer' characteristic.
 */
- (void)centralManager:(CBCentralManager *)central didConnectPeripheral:(CBPeripheral *)peripheral
{
    NSLog(@"Peripheral Connected");
    connectTimeout = 5000;
    Status |= STATUS_CONNECTED;
    // Stop scanning
    [self.centralManager stopScan];
    NSLog(@"Scanning stopped");
    Status &= ~STATUS_SCAN_STARTED;
    // Clear the data that we may already have
    [self.data setLength:0];
    
    // Make sure we get the discovery callbacks
    peripheral.delegate = self;
    
    [self performSelector:@selector(delayedDiscoverServices:) withObject:peripheral afterDelay: 0.5];
    [self performSelector:@selector(delayedDiscoverServices:) withObject:peripheral afterDelay: 1];
    [self performSelector:@selector(delayedDiscoverServices:) withObject:peripheral afterDelay: 2];
    
}

-(void)delayedDiscoverServices:(CBPeripheral *)peripheral
{
    connectTimeout = 5000;
    if (peripheral.services)
    {
        [self peripheral:peripheral didDiscoverServices:nil];
    }
    else
    {
        [peripheral discoverServices:nil];
        
        // Search only for services that match our UUID
        //@[[CBUUID UUIDWithString:TRANSFER_SERVICE_TX_UUID],[CBUUID UUIDWithString:TRANSFER_SERVICE_RX_UUID]]];
        //[peripheral discoverServices] //@[[CBUUID UUIDWithString:TRANSFER_SERVICE_RX_UUID]]];
    }
}

/** The Transfer Service was discovered
 */
- (void)peripheral:(CBPeripheral *)peripheral didDiscoverServices:(NSError *)error
{
    if (error) {
        NSLog(@"Error discovering services: %@", [error localizedDescription]);
        [self cleanup];
        return;
    }
    connectTimeout = 5000;
    // Discover the characteristic we want...
    Status |= STATUS_SERVICEFOUND;
    
    // Loop through the newly filled peripheral.services array, just in case there's more than one.
    for (CBService *service in peripheral.services) {
        if (service.characteristics)
        {
            [self peripheral:peripheral didDiscoverCharacteristicsForService:service error:nil];
        }
        else
        {
            if ([service.UUID isEqual:[CBUUID UUIDWithString:TRANSFER_SERVICE_TX_UUID]]) {
                [peripheral discoverCharacteristics:@[[CBUUID UUIDWithString:TRANSFER_CHARACTERISTIC_TX_UUID]] forService:service];
            }
            
            if ([service.UUID isEqual:[CBUUID UUIDWithString:TRANSFER_SERVICE_RX_UUID]]) {
                [peripheral discoverCharacteristics:@[[CBUUID UUIDWithString:TRANSFER_CHARACTERISTIC_RX_UUID]] forService:service];
            }
        }
    }
}

/** The Transfer characteristic was discovered.
 *  Once this has been found, we want to subscribe to it, which lets the peripheral know we want the data it contains
 */
- (void)peripheral:(CBPeripheral *)peripheral didDiscoverCharacteristicsForService:(CBService *)service error:(NSError *)error
{
    // Deal with errors (if any)
    if (error) {
        NSLog(@"Error discovering characteristics: %@", [error localizedDescription]);
        [self cleanup];
        return;
    }
    Status |= STATUS_CHARACTERISTIC_FOUND;
    _discoveredPeripheral = peripheral;
    connectTimeout = 5000;
    // Again, we loop through the array, just in case.
    NSLog(@"For Service: %@",service );
    for (CBCharacteristic *characteristic in service.characteristics) {
        // And check if it's the right one
        if ([service.UUID isEqual:[CBUUID UUIDWithString:TRANSFER_SERVICE_RX_UUID]])
        {
            if ([characteristic.UUID isEqual:[CBUUID UUIDWithString:TRANSFER_CHARACTERISTIC_RX_UUID]]) {
                _RxService = service;
                _RxCharacteristics = characteristic;
                NSLog(@"Adding RxCharacteristics: %@",_RxCharacteristics);
                // If it is, subscribe to it
                NSLog(@"Starting notification mode...");
                [peripheral setNotifyValue:YES forCharacteristic:characteristic];
                
            }
        }
        if ([service.UUID isEqual:[CBUUID UUIDWithString:TRANSFER_SERVICE_TX_UUID]])
        {
            if ([characteristic.UUID isEqual:[CBUUID UUIDWithString:TRANSFER_CHARACTERISTIC_TX_UUID]]) {
                _TxService = service;
                _TxCharacteristics = characteristic;
                NSLog(@"Adding TxCharacteristics: %@",_TxCharacteristics);
            }
        }
        
    }
    DiscoverComplete = true;
    // Once this is complete, we just need to wait for the data to come in.
}

/** This callback lets us know more data has arrived via notification on the characteristic
 */
- (void)peripheral:(CBPeripheral *)peripheral didUpdateValueForCharacteristic:(CBCharacteristic *)characteristic error:(NSError *)error
{
    static NSString* stringCompleteData = @"";
    if (error) {
        NSLog(@"Error discovering characteristics: %@", [error localizedDescription]);
        return;
    }

}

/** Once the disconnection happens, we need to clean up our local copy of the peripheral
 */
- (void)centralManager:(CBCentralManager *)central didDisconnectPeripheral:(CBPeripheral *)peripheral error:(NSError *)error
{
    NSLog(@"Peripheral Disconnected");
    self.discoveredPeripheral = nil;
    Status = 0;
    // We're disconnected, so start scanning again
    [self scan];
}

-(void)sendString:(NSString*)strdata {
    NSData* data = [strdata dataUsingEncoding:NSUTF8StringEncoding];
    [self sendData:data];
}

-(void)sendData:(NSData*)data {
    NSString* logStr = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
    NSLog(@"\r\nSending: \"%@\"\r\n\r\n",logStr );
    if (_discoveredPeripheral == NULL) return;
    if (_TxCharacteristics == NULL) return;
    connectTimeout = 1000;
    if ((_TxCharacteristics.properties & CBCharacteristicPropertyWriteWithoutResponse) != 0)
    {
        [_discoveredPeripheral writeValue:data forCharacteristic:_TxCharacteristics type:CBCharacteristicWriteWithoutResponse];
        
    }
    else
    {
        [_discoveredPeripheral writeValue:data forCharacteristic:_TxCharacteristics type:CBCharacteristicWriteWithResponse];
    }
}

-(void)outputAccelertionData:(CMAcceleration)acceleration
{
    if ((acceleration.z < 0.6) && (acceleration.z > -0.6))
    {
        self.flBtn.hidden = true;
        self.frBtn.hidden = true;
        self.blBtn.hidden = true;
        self.brBtn.hidden = true;
        if (acceleration.y > 0.2)
        {
            drivelr = -1;
        } else if (acceleration.y < -0.2)
        {
            drivelr = 1;
        }
        else
        {
            drivelr = 0;
        }
        if (acceleration.x > 0)
        {
            drivelr = -drivelr;
        }
        if (drivelr > 0)
        {
            if (drivefb == 1)
            {
                self.frBtn.hidden = false;
            } else if (drivefb == -1)
            {
                self.brBtn.hidden = false;
            }
        } else if (drivelr < 0)
        {
            if (drivefb == 1)
            {
                self.flBtn.hidden = false;
            } else if (drivefb == -1)
            {
                self.blBtn.hidden = false
                ;
            }
        }

    }
    else{
        drivelr = 0;
        self.flBtn.hidden = false;
        self.frBtn.hidden = false;
        self.blBtn.hidden = false;
        self.brBtn.hidden = false;
    }
}
-(void)outputRotationData:(CMRotationRate)rotation
{
    
}


- (void)didReceiveMemoryWarning {
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}

-(void)updateTimer
{
    NSString* strData = @"";
    if (drivelr_touch != 0)
    {
        drivelr = drivelr_touch;
    }
    if ((drivefb == olddrivefb) && (drivelr == olddrivelr))
    {
        return;
    }
    olddrivefb = drivefb;
    olddrivelr = drivelr;
    if (drivefb == 1)
    {
        strData = [strData stringByAppendingString:@"f"];
    } else if (drivefb == -1)
    {
        strData = [strData stringByAppendingString:@"b"];
    } else
    {
        strData = [strData stringByAppendingString:@" "];
    }
    
    if (drivelr == 1)
    {
        strData = [strData stringByAppendingString:@"l"];
    } else if (drivelr == -1)
    {
        strData = [strData stringByAppendingString:@"r"];
    } else
    {
        strData = [strData stringByAppendingString:@" "];
    }
    
    
    //NSLog(strData);
    [self sendString:strData];
    [self sendString:strData];
    [self sendString:strData];
}

-(void)updateTimerSlow
{
    NSString* strData = @"";
    
    if (drivefb == 1)
    {
        strData = [strData stringByAppendingString:@"f"];
    } else if (drivefb == -1)
    {
        strData = [strData stringByAppendingString:@"b"];
    } else
    {
        strData = [strData stringByAppendingString:@" "];
    }
    
    if (drivelr == 1)
    {
        strData = [strData stringByAppendingString:@"l"];
    } else if (drivelr == -1)
    {
        strData = [strData stringByAppendingString:@"r"];
    } else
    {
        strData = [strData stringByAppendingString:@" "];
    }
    
    
    //NSLog(strData);
    [self sendString:strData];
}

- (IBAction)forwardStart:(id)sender {
    drivefb = 1;
}

- (IBAction)backwardStart:(id)sender {
    drivefb = -1;
}

- (IBAction)moveStop:(id)sender {
    drivefb = 0;
    drivelr_touch = 0;
}

- (IBAction)forwardLeftStart:(id)sender {
    drivefb = 1;
    drivelr_touch = -1;
}

- (IBAction)forwardRightStart:(id)sender {
    drivefb = 1;
    drivelr_touch = 1;
}

- (IBAction)backwardLeftStart:(id)sender {
    drivefb = -1;
    drivelr_touch = -1;
}

- (IBAction)backwardRightStart:(id)sender {
    drivefb = -1;
    drivelr_touch = 1;
}
@end
