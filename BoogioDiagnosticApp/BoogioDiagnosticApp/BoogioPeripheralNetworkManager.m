//         [manager connectPeripheral:peripheral options:[NSDictionary dictionaryWithObject:[NSNumber numberWithBool:YES] forKey:CBConnectPeripheralOptionNotifyOnDisconnectionKey]];
//  BoogioPeripheralNetworkManager.m
//  BoogioPeripheralNetworkManager
//
//  Created by Nate Shortsleeve on 9/19/14.
//  Copyright (c) 2014 Reflx Labs. All rights reserved.
//

#import "BoogioPeripheralNetworkManager.h"


//-----------------------------------------------------------------------------------
//Members
//-----------------------------------------------------------------------------------
//-----------------------------------------------------------------------------------
@implementation BoogioPeripheralNetworkManager {
    CBCentralManager *manager;
    
    //This is a list of peripherals which advertise inconsistently. Multiple scanning
    //passes must be done in order to assemble this authoritative list of devices.
    
    BOOL centralManagerIsScanning;
    BOOL centralManagerShouldScan;



    NSMutableArray *discoveredLeftShoeBoogioPeripherals;
    NSMutableArray *discoveredRightShoeBoogioPeripherals;

    BOOL peripheralsShouldBeConnected;
    
    NSTimer *stateTimer;
}

//-----------------------------------------------------------------------------------
//Constants
//-----------------------------------------------------------------------------------
//-----------------------------------------------------------------------------------




const float STATE_UPDATE_INTERVAL = 2.0f;




//-----------------------------------------------------------------------------------
//Properties
//-----------------------------------------------------------------------------------
//-----------------------------------------------------------------------------------
@synthesize delegate;

//-----------------------------------------------------------------------------------
//Constructor
//-----------------------------------------------------------------------------------
//-----------------------------------------------------------------------------------
- (id)init {
    self = [super init];
    if (self) {
        if(manager == nil) {
            manager = [[CBCentralManager alloc] initWithDelegate:self queue:nil];
            NSLog(@"Initialized CoreBluetooth Manager");
            
            discoveredLeftShoeBoogioPeripherals = [[NSMutableArray alloc] init];
            discoveredRightShoeBoogioPeripherals = [[NSMutableArray alloc] init];

           stateTimer = [NSTimer scheduledTimerWithTimeInterval: STATE_UPDATE_INTERVAL target:self selector:@selector(updateState) userInfo:nil repeats: YES];

        }
    }
    return self;
}


//-----------------------------------------------------------------------------------
//External Interface
//-----------------------------------------------------------------------------------
//-----------------------------------------------------------------------------------

- (void) startScan {
    
    //prevent repeated invocations from interferring with scan.
    centralManagerShouldScan = TRUE;
    
    if(centralManagerIsScanning == TRUE || [manager state] != CBManagerStatePoweredOn) {
        return;
    }

    
    
    [self clearDiscoveredBoogioPeripherals];
    
    
    
    
    NSLog(@"Starting Scan for Boogio peripherals...");
    
    // Initialize a private variable with the heart rate service UUID
    CBUUID *sensorServiceUUID = [CBUUID UUIDWithString:SENSOR_SERVICE_UUID];
    
    // Create a dictionary for passing down to the scan with service method
    NSDictionary *scanOptions = [NSDictionary dictionaryWithObject:[NSNumber numberWithBool:YES] forKey:CBCentralManagerScanOptionAllowDuplicatesKey];
    
    // Tell the central manager (cm) to scan for the heart rate service
    [manager scanForPeripheralsWithServices:[NSArray arrayWithObjects:sensorServiceUUID,nil] options:scanOptions];

    centralManagerIsScanning = TRUE;

}
- (void) updateState {
    
    BoogioPeripheral *leftShoe  = [self getPairedPeripheralAtLocation:LEFT_SHOE];
    BoogioPeripheral *rightShoe = [self getPairedPeripheralAtLocation:RIGHT_SHOE];
    
    if(   leftShoe != nil
       && rightShoe != nil
       && [self isBoogioPeripheralConnectedAtLocation:LEFT_SHOE]
       && [self isBoogioPeripheralConnectedAtLocation:RIGHT_SHOE]) {
        [self stopScan];
    }
    else {
        [self startScan];
    }
    
}
- (void) stopScan {
    centralManagerShouldScan = FALSE;
    if(!centralManagerIsScanning) {
        return;
    }
    centralManagerIsScanning = FALSE;
    [manager stopScan];
    printf("Stopped scanning.\n");
}
- (void)clearDiscoveredBoogioPeripherals {
    for(BoogioPeripheral *boogioPeripheral in discoveredLeftShoeBoogioPeripherals) {
        [boogioPeripheral disconnect];
        boogioPeripheral.cbPeripheralReference = nil;
    }
    
    for(BoogioPeripheral *boogioPeripheral in discoveredRightShoeBoogioPeripherals) {
        [boogioPeripheral disconnect];
        boogioPeripheral.cbPeripheralReference = nil;
    }

    
    //clear the discovered list of periphearls.
    [discoveredLeftShoeBoogioPeripherals removeAllObjects];
    [discoveredRightShoeBoogioPeripherals removeAllObjects];

}

//Manually disconnect from all peripherals.
- (void)disconnectFromAllPeripherals {
    peripheralsShouldBeConnected = FALSE;
    [self clearDiscoveredBoogioPeripherals];
    [self stopScan];
}
- (void) connectToPairedPeripherals {
    peripheralsShouldBeConnected = TRUE;
    [self startScan];
}

- (void)subscribeToBoogioPeripheralAt:(BOOGIO_PERIPHERAL_LOCATION)location
                forNotificationsAbout:(BOOGIO_DATA_TYPE)dataType {
    
    BoogioPeripheral *boogioPeripheral = [self getPairedPeripheralAtLocation:location];
    if(boogioPeripheral == nil) {
        return;
    }
    [boogioPeripheral subscribeForNotificationsAbout:dataType];

}
- (void)unsubscribeFromBoogioPeripheralAt:(BOOGIO_PERIPHERAL_LOCATION)location
                forNotificationsAbout:(BOOGIO_DATA_TYPE)dataType {
    BoogioPeripheral *boogioPeripheral = [self getPairedPeripheralAtLocation:location];
    if(boogioPeripheral == nil) {
        return;
    }
    [boogioPeripheral unsubscribeFromNotificationsAbout:dataType];

}

//To avoid mistakes, the discovered peripheral collection should remain authoritative within the
//BoogioPeripheralNetwork object.
- (NSUInteger)getLeftShoeBoogioPeripheralsCount {
    return [discoveredLeftShoeBoogioPeripherals count];
}
- (NSUInteger)getRightShoeBoogioPeripheralsCount {
    return [discoveredRightShoeBoogioPeripherals count];
}

- (BoogioPeripheral*)getLeftShoeBoogioPeripheralAtIndex:(NSUInteger)index {
    if(index >= [discoveredLeftShoeBoogioPeripherals count]){
        return nil;
    }
    return [discoveredLeftShoeBoogioPeripherals objectAtIndex:index];
}
- (BoogioPeripheral*)getRightShoeBoogioPeripheralAtIndex:(NSUInteger)index {
    if(index >= [discoveredRightShoeBoogioPeripherals count]){
        return nil;
    }
    return [discoveredRightShoeBoogioPeripherals objectAtIndex:index];
}

- (void)readDataFromBoogioPeripheralAt:(BOOGIO_PERIPHERAL_LOCATION)location
                            ofDataType:(BOOGIO_DATA_TYPE)dataType {
    
    BoogioPeripheral *boogioPeripheral = [self getPairedPeripheralAtLocation:location];
    if(boogioPeripheral == nil) {
        return;
    }
    [boogioPeripheral readDataFromBoogioPeripheral:dataType];
}

//-----------------------------------------------------------------------------------
//BoogioPeripheral Delegate Callbacks
//-----------------------------------------------------------------------------------
//-----------------------------------------------------------------------------------
- (void)boogioPeripheral:(BoogioPeripheral*)peripheral
             DidSendData:(NSArray*)data
                  ofType:(BOOGIO_DATA_TYPE)sensorDataType{
    if (delegate != nil && [(NSObject*)self.delegate respondsToSelector:@selector(boogioPeripheral:DidSendData:ofType:)]) {
        [delegate boogioPeripheral:peripheral DidSendData:data ofType:sensorDataType];
    }
}
- (void)boogioPeripheralDidConnect:(BoogioPeripheral*)peripheral {
    
    
    NSLog(@"Peripheral %@ did connect", peripheral.cbPeripheralReference.name);
    [delegate boogioPeripheralDidConnect:peripheral];
    
}
- (void)boogioPeripheralDidDisconnect:(BoogioPeripheral*)peripheral {
    [delegate boogioPeripheralDidDisconnect:peripheral];
}


//-----------------------------------------------------------------------------------
//CoreBluetooth Framework CBCentralManager Callbacks
//-----------------------------------------------------------------------------------
//-----------------------------------------------------------------------------------
- (void)centralManagerDidUpdateState:(CBCentralManager *)central {
    
    NSString * state = nil;
    switch ([manager state]) {
        case CBManagerStateUnsupported:
            state = @"The platform/hardware doesn't support Bluetooth Low Energy.";
            break;
        case CBManagerStateUnauthorized:
            state = @"The app is not authorized to use Bluetooth Low Energy.";
            break;
        case CBManagerStatePoweredOff:
            state = @"Bluetooth is currently powered off.";
            break;
        case CBManagerStatePoweredOn:
            state = @"Bluetooth is currently powered on.";
            if(centralManagerShouldScan) {
                [self startScan];
            }
            break;
        case CBManagerStateUnknown:
            state = @"Bluetooth state is unknown.";
            break;
        default:
            state = @"Bluetooth state is unknown.";
            break;
            
    }
    NSLog(@"Central manager state: %@", state);

}


- (void)centralManager:(CBCentralManager *)central
 didDiscoverPeripheral:(CBPeripheral *)peripheral
     advertisementData:(NSDictionary *)advertisementData
                  RSSI:(NSNumber *)RSSI{

    //Sometimes the advertisement data does not come through
    //Drop the event if this occurs.
    NSData *manufacturerData = [advertisementData objectForKey:CBAdvertisementDataManufacturerDataKey];
    NSData *leftShoeManufacturerData = [NSData dataWithBytes:(unsigned char[]){0xff, 0xff, 0x06} length:3];
    NSData *rightShoeManufacturerData = [NSData dataWithBytes:(unsigned char[]){0xff, 0xff, 0x07} length:3];
//    NSLog(@"Manufacturer Data: %@", [manufacturerData description]);

    BOOGIO_PERIPHERAL_LOCATION location;
    
    if([manufacturerData isEqualToData:leftShoeManufacturerData]) {
        location = LEFT_SHOE;
    }
    else if([manufacturerData isEqualToData:rightShoeManufacturerData]) {
        location = RIGHT_SHOE;
    }
    else {
        return;
    }
    
    //Factory a boogio peripheral
    BoogioPeripheral *boogioPeripheral = [self factoryBoogioPeripheralFrom:peripheral forLocation:location];

    if([self getBoogioPeripheralWithUUID:peripheral.identifier.UUIDString] != nil) {
        //already discovered and stored
        return;
    }
    
    switch (location) {
        case LEFT_SHOE:
            [discoveredLeftShoeBoogioPeripherals addObject:boogioPeripheral];
            break;
        case RIGHT_SHOE:
            [discoveredRightShoeBoogioPeripherals addObject:boogioPeripheral];
            break;
            
        default:
            break;
    }
    

    
    NSLog(@"Paired Left Shoe  = %@", [self getPairedPeripheralUUID:LEFT_SHOE]);
    NSLog(@"Paired Right Shoe = %@", [self getPairedPeripheralUUID:RIGHT_SHOE]);
    NSLog(@"Discovered          %@", [boogioPeripheral getUUIDString]);
    
    if(peripheralsShouldBeConnected) {
        
        for(BoogioPeripheral *boogioPeripheral in discoveredLeftShoeBoogioPeripherals) {
            if([[boogioPeripheral getUUIDString]isEqualToString:[self getPairedPeripheralUUID:LEFT_SHOE]]) {
                [boogioPeripheral connect];
            }

        }
        for(BoogioPeripheral *boogioPeripheral in discoveredRightShoeBoogioPeripherals) {
            if([[boogioPeripheral getUUIDString]isEqualToString:[self getPairedPeripheralUUID:RIGHT_SHOE]]) {
                [boogioPeripheral connect];
            }
            
        }

    }

    //Send Delegates Messages
    if(delegate == nil) {
        NSLog(@"Error: PeripheralNetworkManager delegate is nil.");
        return;
    }
    
    if ([(NSObject*)self.delegate respondsToSelector:@selector(boogioPeripheralWasDiscovered:)]) {
        if(location == LEFT_SHOE) {
            [self.delegate boogioPeripheralWasDiscovered:boogioPeripheral];
        }
        else if(location == RIGHT_SHOE) {
            [self.delegate boogioPeripheralWasDiscovered:boogioPeripheral];
        }
    }
    else {
//        NSLog(@"Error: PeripheralNetworkManager delegate does not respond to selector boogioPeripheralWasDiscovered:");
        return;
    }
}

- (void)centralManager:(CBCentralManager *)central
didDisconnectPeripheral:(CBPeripheral *)peripheral
                 error:(NSError *)error {
    
    NSLog(@"<<%@>> %@ has disconnected", peripheral.identifier.UUIDString, peripheral.name);
    
    BoogioPeripheral *boogioPeripheral = [self getBoogioPeripheralWithUUID:peripheral.identifier.UUIDString];

    if (boogioPeripheral != nil && delegate != nil && [(NSObject*)self.delegate respondsToSelector:@selector(boogioPeripheralDidDisconnect:)]) {
        [delegate boogioPeripheralDidDisconnect:boogioPeripheral];
    }
    
}

- (void)centralManager:(CBCentralManager *)central
  didConnectPeripheral:(CBPeripheral *)peripheral {
    
    NSLog(@"Connected to peripheral <<%@>> %@", peripheral.identifier.UUIDString, peripheral.name);
    
    BoogioPeripheral *boogioPeripheral = [self getBoogioPeripheralWithUUID:peripheral.identifier.UUIDString];

    [boogioPeripheral centralManager:central didConnectPeripheral:peripheral];
    if (boogioPeripheral != nil && delegate != nil && [(NSObject*)self.delegate respondsToSelector:@selector(boogioPeripheralDidConnect:)]) {
        [delegate boogioPeripheralDidConnect:boogioPeripheral];
    }

}

- (NSString*) getPairedPeripheralUUID:(BOOGIO_PERIPHERAL_LOCATION)location {
    switch (location) {
        case LEFT_SHOE:
            return [BoogioGlobals getPersistentSettingsValueForKey:LEFT_SHOE_UUID_KEY_STRING];
        case RIGHT_SHOE:
            return [BoogioGlobals getPersistentSettingsValueForKey:RIGHT_SHOE_UUID_KEY_STRING];
        default:
            break;
    }
    return @"";
}
- (BoogioPeripheral*) getPairedPeripheralAtLocation:(BOOGIO_PERIPHERAL_LOCATION)location {
    for(BoogioPeripheral *boogioPeripheral in discoveredLeftShoeBoogioPeripherals) {
        if([[boogioPeripheral getUUIDString] isEqualToString:[BoogioGlobals getPersistentSettingsValueForKey:LEFT_SHOE_UUID_KEY_STRING]] && [boogioPeripheral getLocation] == location)
            return boogioPeripheral;
    }
    for(BoogioPeripheral *boogioPeripheral in discoveredRightShoeBoogioPeripherals) {
        if([[boogioPeripheral getUUIDString] isEqualToString:[BoogioGlobals getPersistentSettingsValueForKey:RIGHT_SHOE_UUID_KEY_STRING]] && [boogioPeripheral getLocation] == location)
            return boogioPeripheral;
    }
    return nil;
}
- (void) pairWithPeripheralWith:(NSString*)uuidString atLocation:(BOOGIO_PERIPHERAL_LOCATION)location {
    switch (location) {
        case LEFT_SHOE:
            [BoogioGlobals setPersistentSettingsValue:uuidString ForKey:LEFT_SHOE_UUID_KEY_STRING];
            NSLog(@"Set left shoe = %@", uuidString);
            break;
        case RIGHT_SHOE:
            [BoogioGlobals setPersistentSettingsValue:uuidString ForKey:RIGHT_SHOE_UUID_KEY_STRING];
            NSLog(@"Set right shoe = %@", uuidString);
            break;
        default:
            break;
    }
    
    
}
- (BOOL) isBoogioPeripheralConnectedAtLocation:(BOOGIO_PERIPHERAL_LOCATION)location {
    for(BoogioPeripheral *boogioPeripheral in discoveredLeftShoeBoogioPeripherals) {
        if([boogioPeripheral getLocation] == location && [boogioPeripheral getConnectionState] == CBPeripheralStateConnected)
            return TRUE;
    }
    for(BoogioPeripheral *boogioPeripheral in discoveredRightShoeBoogioPeripherals) {
        if([boogioPeripheral getLocation] == location && [boogioPeripheral getConnectionState] == CBPeripheralStateConnected)
            return TRUE;
    }
    return FALSE;
}
- (BoogioPeripheral*)factoryBoogioPeripheralFrom:(CBPeripheral*)peripheral forLocation:(BOOGIO_PERIPHERAL_LOCATION)location{
    
    //Return BoogioPeripheral object if it already exists
    for(BoogioPeripheral * boogioPeripheral in discoveredLeftShoeBoogioPeripherals) {
        if([[boogioPeripheral getUUIDString]isEqualToString:peripheral.identifier.UUIDString]) {
            return boogioPeripheral;
        }
    }
    //Return BoogioPeripheral object if it already exists
    for(BoogioPeripheral * boogioPeripheral in discoveredRightShoeBoogioPeripherals) {
        if([[boogioPeripheral getUUIDString]isEqualToString:peripheral.identifier.UUIDString]) {
            return boogioPeripheral;
        }
    }
    
    
    BoogioPeripheral * boogioPeripheral= [[BoogioPeripheral alloc]init];
    [boogioPeripheral setLocation:location];
    
    boogioPeripheral.cbPeripheralReference = peripheral;
    [peripheral setDelegate:boogioPeripheral];
    boogioPeripheral.delegate = self;
    boogioPeripheral.centralManager = manager;
    

    return boogioPeripheral;

}
- (BoogioPeripheral*)getBoogioPeripheralWithUUID:(NSString*)uuid {
    for(BoogioPeripheral *boogioPeripheral in discoveredLeftShoeBoogioPeripherals) {
        if ([[boogioPeripheral getUUIDString] isEqualToString:uuid]) {
            return boogioPeripheral;
        }
    }
    for(BoogioPeripheral *boogioPeripheral in discoveredRightShoeBoogioPeripherals) {
        if ([[boogioPeripheral getUUIDString] isEqualToString:uuid]) {
            return boogioPeripheral;
        }
    }
    return nil;
}
@end
