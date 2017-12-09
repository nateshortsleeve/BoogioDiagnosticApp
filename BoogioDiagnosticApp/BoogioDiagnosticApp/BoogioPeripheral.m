//
//  BoogioPeripheral.m
//  ConfigurationTool
//
//  Created by Nate on 12/15/14.
//  Copyright (c) 2014 Reflx Labs. All rights reserved.
//

#import "BoogioPeripheral.h"
#import "BoogioPeripheralNetworkManager.h"



typedef enum CHARACTERISTIC_SUBSCRIPTION_STATE : NSUInteger {
    UNDISCOVERED = 0,
    UNSUBSCRIBED,
    WOULD_LIKE_TO_SUBSCRIBE,
    SUBSCRIBED,
    WOULD_LIKE_TO_UNSUBSCRIBE,
    
} CHARACTERISTIC_SUBSCRIPTION_STATE;

// Inverse square root.
static inline float invSqrt(float x)
{
    float xhalf = 0.5f * x;
    int i = *(int*)&x;              // get bits for floating value
    i = 0x5f375a86 - (i >> 1);      // gives initial guess y0
    x = *(float*)&i;                // convert bits back to float
    x = x * (1.5f - xhalf * x * x); // Newton step, repeating increases accuracy
    return x;
}



@implementation BoogioPeripheral {
    //Characteristics must be discovered and stored before they can be subscribed to
    NSMutableDictionary *characteristicMap;
    
    ///<,value> == <NSString *uuid, NSAarray *descriptors>
    NSMutableDictionary *descriptors;
    
    NSTimer *synchronizeValuesTimer;
    NSDate* intendedOriginTime;
    
    
    BOOGIO_PERIPHERAL_LOCATION lastKnownLocation;
    NSUInteger batteryLevel;
    
    //Read States
    BOOL waitingToReceiveBodySensorLocationValue;
    BOOL waitingToReceiveBatteryLevelValue;
    BOOL waitingToReceiveSynchronizationValue;
    BOOL waitingToSynchronizePeripheralTime;
    
    BOOL sentSynchronizationRequestEarly;
    
    //Synchronization States
    BOOL waitingToReceiveToeAndBallSynchronizationPacket;
    BOOL waitingToReceiveArchAndHeelSynchronizationPacket;
    BOOL waitingToReceiveAccelerationSynchronizationPacket;
    BOOL waitingToReceiveRotationSynchronizationPacket;
    BOOL waitingToReceiveDirectionSynchronizationPacket;
    
    //TODO: Make these Queues of data and keep them aligned using the above bool states
    NSArray *toeAndBallSynchronizationPacket;
    NSArray *archAndHeelSynchronizationPacket;
    NSArray *accelerationSynchronizationPacket;
    NSArray *rotationSynchronizationPacket;
    NSArray *directionSynchronizationPacket;
    
    
    
    //Notify States
    BOOL intendedForceCharacteristicSubscriptionState;
    BOOL intendedAccelerationCharacteristicSubscriptionState;
    BOOL intendedRotationCharacteristicSubscriptionState;
    BOOL intendedOrientationCharacteristicSubscriptionState;
    BOOL intendedSynchronizationCharacteristicSubscriptionState;
    
    BOOL lastKnownForceCharacteristicSubscriptionState;
    BOOL lastKnownAccelerationCharacteristicSubscriptionState;
    BOOL lastKnownRotationCharacteristicSubscriptionState;
    BOOL lastKnownOrientationCharacteristicSubscriptionState;
    BOOL lastKnownSynchronizationCharacteristicSubscriptionState;
    
    NSUInteger writeRequestsSent;
    NSUInteger writeRequestsConfirmed;
    
    NSNumber *rssi;
    
    float signedAccelerationXValue;
    float signedAccelerationYValue;
    float signedAccelerationZValue;
    float signedRotationXValue;
    float signedRotationYValue;
    float signedRotationZValue;
    float signedOrientationXValue;
    float signedOrientationYValue;
    float signedOrientationZValue;
    
    
    // These quantities are used for logging
    int currentYear;
    int currentMonth;
    int currentDay;
    int currentHour;
    int currentMinute;
    int currentSecond;
    int currentMillisecond;
    int currentToe;
    int currentBall;
    int currentArch;
    int currentHeel;
    int currentAccelerationX;
    int currentAccelerationY;
    int currentAccelerationZ;
    int currentRotationX;
    int currentRotationY;
    int currentRotationZ;
    int currentDirectionX;
    int currentDirectionY;
    int currentDirectionZ;
    

    // Sample frequency.
    float _sampleFrequencyHz;
    
    // Beta.
    float _beta;
    
    float ahrsSensitivity;

}

@synthesize delegate;


const float NOTIFICATION_REQUEST_TIMEOUT_INTERVAL = 6.0f;

#ifdef TARGET_OS_MAC
    const float PERIPHERAL_SYNCHRONIZATION_INTERVAL = 3.0f;
#else
    const float PERIPHERAL_SYNCHRONIZATION_INTERVAL = 1.0f;
#endif

const float CONNECTION_REQUEST_TIMEOUT_INTERVAL = 3.0f;



- (id)init {
    self = [super init];
    if (self) {
        characteristicMap = [[NSMutableDictionary alloc] init];
        descriptors = [[NSMutableDictionary alloc]init];
        
        
        synchronizeValuesTimer = [NSTimer scheduledTimerWithTimeInterval: PERIPHERAL_SYNCHRONIZATION_INTERVAL target:self selector:@selector(synchronizePeripheral) userInfo:nil repeats: YES];
        
        _intendedConnectionState = CBPeripheralStateDisconnected;
        
        ahrsSensitivity = 1.0f;

    }
    return self;
}
- (void)setAHRSSensitivity:(float)sensitivity {
    ahrsSensitivity = sensitivity;
}
- (void)connect {
    _intendedConnectionState = CBPeripheralStateConnected;
}
- (void)connectToPeripheral:(CBPeripheral*)peripheral {
    [_centralManager cancelPeripheralConnection:peripheral];
    [_centralManager connectPeripheral:_cbPeripheralReference options:[NSDictionary dictionaryWithObject:[NSNumber numberWithBool:YES] forKey:CBConnectPeripheralOptionNotifyOnDisconnectionKey]];
}

- (void)disconnect {
    [self unsubscribeFromNotificationsAbout:SYNCHRONIZATION_TYPE];
    [_centralManager cancelPeripheralConnection:_cbPeripheralReference];
    _intendedConnectionState = CBPeripheralStateDisconnected;
    [self.delegate boogioPeripheralDidDisconnect:self];
}

- (void)synchronizePeripheral {
    
    //TODO unified collection of BoogioPeripherals which can be iterated upon without respect to left or right
    [_cbPeripheralReference setDelegate:self];

    

    
    switch (_cbPeripheralReference.state) {
        case CBPeripheralStateDisconnected:
            //Connect
            if(_intendedConnectionState != CBPeripheralStateDisconnected) {
                [self connectToPeripheral:_cbPeripheralReference];
            }
            break;
        case CBPeripheralStateConnecting:
            //Count the seconds the connection is taking and restart the process if it takes too long
            if( ++_secondsSpentWaitingForConnection > CONNECTION_REQUEST_TIMEOUT_INTERVAL) {
                _secondsSpentWaitingForConnection = 0;
                NSLog(@"Connection attempt timed out. Resending connection request to %@", _cbPeripheralReference.name);
                [self disconnect];
                [self connect];
            }
            break;
        case CBPeripheralStateConnected:
            //synchronize data
            //            [self synchronizePeripheralClone:_currentLeftShoePeripheralState];
            
            if(_intendedConnectionState == CBPeripheralStateDisconnected) {
                [self disconnect];
            }
            break;
        default:
            break;
    }
    
    
    
    //resend subscription/unsubscription requests
    if(intendedForceCharacteristicSubscriptionState) {
        [self subscribeForNotificationsAbout:FORCE_TYPE];
    }
    else {
        [self unsubscribeFromNotificationsAbout:FORCE_TYPE];
    }
    
    if(intendedAccelerationCharacteristicSubscriptionState) {
        [self subscribeForNotificationsAbout:ACCELERATION_TYPE];
    }
    else {
        [self unsubscribeFromNotificationsAbout:ACCELERATION_TYPE];
    }
    
    if(intendedRotationCharacteristicSubscriptionState) {
        [self subscribeForNotificationsAbout:ROTATION_TYPE];
    }
    else {
        [self unsubscribeFromNotificationsAbout:ROTATION_TYPE];
    }
    
    if(intendedOrientationCharacteristicSubscriptionState) {
        [self subscribeForNotificationsAbout:DIRECTION_TYPE];
    }
    else {
        [self unsubscribeFromNotificationsAbout:DIRECTION_TYPE];
    }
    
    if(intendedSynchronizationCharacteristicSubscriptionState) {
        [self subscribeForNotificationsAbout:SYNCHRONIZATION_TYPE];
    }
    else {
        [self unsubscribeFromNotificationsAbout:SYNCHRONIZATION_TYPE];
    }

    
    
    //if peripheral ignores too many write requests, disconnect and reconnect
    if(writeRequestsSent > 20 && writeRequestsSent > 4 * writeRequestsConfirmed) {
        writeRequestsConfirmed = writeRequestsSent = 0;
        NSLog(@"Peripheral %@ has confirmed only %lu write requests out of %lu.", _cbPeripheralReference.name, (unsigned long)writeRequestsConfirmed, (unsigned long)writeRequestsSent);
        NSLog(@"Peripheral %@ has been deemed unresponsive.", _cbPeripheralReference.name);
//        [_centralManager cancelPeripheralConnection:_cbPeripheralReference];
    }
    
    //resend send read requests
//    if(waitingToReceiveBodySensorLocationValue) {
//        [self readCharacteristic:[self getCharacteristic:BODY_SENSOR_LOCATION]];
//    }
    //resend send read requests
    if(waitingToReceiveBatteryLevelValue) {
        [self readCharacteristic:[self getCharacteristic:BATTERY_LEVEL_TYPE]];
    }
    
    if(waitingToSynchronizePeripheralTime) {
        [self synchronizePeripheralTime];
    }
    else if (intendedSynchronizationCharacteristicSubscriptionState == TRUE){
        [self synchronizationTimeout];
    }
    
    
}
- (void)synchronizationTimeout {
    

    CBCharacteristic *syncCharacteristic = [self getCharacteristic:SYNCHRONIZATION_TYPE];
    
    if(syncCharacteristic == nil)
    {
        return;
    }
    
    //This BOOL is a temporary flag allowing the timed method invocation to be ignored after having invoked this method manually.
    //It is helpful in saving time so that as soon as the last packet arrives, a pop request can written immediately.
    if(sentSynchronizationRequestEarly) {
        sentSynchronizationRequestEarly = FALSE;
        return;
    }
    
    
    
    const UInt8  syncCommand = 2;
    
    if(intendedSynchronizationCharacteristicSubscriptionState && lastKnownSynchronizationCharacteristicSubscriptionState) {
        
        
        if (   waitingToReceiveToeAndBallSynchronizationPacket
            || waitingToReceiveArchAndHeelSynchronizationPacket
            || waitingToReceiveAccelerationSynchronizationPacket
            || waitingToReceiveRotationSynchronizationPacket
            || waitingToReceiveDirectionSynchronizationPacket) {

            NSLog(@"SYNC TIMEOUT. Requesting same 5 packets...");
            
            unsigned char bytes[] = {syncCommand, 0};
            NSData *payload = [NSData dataWithBytes:bytes length:sizeof(UInt8)*2];
            [_cbPeripheralReference writeValue:payload forCharacteristic:syncCharacteristic type:CBCharacteristicWriteWithoutResponse];

      
            
        }
        else{
            
//            NSLog(@"SYNC STEP SUCCESS. Requesting new set of 5 packets...");
            
            waitingToReceiveToeAndBallSynchronizationPacket     = TRUE;
            waitingToReceiveArchAndHeelSynchronizationPacket    = TRUE;
            waitingToReceiveAccelerationSynchronizationPacket   = TRUE;
            waitingToReceiveRotationSynchronizationPacket       = TRUE;
            waitingToReceiveDirectionSynchronizationPacket      = TRUE;
            

            unsigned char bytes[] = {syncCommand, 1};
            NSData *payload = [NSData dataWithBytes:bytes length:sizeof(UInt8)*2];
            [_cbPeripheralReference writeValue:payload forCharacteristic:syncCharacteristic type:CBCharacteristicWriteWithoutResponse];

            
            
            
            
        }
        

    }
    
}
- (double)getCurrentSynchronizationNotificationBatchPercentageCompleted {
    double percentComplete = 0.0f;
    
    const double increment = 20.0f; //100 % / 5 notifications
    
    if(!waitingToReceiveToeAndBallSynchronizationPacket) {
        percentComplete += increment;
    }
    if(!waitingToReceiveArchAndHeelSynchronizationPacket) {
        percentComplete += increment;
    }
    if(!waitingToReceiveAccelerationSynchronizationPacket) {
        percentComplete += increment;
    }
    if(!waitingToReceiveRotationSynchronizationPacket) {
        percentComplete += increment;
    }
    if(!waitingToReceiveDirectionSynchronizationPacket) {
        percentComplete += increment;
    }
    
    return percentComplete;
}
- (double)getApproximateSynchronizationPercentageCompleted {
//    - millisecondsInCurrentPacket = millisecondsFromEpochToCurrentPacket
//    - millisecondsNow = millisecondsFromEpochToNow
//    - deltaMilliseconds = millisecondsNow - millisecondsInCurrentPacket
//    - possibleTotalReadingsRemaining = deltaMilliseconds * readingsPerSecond
//    - percentageComplete = possibleTotalReadingsRemaining / firstValueForPossibleTotalReadingsRemaining * 100
    
    double approximateSynchronizationPercentageCompleted = 0.0f;

    if(lastKnownSynchronizationCharacteristicSubscriptionState == FALSE) {
        return approximateSynchronizationPercentageCompleted;
    }
    
    
    //NSTimeInterval diff = [date2 timeIntervalSinceDate:date1];
    //int timestamp = [[NSDate date] timeIntervalSince1970];
    
    NSDate *latestPacketDate = [NSDate date];
    NSCalendar* packetCalendar = [NSCalendar currentCalendar];
    NSDateComponents* packetComponents = [packetCalendar components:NSCalendarUnitYear|NSCalendarUnitMonth|NSCalendarUnitDay|NSCalendarUnitHour|NSCalendarUnitMinute|NSCalendarUnitMinute|NSCalendarUnitSecond|NSCalendarUnitNanosecond fromDate:latestPacketDate]; // Get necessary date components
    
    
    NSUInteger year = currentYear;
    NSUInteger month = currentMonth;
    NSUInteger day = currentDay;
    NSUInteger hour = currentHour;
    NSUInteger minute = currentMinute;
    NSUInteger second = currentSecond;
    NSUInteger millisecond = currentMillisecond;
    
    
    
    [packetComponents setYear:year];
    [packetComponents setMonth:month];
    [packetComponents setDay:day];
    [packetComponents setHour:hour];
    [packetComponents setMinute:minute];
    [packetComponents setSecond:second];
    [packetComponents setNanosecond:millisecond * 1000000];
    
    latestPacketDate = [[NSCalendar currentCalendar] dateFromComponents:packetComponents];
    

//    NSLog(@"%ld/%ld/%ld %ld:%ld:%ld.%ld", (long)[packetComponents year], (long)[packetComponents month], (long)[packetComponents day], (long)[packetComponents hour], (long)[packetComponents minute], (long)[packetComponents second], (long)[packetComponents nanosecond]/1000000);
    
    
//    NSTimeInterval deltaTime = [now timeIntervalSinceDate:latestPacketDate];
    
   

    //NSTimeInterval diff = [date2 timeIntervalSinceDate:date1];
    NSTimeInterval difference = [[NSDate date] timeIntervalSinceDate:latestPacketDate];
    
    
//    NSLog(@"%f - %f = %f", currentTime, packetTime, difference);
//    NSLog(@"%f / %f", deltaTime, firstDeltaTime);
//    NSLog(@"%f / %f", currentTime, packetTime);
    
    //STORAGE_BLOCK_SIZE * STORAGE_RAM_BLOCKS * STORAGE_BLOCK_NUM_SAMPLES  * SAMPLE_RATE / SAMPLE_SIZE
    //MAX_SAMPLES = (STORAGE_RAM_BLOCKS - 1) * STORAGE_BLOCK_NUM_SAMPLES)// Number of samples in RAM
    //    + ((STORAGE_FLASH_BLOCKS - 1) * STORAGE_BLOCK_NUM_SAMPLES);// Number of samples in Flash
    const double maxCapacity = 4096.0f * 2.0f * 113.0f / (10.0f * 15.0f);


    //NSTimeInterval diff = [date2 timeIntervalSinceDate:date1];
    approximateSynchronizationPercentageCompleted = ABS(100.0f - ((difference * 10.0f ) / maxCapacity));

    
    if(approximateSynchronizationPercentageCompleted > 100.0f) {
        approximateSynchronizationPercentageCompleted = 0.0f;
    }
    
//    NSLog(@"%f %ld/%ld/%ld %ld:%ld:%ld.%ld", approximateSynchronizationPercentageCompleted, (long)[packetComponents year], (long)[packetComponents month], (long)[packetComponents day], (long)[packetComponents hour], (long)[packetComponents minute], (long)[packetComponents second], (long)[packetComponents nanosecond]/1000000);

//    NSLog(@"%f", approximateSynchronizationPercentageCompleted);
    
    return approximateSynchronizationPercentageCompleted;
    
}

- (void)synchronizePeripheralTime {
    
    waitingToSynchronizePeripheralTime = TRUE;
    
    CBCharacteristic *syncCharacteristic = [self getCharacteristic:SYNCHRONIZATION_TYPE];
    
    if(syncCharacteristic == nil)
    {
        return;
    }
    
    NSDate *currentDate = [NSDate date];
    NSCalendar* calendar = [NSCalendar currentCalendar];
    NSDateComponents* components = [calendar components:NSCalendarUnitYear|NSCalendarUnitMonth|NSCalendarUnitDay|NSCalendarUnitHour|NSCalendarUnitMinute|NSCalendarUnitMinute|NSCalendarUnitSecond|NSCalendarUnitNanosecond fromDate:currentDate]; // Get necessary date components
    


    //convert from integer to uint16_t
    UInt8  syncTimeCommand = 0;
    UInt16 year            = [components year];
    UInt8  month           = [components month];
    UInt8  day             = [components day];
    UInt8  hour            = [components hour];
    UInt8  minute          = [components minute];
    UInt8  second          = [components second];
    UInt16 millisecond     = [components nanosecond] / 1000000;

    UInt8  year_low_byte = year & 0xFF;
    UInt8  year_high_byte = year >> 8;
    UInt8  millisecond_low_byte = millisecond & 0xFF;
    UInt8  millisecond_high_byte = millisecond >> 8;

    unsigned char bytes[] = {syncTimeCommand,
                           year_low_byte, year_high_byte,
                           month,
                           day,
                           hour,
                           minute,
                           second,
                           millisecond_low_byte, millisecond_high_byte};
    
    
    NSData *payload = [NSData dataWithBytes:bytes length:10];
    
    
    
    
    
    [_cbPeripheralReference writeValue:payload forCharacteristic:syncCharacteristic type:CBCharacteristicWriteWithResponse];
    
    NSLog(@"Sent time synchronize write.");
    
    waitingToSynchronizePeripheralTime = FALSE;
    
    


}
//-----------------------------------------------------------------------------------
//Characteristic Management
//-----------------------------------------------------------------------------------
//-----------------------------------------------------------------------------------
- (BOOGIO_PERIPHERAL_LOCATION)getLocation {
    return lastKnownLocation;
}
- (void)setLocation:(BOOGIO_PERIPHERAL_LOCATION)location {
    lastKnownLocation = location;
}
- (NSUInteger)getLastKnownBatteryLevel {
    return batteryLevel;
}
- (CBPeripheralState)getConnectionState {
    return _cbPeripheralReference.state;
}
- (NSString*)getUUIDString {
    return _cbPeripheralReference.identifier.UUIDString;
}

- (void)readCharacteristic:(CBCharacteristic*)characteristic {
    
//    NSLog(@"%@", characteristic.UUID.UUIDString);
    if(characteristic == nil) {
        NSLog(@"ERROR: Characteristic is nil. Cannot perform read.");
        
        return;
    }

    if([characteristic.UUID.UUIDString isEqualToString: BODY_SENSOR_LOCATION_CHARACTERISTIC_UUID]) {
        waitingToReceiveBodySensorLocationValue = TRUE;
    }
    else if([characteristic.UUID.UUIDString isEqualToString: BATTERY_LEVEL_CHARACTERISTIC_UUID]) {
        waitingToReceiveBatteryLevelValue = TRUE;
    }
    else if([characteristic.UUID.UUIDString isEqualToString: SYNCHRONIZATION_CHARACTERISTIC_UUID]) {
        waitingToReceiveSynchronizationValue = TRUE;
    }
    
    [_cbPeripheralReference readValueForCharacteristic:characteristic];
}


//-----------------------------------------------------------------------------------
//CoreBluetooth Framework CBPeripheral Callbacks
//-----------------------------------------------------------------------------------
//-----------------------------------------------------------------------------------

- (void)peripheral:(CBPeripheral *)peripheral
didWriteValueForCharacteristic:(CBCharacteristic *)characteristic
             error:(NSError *)error {
    if(error != nil) {
        NSLog(@"Error writing value to characteristic %@", characteristic.UUID.UUIDString);
        NSLog(@"%@", [error userInfo]);
        writeRequestsConfirmed++;
    }
    
    //read the value so that it can be verified in the same method it's already being interpreted: PeripheralDidUpdateValueForCharacteristic callback
    [self readCharacteristic:characteristic];
}
-(void) peripheral:(CBPeripheral *)peripheral
       didReadRSSI:(NSNumber *)RSSI
             error:(NSError *)error {

    NSLog(@"Got RSSI update in didReadRSSI : %4.1f", [RSSI doubleValue]);
    
    if( self.delegate == nil) {
        NSLog(@"But Peripheral Network delegate is not set. Dropping data.");
        return;
    }
    if(error) {
        NSLog(@"error: %@", error.debugDescription);
        return;
    }
    
    
    
    NSArray *arrayOfValues =    [NSArray arrayWithObjects:
                                 [NSNumber numberWithInteger:[RSSI intValue]],
                                 nil];
    [self.delegate boogioPeripheral:self DidSendData:arrayOfValues ofType:RSSI_TYPE];
    [self setRSSI:RSSI];
}

- (void)peripheral:(CBPeripheral *)peripheral
didDiscoverServices:(NSError *)error {
    NSLog(@"----- %@ Services (%lu) -----", peripheral.name, (unsigned long)peripheral.services.count);
    if (!error) {
        for (CBService *service in peripheral.services) {
            [peripheral discoverIncludedServices:nil forService:service];
            if([service isPrimary] ==  TRUE) {
                NSLog(@"  Service (Primary): %@", service.UUID.description);
            }
            else {
                NSLog(@"    Service (Secondary): %@", service.UUID.description);
            }
            [peripheral discoverCharacteristics:nil forService:service];
        }
        
        
    }
    else {
        NSLog(@"Service discovery was unsuccessful!");
        NSLog(@"%@",error.debugDescription);
    }
    
}
- (void)peripheral:(CBPeripheral *)peripheral
didDiscoverCharacteristicsForService:(CBService *)service
             error:(NSError *)error {
    if (!error) {
        for (CBCharacteristic *characteristic in service.characteristics) {
            
            //            [peripheral discoverDescriptorsForCharacteristic:characteristic];
            NSLog(@"    Characteristic: %@", characteristic.UUID.UUIDString);
            [characteristicMap setValue:characteristic forKey:characteristic.UUID.UUIDString];
            
        }
    }
    else {
        NSLog(@"Characteristic discorvery unsuccessful!");
    }
}
- (void)peripheral:(CBPeripheral *)peripheral
didDiscoverDescriptorsForCharacteristic:(CBCharacteristic *)characteristic
             error:(NSError *)error {
    if (error) {
        NSLog(@"Error discovering descriptors for characteristic %@ %@", characteristic.UUID.UUIDString, error.localizedDescription);
        return;
    }
    
    [descriptors setValue:characteristic.descriptors forKey:characteristic.UUID.UUIDString];
    NSLog(@"    Discovered characteristic %@", characteristic.UUID.data);
    //        NSLog(@"    Descriptors: ");
    for (CBDescriptor * descriptor in characteristic.descriptors) {
        [peripheral readValueForDescriptor:descriptor];
    }
}
- (void)peripheral:(CBPeripheral *)peripheral didUpdateValueForDescriptor:(CBDescriptor *)descriptor error:(NSError *)error {
    if (error) {
        NSLog(@"Error reading updated value for descriptor %@", error.localizedDescription);
        return;
    }
    NSString *descriptorString = [NSString stringWithFormat:@"%@",descriptor.value];
    NSString *characteristicUUUIDString = descriptor.characteristic.UUID.UUIDString;
    if([descriptorString isEqualToString:@"0"]) {
        return;
    }
    //    NSLog(@"%@ %@", characteristicUUUIDString, descriptorString);
    [descriptors setValue:descriptorString forKey:characteristicUUUIDString];
    
    
}


- (void)peripheral:(CBPeripheral *)peripheral
didUpdateNotificationStateForCharacteristic:(CBCharacteristic *)characteristic
             error:(NSError *)error {
    
    
    if(error == nil) {
        if (!characteristic.isNotifying) {
            if([characteristic.UUID.UUIDString isEqualToString:FORCE_CHARACTERISTIC_UUID]) {
                lastKnownForceCharacteristicSubscriptionState = FALSE;
            }
            else if([characteristic.UUID.UUIDString isEqualToString:ACCELERATION_CHARACTERISTIC_UUID]) {
                lastKnownAccelerationCharacteristicSubscriptionState = FALSE;
            }
            else if([characteristic.UUID.UUIDString isEqualToString:ROTATION_CHARACTERISTIC_UUID]) {
                lastKnownRotationCharacteristicSubscriptionState = FALSE;
            }
            else if([characteristic.UUID.UUIDString isEqualToString:ORIENTATION_CHARACTERISTIC_UUID]) {
                lastKnownOrientationCharacteristicSubscriptionState = FALSE;
            }
            else if([characteristic.UUID.UUIDString isEqualToString:SYNCHRONIZATION_CHARACTERISTIC_UUID]) {
                lastKnownSynchronizationCharacteristicSubscriptionState = FALSE;
            }
            
        }
        else {
            //            if([characteristic.UUID.UUIDString isEqualToString:FORCE_CHARACTERISTIC_UUID]) {
            //                lastKnownForceCharacteristicSubscriptionState = TRUE;
            //            }
            //            else if([characteristic.UUID.UUIDString isEqualToString:ACCELERATION_CHARACTERISTIC_UUID]) {
            //                lastKnownAccelerationCharacteristicSubscriptionState = TRUE;
            //            }
            //            else if([characteristic.UUID.UUIDString isEqualToString:ROTATION_CHARACTERISTIC_UUID]) {
            //                lastKnownRotationCharacteristicSubscriptionState = TRUE;
            //            }
            //            else if([characteristic.UUID.UUIDString isEqualToString:ORIENTATION_CHARACTERISTIC_UUID]) {
            //                lastKnownOrientationCharacteristicSubscriptionState = TRUE;
            //            }
            //            else
            if([characteristic.UUID.UUIDString isEqualToString:SYNCHRONIZATION_CHARACTERISTIC_UUID]) {
                lastKnownSynchronizationCharacteristicSubscriptionState = TRUE;
            }
            
        }
    }
    else {
        NSLog(@"Error updating notification state for characteristic %@", characteristic.UUID.UUIDString);
        NSLog(@"%@", [error userInfo]);
    }
    
    
}


- (void)peripheral:(CBPeripheral *)peripheral
didUpdateValueForCharacteristic:(CBCharacteristic *)characteristic
             error:(NSError *)error {
    
    bool quaternionNeedsUpdating = false;
    
//    NSLog(@"Received update value for characteristic.");
    if( self.delegate == nil) {
        NSLog(@"But Peripheral Network delegate is not set. Dropping data.");
        return;
    }
    if(error) {
        NSLog(@"error: %@", error.debugDescription);
        return;
    }
    
    NSData *data = characteristic.value;
    if(data == nil) {
        NSLog(@"Empty packet update");
        return;
    }
    
    NSString *unformattedString = characteristic.value.description;
    
    NSString *characteristicValueString = unformattedString;
    characteristicValueString = [characteristicValueString stringByReplacingOccurrencesOfString:@"<" withString:@""];
    characteristicValueString = [characteristicValueString stringByReplacingOccurrencesOfString:@">" withString:@""];
    characteristicValueString = [characteristicValueString stringByReplacingOccurrencesOfString:@" " withString:@""];
    characteristicValueString = [characteristicValueString stringByReplacingOccurrencesOfString:@"-" withString:@""];
    if([characteristic isEqual:[characteristicMap objectForKey:BODY_SENSOR_LOCATION_CHARACTERISTIC_UUID]]){
        waitingToReceiveBodySensorLocationValue = FALSE;
       
        
        
        NSString *boardPlacementSubstring = [characteristicValueString substringWithRange:NSMakeRange(0,2)];
        
        NSScanner *scanner;
        [scanner setScanLocation:0];
        
        scanner = [NSScanner scannerWithString:boardPlacementSubstring];
        unsigned int boardPlacementIntValue = 0;
        [scanner scanHexInt:&boardPlacementIntValue];
        
        lastKnownLocation = (BOOGIO_PERIPHERAL_LOCATION)boardPlacementIntValue;

        
        
        NSArray *arrayOfValues =    [NSArray arrayWithObjects:
                                     [NSNumber numberWithUnsignedInteger:lastKnownLocation],
                                     nil];
        
        NSUInteger bodySensorLocationValue = [arrayOfValues[0] integerValue];
        
        NSLog(@"Body Sensor Location = %lu", (unsigned long)bodySensorLocationValue);
        
        NSString *uuid = _cbPeripheralReference.identifier.UUIDString;
        NSString *name = _cbPeripheralReference.name;
        
        NSString* shoeUUIDKey;
        NSString* shoeNameKey;
        
        
        switch (bodySensorLocationValue) {
            case LEFT_SHOE:
                shoeUUIDKey = LEFT_SHOE_UUID_KEY_STRING;
                shoeNameKey = LEFT_SHOE_NAME_KEY_STRING;
                break;
            case RIGHT_SHOE:
                shoeUUIDKey = RIGHT_SHOE_UUID_KEY_STRING;
                shoeNameKey = RIGHT_SHOE_NAME_KEY_STRING;
                break;
            default:
                
                [NSException raise:NSInvalidArgumentException
                            format:@"Unrecognized Value for Body Sensor Location!"];
                break;
        }
        
        [BoogioGlobals setPersistentSettingsValue:uuid ForKey:shoeUUIDKey];
        [BoogioGlobals setPersistentSettingsValue:name ForKey:shoeNameKey];

        
        
        [self.delegate boogioPeripheral:self DidSendData:arrayOfValues ofType:BODY_SENSOR_LOCATION_TYPE];
    }
    if([characteristic isEqual:[characteristicMap objectForKey:BATTERY_LEVEL_CHARACTERISTIC_UUID]]){
        waitingToReceiveBatteryLevelValue = FALSE;
        
        NSString *batteryLevelSubstring = [characteristicValueString substringWithRange:NSMakeRange(0,2)];
        
        NSScanner *scanner;
        [scanner setScanLocation:0];
        
        scanner = [NSScanner scannerWithString:batteryLevelSubstring];
        unsigned int batteryLevelIntValue = 0;
        [scanner scanHexInt:&batteryLevelIntValue];
        
        batteryLevel = (NSUInteger)batteryLevelIntValue;
        
        
        NSArray *arrayOfValues =    [NSArray arrayWithObjects:
                                     [NSNumber numberWithUnsignedInteger:batteryLevel],
                                     nil];
        
        
        [self.delegate boogioPeripheral:self DidSendData:arrayOfValues ofType:BATTERY_LEVEL_TYPE];
    }
    else if(   [characteristic isEqual:[characteristicMap objectForKey:FORCE_CHARACTERISTIC_UUID]]){
        
        //        NSLog(@"%@", characteristicValueString);
        
        lastKnownForceCharacteristicSubscriptionState = TRUE;

        NSString *toeFSRSubstringLowByte           = [characteristicValueString substringWithRange:NSMakeRange(0,2)];
        NSString *toeFSRSubstringHighByte          = [characteristicValueString substringWithRange:NSMakeRange(2,2)];
        
        NSString *ballFSRSubstringLowByte          = [characteristicValueString substringWithRange:NSMakeRange(4,2)];
        NSString *ballFSRSubstringHighByte         = [characteristicValueString substringWithRange:NSMakeRange(6,2)];
        
        NSString *archFSRSubstringLowByte          = [characteristicValueString substringWithRange:NSMakeRange(8,2)];
        NSString *archFSRSubstringHighByte         = [characteristicValueString substringWithRange:NSMakeRange(10,2)];
        
        NSString *heelFSRSubstringLowByte          = [characteristicValueString substringWithRange:NSMakeRange(12,2)];
        NSString *heelFSRSubstringHighByte         = [characteristicValueString substringWithRange:NSMakeRange(14,2)];
        


        //Generate Big-Endian Byte Strings
        NSString *toeFSRSubstring  = [NSString stringWithFormat:@"%@%@",toeFSRSubstringHighByte, toeFSRSubstringLowByte];
        NSString *ballFSRSubstring = [NSString stringWithFormat:@"%@%@",ballFSRSubstringHighByte, ballFSRSubstringLowByte];
        NSString *archFSRSubstring = [NSString stringWithFormat:@"%@%@",archFSRSubstringHighByte, archFSRSubstringLowByte];
        NSString *heelFSRSubstring = [NSString stringWithFormat:@"%@%@",heelFSRSubstringHighByte, heelFSRSubstringLowByte];
        
        
        //Convert from hex to integer
        
        NSScanner *scanner;
        [scanner setScanLocation:0];
        
        scanner = [NSScanner scannerWithString:toeFSRSubstring];
        unsigned int toeFSR32_t = 0;
        [scanner scanHexInt:&toeFSR32_t];
        
        scanner = [NSScanner scannerWithString:ballFSRSubstring];
        unsigned int ballFSR32_t = 0;
        [scanner scanHexInt:&ballFSR32_t];
        
        scanner = [NSScanner scannerWithString:archFSRSubstring];
        unsigned int archFSR32_t = 0;
        [scanner scanHexInt:&archFSR32_t];
        
        scanner = [NSScanner scannerWithString:heelFSRSubstring];
        unsigned int heelFSR32_t = 0;
        [scanner scanHexInt:&heelFSR32_t];
        
     
        
        
        //convert from integer to uint16_t
        
        
        UInt16 toeFSR = [[NSNumber numberWithInt:toeFSR32_t]shortValue];
        UInt16 ballFSR = [[NSNumber numberWithInt:ballFSR32_t]shortValue];
        UInt16 archFSR = [[NSNumber numberWithInt:archFSR32_t]shortValue];
        UInt16 heelFSR = [[NSNumber numberWithInt:heelFSR32_t]shortValue];
        
        
        
        
//        NSLog(@"%hu", toeFSR);
        
        float signedToeFSR  = (float)toeFSR  / 100.0f;
        float signedBallFSR = (float)ballFSR / 100.0f;;
        float signedArchFSR = (float)archFSR / 100.0f;;
        float signedHeelFSR = (float)heelFSR / 100.0f;;

        
       
        
        

        //Translate the X,Y,Z values from unitless numbers to values based on Gravities units and resolution
        
        NSArray *arrayOfValues =    [NSArray arrayWithObjects:
                                     [NSNumber numberWithFloat:signedToeFSR],
                                     [NSNumber numberWithFloat:signedBallFSR],
                                     [NSNumber numberWithFloat:signedArchFSR],
                                     [NSNumber numberWithFloat:signedHeelFSR],
                                                                          nil];

//        NSLog(@"[%hu %hu %hu %hu]",
//                                                [arrayOfValues[0] shortValue],
//                                                [arrayOfValues[1] shortValue],
//                                                [arrayOfValues[2] shortValue],
//                                                [arrayOfValues[3] shortValue]);


        [self.delegate boogioPeripheral:self DidSendData:arrayOfValues ofType:FORCE_TYPE];
    }
    else if(   [characteristic isEqual:[characteristicMap objectForKey:ACCELERATION_CHARACTERISTIC_UUID]]){
        
        //        NSLog(@"%@", characteristicValueString);
        
        lastKnownAccelerationCharacteristicSubscriptionState = TRUE;
        
        quaternionNeedsUpdating = true;
        
        NSString *accelerationXSubstringLowByte    = [characteristicValueString substringWithRange:NSMakeRange(0,2)];
        NSString *accelerationXSubstringHighByte   = [characteristicValueString substringWithRange:NSMakeRange(2,2)];
        
        NSString *accelerationYSubstringLowByte    = [characteristicValueString substringWithRange:NSMakeRange(4,2)];
        NSString *accelerationYSubstringHighByte   = [characteristicValueString substringWithRange:NSMakeRange(6,2)];
        
        NSString *accelerationZSubstringLowByte    = [characteristicValueString substringWithRange:NSMakeRange(8,2)];
        NSString *accelerationZSubstringHighByte   = [characteristicValueString substringWithRange:NSMakeRange(10,2)];
        
       
        
        
        NSString *accelerationXSubstring  = [NSString stringWithFormat:@"%@%@",accelerationXSubstringHighByte, accelerationXSubstringLowByte];
        NSString *accelerationYSubstring  = [NSString stringWithFormat:@"%@%@",accelerationYSubstringHighByte, accelerationYSubstringLowByte];
        NSString *accelerationZSubstring  = [NSString stringWithFormat:@"%@%@",accelerationZSubstringHighByte, accelerationZSubstringLowByte];
        
        
        //Convert from hex to integer
        
        NSScanner *scanner;
        [scanner setScanLocation:0];
        
        
        scanner = [NSScanner scannerWithString:accelerationXSubstring];
        unsigned int accelerationX32_t = 0;
        [scanner scanHexInt:&accelerationX32_t];
        
        scanner = [NSScanner scannerWithString:accelerationYSubstring];
        unsigned int accelerationY32_t = 0;
        [scanner scanHexInt:&accelerationY32_t];
        
        scanner = [NSScanner scannerWithString:accelerationZSubstring];
        unsigned int accelerationZ32_t = 0;
        [scanner scanHexInt:&accelerationZ32_t];
        
       
        
        
        //convert from integer to uint16_t
        
        
      
        
        UInt16 accelerationX = [[NSNumber numberWithInt:accelerationX32_t]shortValue];
        UInt16 accelerationY = [[NSNumber numberWithInt:accelerationY32_t]shortValue];
        UInt16 accelerationZ = [[NSNumber numberWithInt:accelerationZ32_t]shortValue];
        
        
        //        NSLog(@"%hu", toeFSR);
        
        
        //2's complement for the signed readings
        
        signedAccelerationXValue = (float)accelerationX;
        signedAccelerationYValue = (float)accelerationY;
        signedAccelerationZValue = (float)accelerationZ;
        
        
        if(signedAccelerationXValue > HALF_OF_MAX_SHORT_VALUE)
            signedAccelerationXValue -= MAX_SHORT_VALUE;
        
        if(signedAccelerationYValue > HALF_OF_MAX_SHORT_VALUE)
            signedAccelerationYValue -= MAX_SHORT_VALUE;
        
        if(signedAccelerationZValue > HALF_OF_MAX_SHORT_VALUE)
            signedAccelerationZValue -= MAX_SHORT_VALUE;
        

        //Convert to Meters/Second^2
        const float ACCELERATION_CONVERSION_COEFFICIENT = (MAX_ACCELERATION_READING / HALF_OF_MAX_SHORT_VALUE);
        
        signedAccelerationXValue *= ACCELERATION_CONVERSION_COEFFICIENT;
        signedAccelerationYValue *= ACCELERATION_CONVERSION_COEFFICIENT;
        signedAccelerationZValue *= ACCELERATION_CONVERSION_COEFFICIENT;
        
        
        
        //Translate the X,Y,Z values from unitless numbers to values based on Gravities units and resolution
        
        NSArray *arrayOfValues =    [NSArray arrayWithObjects:
                                     
                                     [NSNumber numberWithFloat:signedAccelerationXValue],
                                     [NSNumber numberWithFloat:signedAccelerationYValue],
                                     [NSNumber numberWithFloat:signedAccelerationZValue],
                                     
                                     nil];
        
//                NSLog(@"[%d %d %d]",
//                                                        [arrayOfValues[0] intValue],
//                                                        [arrayOfValues[1] intValue],
//                                                        [arrayOfValues[2] intValue]);
        
        
        [self.delegate boogioPeripheral:self DidSendData:arrayOfValues ofType:ACCELERATION_TYPE];
    }
    else if(   [characteristic isEqual:[characteristicMap objectForKey:ROTATION_CHARACTERISTIC_UUID]]){
        
        //        NSLog(@"%@", characteristicValueString);
        
        lastKnownRotationCharacteristicSubscriptionState = TRUE;
        
        quaternionNeedsUpdating = true;
        
        NSString *rotationXSubstringLowByte        = [characteristicValueString substringWithRange:NSMakeRange(0,2)];
        NSString *rotationXSubstringHighByte       = [characteristicValueString substringWithRange:NSMakeRange(2,2)];
        
        NSString *rotationYSubstringLowByte        = [characteristicValueString substringWithRange:NSMakeRange(4,2)];
        NSString *rotationYSubstringHighByte       = [characteristicValueString substringWithRange:NSMakeRange(6,2)];
        
        NSString *rotationZSubstringLowByte        = [characteristicValueString substringWithRange:NSMakeRange(8,2)];
        NSString *rotationZSubstringHighByte       = [characteristicValueString substringWithRange:NSMakeRange(10,2)];
        
        
        //Generate Big-Endian Byte Strings
        
        
        NSString *rotationXSubstring  = [NSString stringWithFormat:@"%@%@",rotationXSubstringHighByte, rotationXSubstringLowByte];
        NSString *rotationYSubstring  = [NSString stringWithFormat:@"%@%@",rotationYSubstringHighByte, rotationYSubstringLowByte];
        NSString *rotationZSubstring  = [NSString stringWithFormat:@"%@%@",rotationZSubstringHighByte, rotationZSubstringLowByte];
        
        
        //Convert from hex to integer
        
        NSScanner *scanner;
        [scanner setScanLocation:0];
        
        
        scanner = [NSScanner scannerWithString:rotationXSubstring];
        unsigned int rotationX32_t = 0;
        [scanner scanHexInt:&rotationX32_t];
        
        scanner = [NSScanner scannerWithString:rotationYSubstring];
        unsigned int rotationY32_t = 0;
        [scanner scanHexInt:&rotationY32_t];
        
        scanner = [NSScanner scannerWithString:rotationZSubstring];
        unsigned int rotationZ32_t = 0;
        [scanner scanHexInt:&rotationZ32_t];
        
        
        //convert from integer to uint16_t
        
        
     
        
        UInt16 rotationX = [[NSNumber numberWithInt:rotationX32_t]shortValue];
        UInt16 rotationY = [[NSNumber numberWithInt:rotationY32_t]shortValue];
        UInt16 rotationZ = [[NSNumber numberWithInt:rotationZ32_t]shortValue];
        
        
        
        
        //        NSLog(@"%hu", toeFSR);
       
        
        
        //2's complement for the signed readings
        
        
        
        signedRotationXValue = (float)rotationX;
        signedRotationYValue = (float)rotationY;
        signedRotationZValue = (float)rotationZ;
        
        
        
        
        
        if(signedRotationXValue > HALF_OF_MAX_SHORT_VALUE)
            signedRotationXValue -= MAX_SHORT_VALUE;
        
        if(signedRotationYValue > HALF_OF_MAX_SHORT_VALUE)
            signedRotationYValue -= MAX_SHORT_VALUE;
        
        if(signedRotationZValue > HALF_OF_MAX_SHORT_VALUE)
            signedRotationZValue -= MAX_SHORT_VALUE;
        
        const float ROTATION_CONVERSION_COEFFICIENT = (MAX_ROTATION_READING / HALF_OF_MAX_SHORT_VALUE);

        
        signedRotationXValue *= ROTATION_CONVERSION_COEFFICIENT;
        signedRotationYValue *= ROTATION_CONVERSION_COEFFICIENT;
        signedRotationZValue *= ROTATION_CONVERSION_COEFFICIENT;
        
        
        
        NSArray *arrayOfValues =    [NSArray arrayWithObjects:
                                     
                                     [NSNumber numberWithFloat:signedRotationXValue],
                                     [NSNumber numberWithFloat:signedRotationYValue],
                                     [NSNumber numberWithFloat:signedRotationZValue],
                                     nil];
        
//        NSLog(@"[%f %f %f]",
//              [arrayOfValues[0] floatValue],
//              [arrayOfValues[1] floatValue],
//              [arrayOfValues[2] floatValue]);
//        NSLog(@"%@", characteristicValueString);
        
        [self.delegate boogioPeripheral:self DidSendData:arrayOfValues ofType:ROTATION_TYPE];
    }
    else if(   [characteristic isEqual:[characteristicMap objectForKey:ORIENTATION_CHARACTERISTIC_UUID]]){
        
        quaternionNeedsUpdating = true;
        
        lastKnownOrientationCharacteristicSubscriptionState = TRUE;
        
        NSString *orientationXSubstringLowByte    = [characteristicValueString substringWithRange:NSMakeRange(0,2)];
        NSString *orientationXSubstringHighByte   = [characteristicValueString substringWithRange:NSMakeRange(2,2)];
        
        NSString *orientationYSubstringLowByte    = [characteristicValueString substringWithRange:NSMakeRange(4,2)];
        NSString *orientationYSubstringHighByte   = [characteristicValueString substringWithRange:NSMakeRange(6,2)];
        
        NSString *orientationZSubstringLowByte    = [characteristicValueString substringWithRange:NSMakeRange(8,2)];
        NSString *orientationZSubstringHighByte   = [characteristicValueString substringWithRange:NSMakeRange(10,2)];
        
        
        
        
        NSString *orientationXSubstring  = [NSString stringWithFormat:@"%@%@",orientationXSubstringHighByte, orientationXSubstringLowByte];
        NSString *orientationYSubstring  = [NSString stringWithFormat:@"%@%@",orientationYSubstringHighByte, orientationYSubstringLowByte];
        NSString *orientationZSubstring  = [NSString stringWithFormat:@"%@%@",orientationZSubstringHighByte, orientationZSubstringLowByte];
        
        
        //Convert from hex to integer
        
        NSScanner *scanner;
        [scanner setScanLocation:0];
        
        
        scanner = [NSScanner scannerWithString:orientationXSubstring];
        unsigned int orientationX32_t = 0;
        [scanner scanHexInt:&orientationX32_t];
        
        scanner = [NSScanner scannerWithString:orientationYSubstring];
        unsigned int orientationY32_t = 0;
        [scanner scanHexInt:&orientationY32_t];
        
        scanner = [NSScanner scannerWithString:orientationZSubstring];
        unsigned int orientationZ32_t = 0;
        [scanner scanHexInt:&orientationZ32_t];
        
        
        
        
        //convert from integer to uint16_t
        
        
        
        
        UInt16 orientationX = [[NSNumber numberWithInt:orientationX32_t]shortValue];
        UInt16 orientationY = [[NSNumber numberWithInt:orientationY32_t]shortValue];
        UInt16 orientationZ = [[NSNumber numberWithInt:orientationZ32_t]shortValue];
        
        
        //        NSLog(@"%hu", toeFSR);
        
        
        //2's complement for the signed readings
        
        signedOrientationXValue = (float)orientationX;
        signedOrientationYValue = (float)orientationY;
        signedOrientationZValue = (float)orientationZ;
        
        
        if(signedOrientationXValue > HALF_OF_MAX_SHORT_VALUE)
            signedOrientationXValue -= MAX_SHORT_VALUE;
        
        if(signedOrientationYValue > HALF_OF_MAX_SHORT_VALUE)
            signedOrientationYValue -= MAX_SHORT_VALUE;
        
        if(signedOrientationZValue > HALF_OF_MAX_SHORT_VALUE)
            signedOrientationZValue -= MAX_SHORT_VALUE;
        
        const float DIRECTION_CONVERSION_COEFFICIENT = (MAX_DIRECTION_READING / HALF_OF_MAX_SHORT_VALUE);
        
        
        signedOrientationXValue *= DIRECTION_CONVERSION_COEFFICIENT;
        signedOrientationYValue *= DIRECTION_CONVERSION_COEFFICIENT;
        signedOrientationZValue *= DIRECTION_CONVERSION_COEFFICIENT;
        
        
        
        //Translate the X,Y,Z values from unitless numbers to values based on Gravities units and resolution
        
        NSArray *arrayOfValues =    [NSArray arrayWithObjects:
                                     [NSNumber numberWithFloat:signedOrientationXValue],
                                     [NSNumber numberWithFloat:signedOrientationYValue],
                                     [NSNumber numberWithFloat:signedOrientationZValue],
                                     
                                     nil];
        
//        NSLog(@"[%2.2f %2.2f %2.2f]",
//              [arrayOfValues[0] floatValue],
//              [arrayOfValues[1] floatValue],
//              [arrayOfValues[2] floatValue]);
        
        [self.delegate boogioPeripheral:self DidSendData:arrayOfValues ofType:DIRECTION_TYPE];
    }
    else if(   [characteristic isEqual:[characteristicMap objectForKey:SYNCHRONIZATION_CHARACTERISTIC_UUID]]){
      
        

        
//        NSLog(@"%@", characteristicValueString);
        
        if([characteristicValueString length] == 4) {
            
            
            
//            [self unsubscribeFromNotificationsAbout:SYNCHRONIZATION_TYPE];
            
            
            NSString *errorCodeString            = [characteristicValueString substringWithRange:NSMakeRange(0,2)];
            NSString *errorTypeString            = [characteristicValueString substringWithRange:NSMakeRange(2,2)];
            NSScanner *scanner;
            [scanner setScanLocation:0];
            
            scanner = [NSScanner scannerWithString:errorCodeString];
            unsigned int errorCode32_t = 0;
            [scanner scanHexInt:&errorCode32_t];
            
            scanner = [NSScanner scannerWithString:errorTypeString];
            unsigned int errorType32_t = 0;
            [scanner scanHexInt:&errorType32_t];

            UInt8  errorCode       = [[NSNumber numberWithInt:errorCode32_t]charValue];
            UInt8  errorType         = [[NSNumber numberWithInt:errorType32_t]charValue];
            
            NSArray *arrayOfValues =    [NSArray arrayWithObjects:
                                         [NSNumber numberWithFloat:errorCode],
                                         [NSNumber numberWithFloat:errorType],
                                         nil];
            
            
            [self.delegate boogioPeripheral:self DidSendData:arrayOfValues ofType:SYNCHRONIZATION_TYPE];
            return;
        }
        
        NSString *value0LowByteString;
        NSString *value0HighByteString;
        NSString *value1LowByteString;
        NSString *value1HighByteString;
        NSString *value2LowByteString;
        NSString *value2HighByteString;
        
        NSString *dataTypeString            = [characteristicValueString substringWithRange:NSMakeRange(0,2)];
        NSString *yearLowByteString         = [characteristicValueString substringWithRange:NSMakeRange(2,2)];
        NSString *yearHighByteString        = [characteristicValueString substringWithRange:NSMakeRange(4,2)];
        NSString *monthString               = [characteristicValueString substringWithRange:NSMakeRange(6,2)];
        NSString *dayString                 = [characteristicValueString substringWithRange:NSMakeRange(8,2)];
        NSString *hourString                = [characteristicValueString substringWithRange:NSMakeRange(10,2)];
        NSString *minuteString              = [characteristicValueString substringWithRange:NSMakeRange(12,2)];
        NSString *secondString              = [characteristicValueString substringWithRange:NSMakeRange(14,2)];
        NSString *millisecondLowByteString  = [characteristicValueString substringWithRange:NSMakeRange(16,2)];
        NSString *millisecondHighByteString = [characteristicValueString substringWithRange:NSMakeRange(18,2)];

        NSString *yearString;
        NSString *millisecondString;
        NSString *value0String;
        NSString *value1String;
        NSString *value2String;



        yearString                    = [NSString stringWithFormat:@"%@%@", yearHighByteString, yearLowByteString];
        millisecondString             = [NSString stringWithFormat:@"%@%@", millisecondHighByteString, millisecondLowByteString];

        if([characteristicValueString length] >= 24) {
            value0LowByteString       = [characteristicValueString substringWithRange:NSMakeRange(20,2)];
            value0HighByteString      = [characteristicValueString substringWithRange:NSMakeRange(22,2)];
            value0String              = [NSString stringWithFormat:@"%@%@", value0HighByteString, value0LowByteString];
        }
        if([characteristicValueString length] >= 28) {
            value1LowByteString       = [characteristicValueString substringWithRange:NSMakeRange(24,2)];
            value1HighByteString      = [characteristicValueString substringWithRange:NSMakeRange(26,2)];
            value1String              = [NSString stringWithFormat:@"%@%@", value1HighByteString, value1LowByteString];
        }
        if([characteristicValueString length] >= 30) {
            value2LowByteString       = [characteristicValueString substringWithRange:NSMakeRange(28,2)];
            value2HighByteString      = [characteristicValueString substringWithRange:NSMakeRange(30,2)];
            value2String              = [NSString stringWithFormat:@"%@%@", value2HighByteString, value2LowByteString];
        }


        
        
        
        
        //Convert from hex to integer
        
        NSScanner *scanner;
        [scanner setScanLocation:0];
        
        scanner = [NSScanner scannerWithString:dataTypeString];
        unsigned int dataType32_t = 0;
        [scanner scanHexInt:&dataType32_t];
        
        scanner = [NSScanner scannerWithString:yearString];
        unsigned int year32_t = 0;
        [scanner scanHexInt:&year32_t];
       
        scanner = [NSScanner scannerWithString:monthString];
        unsigned int month32_t = 0;
        [scanner scanHexInt:&month32_t];
        
        scanner = [NSScanner scannerWithString:dayString];
        unsigned int day32_t = 0;
        [scanner scanHexInt:&day32_t];
        
        scanner = [NSScanner scannerWithString:hourString];
        unsigned int hour32_t = 0;
        [scanner scanHexInt:&hour32_t];
        
        scanner = [NSScanner scannerWithString:minuteString];
        unsigned int minute32_t = 0;
        [scanner scanHexInt:&minute32_t];
        
        scanner = [NSScanner scannerWithString:secondString];
        unsigned int second32_t = 0;
        [scanner scanHexInt:&second32_t];
        
        scanner = [NSScanner scannerWithString:millisecondString];
        unsigned int millisecond32_t = 0;
        [scanner scanHexInt:&millisecond32_t];

        unsigned int value032_t = 0;
        unsigned int value132_t = 0;
        unsigned int value232_t = 0;
        
        if([characteristicValueString length] >= 24) {
            scanner = [NSScanner scannerWithString:value0String];
            [scanner scanHexInt:&value032_t];
        }
        if([characteristicValueString length] >= 28) {
            scanner = [NSScanner scannerWithString:value1String];
            [scanner scanHexInt:&value132_t];
        }
        
        if([characteristicValueString length] >= 30) {
            scanner = [NSScanner scannerWithString:value2String];
            [scanner scanHexInt:&value232_t];
        }

        
        
        
        //convert from integer to uint16_t
        UInt16 year        = [[NSNumber numberWithInt:year32_t]shortValue];
        UInt8  month       = [[NSNumber numberWithInt:month32_t]charValue];
        UInt8  day         = [[NSNumber numberWithInt:day32_t]charValue];
        UInt8  hour        = [[NSNumber numberWithInt:hour32_t]charValue];
        UInt8  minute      = [[NSNumber numberWithInt:minute32_t]charValue];
        UInt8  second      = [[NSNumber numberWithInt:second32_t]charValue];
        UInt16 millisecond = [[NSNumber numberWithInt:millisecond32_t]shortValue];
        UInt16 value0      = [[NSNumber numberWithInt:value032_t]shortValue];
        UInt16 value1      = [[NSNumber numberWithInt:value132_t]shortValue];
        UInt16 value2      = [[NSNumber numberWithInt:value232_t]shortValue];
        
        
        
        
        float signedValue0 = 0;
        float signedValue1 = 0;
        float signedValue2 = 0;
        //        NSLog(@"%hu", toeFSR);
        
        
        //2's complement for the signed readings
        if( dataType32_t == 6 || dataType32_t == 7 || dataType32_t == 8) {
            signedValue0 = (float)value0;
            signedValue1 = (float)value1;
            signedValue2 = (float)value2;
            
            if(signedValue0 > HALF_OF_MAX_SHORT_VALUE)
                signedValue0 -= MAX_SHORT_VALUE;
            
            if(signedValue1 > HALF_OF_MAX_SHORT_VALUE)
                signedValue1 -= MAX_SHORT_VALUE;
            
            if(signedValue2 > HALF_OF_MAX_SHORT_VALUE)
                signedValue2 -= MAX_SHORT_VALUE;

        }
        
        if(dataType32_t == 4 || dataType32_t == 5 || dataType32_t == 6 || dataType32_t == 7 || dataType32_t == 8) {
            lastKnownSynchronizationCharacteristicSubscriptionState = TRUE;
        }
        
        if(dataType32_t == 6) {
            const float ACCELERATION_CONVERSION_COEFFICIENT = (MAX_ACCELERATION_READING / HALF_OF_MAX_SHORT_VALUE);
            
            signedValue0 *= ACCELERATION_CONVERSION_COEFFICIENT;
            signedValue1 *= ACCELERATION_CONVERSION_COEFFICIENT;
            signedValue2 *= ACCELERATION_CONVERSION_COEFFICIENT;
        }
        else if(dataType32_t == 7) {
            const float ROTATION_CONVERSION_COEFFICIENT = (MAX_ROTATION_READING / HALF_OF_MAX_SHORT_VALUE);
            
            signedValue0 *= ROTATION_CONVERSION_COEFFICIENT;
            signedValue1 *= ROTATION_CONVERSION_COEFFICIENT;
            signedValue2 *= ROTATION_CONVERSION_COEFFICIENT;
        }
        else if(dataType32_t == 8) {
            const float DIRECTION_CONVERSION_COEFFICIENT = (MAX_DIRECTION_READING / HALF_OF_MAX_SHORT_VALUE);
            
            signedValue0 *= DIRECTION_CONVERSION_COEFFICIENT;
            signedValue1 *= DIRECTION_CONVERSION_COEFFICIENT;
            signedValue2 *= DIRECTION_CONVERSION_COEFFICIENT;
        }
        
        
        NSArray *arrayOfValues =    [NSArray arrayWithObjects:
                                     [NSNumber numberWithFloat:dataType32_t],
                                     [NSNumber numberWithFloat:year],
                                     [NSNumber numberWithFloat:month],
                                     [NSNumber numberWithFloat:day],
                                     [NSNumber numberWithFloat:hour],
                                     [NSNumber numberWithFloat:minute],
                                     [NSNumber numberWithFloat:second],
                                     [NSNumber numberWithFloat:millisecond],
                                     [NSNumber numberWithFloat:signedValue0],
                                     [NSNumber numberWithFloat:signedValue1],
                                     [NSNumber numberWithFloat:signedValue2],
                                     nil];
        
        
        

        
        switch (dataType32_t) {
            case 4:

                if(waitingToReceiveToeAndBallSynchronizationPacket) {
                    currentYear            = [[arrayOfValues objectAtIndex:1] intValue];
                    currentMonth           = [[arrayOfValues objectAtIndex:2] intValue];
                    currentDay             = [[arrayOfValues objectAtIndex:3] intValue];
                    currentHour            = [[arrayOfValues objectAtIndex:4] intValue];
                    currentMinute          = [[arrayOfValues objectAtIndex:5] intValue];
                    currentSecond          = [[arrayOfValues objectAtIndex:6] intValue];
                    currentMillisecond     = [[arrayOfValues objectAtIndex:7] intValue];
                    
                    currentToe             = [[arrayOfValues objectAtIndex:8] intValue];
                    currentBall            = [[arrayOfValues objectAtIndex:9] intValue];
                }
                waitingToReceiveToeAndBallSynchronizationPacket = FALSE;
                break;
            case 5:
                if(waitingToReceiveArchAndHeelSynchronizationPacket) {
                    currentArch            = [[arrayOfValues objectAtIndex:8] intValue];
                    currentHeel            = [[arrayOfValues objectAtIndex:9] intValue];
                }
                waitingToReceiveArchAndHeelSynchronizationPacket = FALSE;
                break;
            case 6:
                if(waitingToReceiveAccelerationSynchronizationPacket) {
                    currentAccelerationX   = [[arrayOfValues objectAtIndex:8] intValue];
                    currentAccelerationY   = [[arrayOfValues objectAtIndex:9] intValue];
                    currentAccelerationZ   = [[arrayOfValues objectAtIndex:10] intValue];
                }
                waitingToReceiveAccelerationSynchronizationPacket = FALSE;
                break;
            case 7:
                if(waitingToReceiveRotationSynchronizationPacket) {
                    currentRotationX       = [[arrayOfValues objectAtIndex:8] intValue];
                    currentRotationY       = [[arrayOfValues objectAtIndex:9] intValue];
                    currentRotationZ       = [[arrayOfValues objectAtIndex:10] intValue];
                }
                waitingToReceiveRotationSynchronizationPacket = FALSE;
                break;
            case 8:
                if(waitingToReceiveDirectionSynchronizationPacket) {
                    currentDirectionX      = [[arrayOfValues objectAtIndex:8] intValue];
                    currentDirectionY      = [[arrayOfValues objectAtIndex:9] intValue];
                    currentDirectionZ      = [[arrayOfValues objectAtIndex:10] intValue];
                }
                waitingToReceiveDirectionSynchronizationPacket = FALSE;
                break;
                
            default:
                break;
        }
        
        if (     !waitingToReceiveToeAndBallSynchronizationPacket
              && !waitingToReceiveArchAndHeelSynchronizationPacket
              && !waitingToReceiveAccelerationSynchronizationPacket
              && !waitingToReceiveRotationSynchronizationPacket
              && !waitingToReceiveDirectionSynchronizationPacket) {

            

            
//            NSString *line = [NSString stringWithFormat:@"%d, %d, %d, %d, %d, %d, %d, %d, %d, %d, %d, %d, %d, %d, %d, %d, %d, %d, %d, %d \n", currentYear, currentMonth, currentDay, currentHour, currentMinute, currentSecond, currentMillisecond, currentToe, currentBall, currentArch, currentHeel, currentAccelerationX, currentAccelerationY, currentAccelerationZ, currentRotationX, currentRotationY, currentRotationZ, currentDirectionX, currentDirectionY, currentDirectionZ];
            
            
            [self synchronizationTimeout];
            sentSynchronizationRequestEarly = TRUE;
            
            
        }

        [self.delegate boogioPeripheral:self DidSendData:arrayOfValues ofType:SYNCHRONIZATION_TYPE];
    }
    
    
    // Calculate AHRS Quaternion using Madgwick's Algorithm
    
    
    if(   lastKnownAccelerationCharacteristicSubscriptionState
       && lastKnownRotationCharacteristicSubscriptionState
       && lastKnownOrientationCharacteristicSubscriptionState
       && quaternionNeedsUpdating)
    {
        
        // X = Roll
        // Y = Pitch?
        // Z = Yaw?
        [self updateWithGyroscopeX:(float)signedRotationZValue * ( M_PI / 180.0f) * ahrsSensitivity
                        gyroscopeY:(float)-signedRotationYValue * ( M_PI / 180.0f) * ahrsSensitivity
                        gyroscopeZ:(float)signedRotationXValue * ( M_PI / 180.0f) * ahrsSensitivity
                    accelerometerX:(float)signedAccelerationZValue
                    accelerometerY:(float)-signedAccelerationXValue
                    accelerometerZ:(float)signedAccelerationYValue
                     magnetometerX:(float)signedOrientationZValue
                     magnetometerY:(float)-signedOrientationYValue
                     magnetometerZ:(float)signedOrientationXValue];
        
        /* Flip Y and X rotation to respect the rotations AROUND the axis
        [self updateWithGyroscopeX:(float)signedRotationYValue/100.0f
                        gyroscopeY:(float)signedRotationXValue/100.0f
                        gyroscopeZ:(float)signedRotationZValue/100.0f
                    accelerometerX:(float)signedAccelerationXValue
                    accelerometerY:(float)signedAccelerationYValue
                    accelerometerZ:(float)signedAccelerationZValue
                     magnetometerX:(float)signedOrientationXValue
                     magnetometerY:(float)signedOrientationYValue
                     magnetometerZ:(float)signedOrientationZValue];*/

        
//        float smoothing = 10000.0f;
//        _q0 /= smoothing;
//        _q1 /= smoothing;
//        _q2 /= smoothing;
//        _q3 /= smoothing;
        
        NSArray *arrayOfValues =    [NSArray arrayWithObjects:
                                     [NSNumber numberWithFloat:_q0],
                                     [NSNumber numberWithFloat:_q1],
                                     [NSNumber numberWithFloat:_q2],
                                     [NSNumber numberWithFloat:_q3],
                                     nil];
        [self.delegate boogioPeripheral:self DidSendData:arrayOfValues ofType:AHRS_QUATERNION_TYPE];

    }
    else {
        //Reset the AHRS quaternion
        [self resetQuaternionWithSampleFrequencyHz:SAMPLE_RATE beta:0];
    }
    
    
}

//-----------------------------------------------------------------------------------
//External Interface
//-----------------------------------------------------------------------------------
//-----------------------------------------------------------------------------------
- (NSNumber *)getRSSI{
    return rssi;
}
- (void) setRSSI:(NSNumber *)RSSI {
    rssi = RSSI;
}
- (void)subscribeForNotificationsAbout:(BOOGIO_DATA_TYPE)dataType {
    

    switch (dataType) {
        case FORCE_TYPE:
            intendedForceCharacteristicSubscriptionState = TRUE;
            break;
        case ACCELERATION_TYPE:
            intendedAccelerationCharacteristicSubscriptionState = TRUE;
            break;
        case ROTATION_TYPE:
            intendedRotationCharacteristicSubscriptionState = TRUE;
            break;
        case DIRECTION_TYPE:
            intendedOrientationCharacteristicSubscriptionState = TRUE;
            break;
        case SYNCHRONIZATION_TYPE:
            intendedSynchronizationCharacteristicSubscriptionState = TRUE;
            break;
            
        default:
            break;
    }
    
    if([self getConnectionState] != CBPeripheralStateConnected) {
        return;
    }

    if(dataType == FORCE_TYPE && lastKnownForceCharacteristicSubscriptionState == TRUE) {
        return;
    }
    else if(dataType == ACCELERATION_TYPE && lastKnownAccelerationCharacteristicSubscriptionState == TRUE) {
        return;
    }
    else if(dataType == ROTATION_TYPE && lastKnownRotationCharacteristicSubscriptionState == TRUE) {
        return;
    }
    else if(dataType == DIRECTION_TYPE && lastKnownOrientationCharacteristicSubscriptionState == TRUE) {
        return;
    }
    else if(dataType == SYNCHRONIZATION_TYPE && lastKnownSynchronizationCharacteristicSubscriptionState == TRUE) {
        return;
    }
    

    
    CBCharacteristic *characteristic = [self getCharacteristic:dataType];
    if(characteristic == nil) {
        NSLog(@"Characteristic is nil. Cannot subscribe.");
        return;
    }
//    NSLog(@"Attempting to subscribe to %@", characteristic.UUID.UUIDString);
    [_cbPeripheralReference setNotifyValue:TRUE forCharacteristic:characteristic];
}

- (void)unsubscribeFromNotificationsAbout:(BOOGIO_DATA_TYPE)dataType {
    
    
    switch (dataType) {
        case FORCE_TYPE:
            intendedForceCharacteristicSubscriptionState = FALSE;
            break;
        case ACCELERATION_TYPE:
            intendedAccelerationCharacteristicSubscriptionState = FALSE;
            break;
        case ROTATION_TYPE:
            intendedRotationCharacteristicSubscriptionState = FALSE;
            break;
        case DIRECTION_TYPE:
            intendedOrientationCharacteristicSubscriptionState = FALSE;
            break;
        case SYNCHRONIZATION_TYPE:
            intendedSynchronizationCharacteristicSubscriptionState = FALSE;
            break;
        default:
            break;
    }
    
    if([self getConnectionState] != CBPeripheralStateConnected) {
        return;
    }
    
    if(dataType == FORCE_TYPE && lastKnownForceCharacteristicSubscriptionState == FALSE) {
        return;
    }
    else if(dataType == ACCELERATION_TYPE && lastKnownAccelerationCharacteristicSubscriptionState == FALSE) {
        return;
    }
    else if(dataType == ROTATION_TYPE && lastKnownRotationCharacteristicSubscriptionState == FALSE) {
        return;
    }
    else if(dataType == DIRECTION_TYPE && lastKnownOrientationCharacteristicSubscriptionState == FALSE) {
        return;
    }
    else if(dataType == SYNCHRONIZATION_TYPE && lastKnownSynchronizationCharacteristicSubscriptionState == FALSE) {
        return;
    }
    
    
    CBCharacteristic *characteristic = [self getCharacteristic:dataType];
    if(characteristic == nil) {
        NSLog(@"Characteristic is nil. Cannot unsubscribe.");
        return;
    }
    //    NSLog(@"Attempting to unsubscribe from %@", characteristic.UUID.UUIDString);
    [_cbPeripheralReference setNotifyValue:FALSE forCharacteristic:characteristic];
    
}


- (CBCharacteristic *)getCharacteristic:(BOOGIO_DATA_TYPE)dataType {
    
    //if the characteristic is nil,
    //for each service in the service map, discover characteristics again
    
    if([self getConnectionState] != CBPeripheralStateConnected) {
        return nil;
    }
    
    CBCharacteristic *characteristic;
    
    switch (dataType) {
        
        case BATTERY_LEVEL_TYPE:
            characteristic = [characteristicMap valueForKey:[BATTERY_LEVEL_CHARACTERISTIC_UUID uppercaseString]];
            break;
        case BODY_SENSOR_LOCATION_TYPE:
            characteristic = [characteristicMap valueForKey:[BODY_SENSOR_LOCATION_CHARACTERISTIC_UUID uppercaseString]];
            break;
        case FORCE_TYPE:
            characteristic = [characteristicMap valueForKey:[FORCE_CHARACTERISTIC_UUID uppercaseString]];
            break;
        case ACCELERATION_TYPE:
            characteristic = [characteristicMap valueForKey:[ACCELERATION_CHARACTERISTIC_UUID uppercaseString]];
            break;
        case ROTATION_TYPE:
            characteristic = [characteristicMap valueForKey:[ROTATION_CHARACTERISTIC_UUID uppercaseString]];
            break;
        case DIRECTION_TYPE:
            characteristic = [characteristicMap valueForKey:[ORIENTATION_CHARACTERISTIC_UUID uppercaseString]];
            break;
        case SYNCHRONIZATION_TYPE:
            characteristic = [characteristicMap valueForKey:[SYNCHRONIZATION_CHARACTERISTIC_UUID uppercaseString]];
            break;

        default:
            characteristic = nil;
            
            break;
            
    }
    if(characteristic == nil) {
        
        for (CBService *service in _cbPeripheralReference.services) {
//            [_cbPeripheralReference discoverIncludedServices:nil forService:service];
            [_cbPeripheralReference discoverCharacteristics:nil forService:service];
        }
        
    }
    
    return characteristic;
}
- (BOOL)readDataFromBoogioPeripheral:(BOOGIO_DATA_TYPE)dataType {
    
    if([self getConnectionState] != CBPeripheralStateConnected) {
        return FALSE;
    }
    
    
    CBCharacteristic *characteristic;
    switch (dataType) {
        case RSSI_TYPE:
            [_cbPeripheralReference readRSSI];
            break;
        
        default:
            characteristic = [self getCharacteristic:dataType];
            
            [self readCharacteristic:characteristic];
            break;
    }
    
    
    return TRUE;
}



//Callback forwarding from the BoogioPeripheralNetwork into the respective peripherals so the
//peripheral objects themselves can handle connection recovery
- (void)centralManager:(CBCentralManager *)central
  didConnectPeripheral:(CBPeripheral *)peripheral {
    
    NSLog(@"Peripheral %@ Connected.", peripheral.name);
    [_cbPeripheralReference discoverServices:nil];
    
    waitingToSynchronizePeripheralTime = TRUE;
    
    [self.delegate boogioPeripheralDidConnect:self];
}
- (void)centralManager:(CBCentralManager *)central
didDisconnectPeripheral:(CBPeripheral *)peripheral
                 error:(NSError *)error {
    
    lastKnownForceCharacteristicSubscriptionState = FALSE;
    lastKnownAccelerationCharacteristicSubscriptionState = FALSE;
    lastKnownRotationCharacteristicSubscriptionState = FALSE;
    lastKnownOrientationCharacteristicSubscriptionState = FALSE;
    lastKnownSynchronizationCharacteristicSubscriptionState = FALSE;
    
    [self.delegate boogioPeripheralDidDisconnect:self];
}

// Class initializer.
- (void)resetQuaternionWithSampleFrequencyHz:(float)sampleFrequencyHz
                                              beta:(float)beta;
{
    
    _sampleFrequencyHz = sampleFrequencyHz;
    _beta = beta;
    _q0 = 1.0f;
    _q1 = 0.0f;
    _q2 = 0.0f;
    _q3 = 0.0f;
    
    
}

// Update with gyroscope and accelerometer.
- (void)updateWithGyroscopeX:(float)gx
                  gyroscopeY:(float)gy
                  gyroscopeZ:(float)gz
              accelerometerX:(float)ax
              accelerometerY:(float)ay
              accelerometerZ:(float)az
{
    float recipNorm;
    float s0, s1, s2, s3;
    float qDot1, qDot2, qDot3, qDot4;
    float _2q0, _2q1, _2q2, _2q3, _4q0, _4q1, _4q2 ,_8q1, _8q2, q0q0, q1q1, q2q2, q3q3;
    
    // Rate of change of quaternion from gyroscope
    qDot1 = 0.5f * (-_q1 * gx - _q2 * gy - _q3 * gz);
    qDot2 = 0.5f * (_q0 * gx + _q2 * gz - _q3 * gy);
    qDot3 = 0.5f * (_q0 * gy - _q1 * gz + _q3 * gx);
    qDot4 = 0.5f * (_q0 * gz + _q1 * gy - _q2 * gx);
    
    // Compute feedback only if accelerometer measurement valid (avoids NaN in accelerometer normalisation)
    if (!((ax == 0.0f) && (ay == 0.0f) && (az == 0.0f)))
    {
        // Normalise accelerometer measurement
        recipNorm = invSqrt(ax * ax + ay * ay + az * az);
        ax *= recipNorm;
        ay *= recipNorm;
        az *= recipNorm;
        
        // Auxiliary variables to avoid repeated arithmetic
        _2q0 = 2.0f * _q0;
        _2q1 = 2.0f * _q1;
        _2q2 = 2.0f * _q2;
        _2q3 = 2.0f * _q3;
        _4q0 = 4.0f * _q0;
        _4q1 = 4.0f * _q1;
        _4q2 = 4.0f * _q2;
        _8q1 = 8.0f * _q1;
        _8q2 = 8.0f * _q2;
        q0q0 = _q0 * _q0;
        q1q1 = _q1 * _q1;
        q2q2 = _q2 * _q2;
        q3q3 = _q3 * _q3;
        
        // Gradient decent algorithm corrective step
        s0 = _4q0 * q2q2 + _2q2 * ax + _4q0 * q1q1 - _2q1 * ay;
        s1 = _4q1 * q3q3 - _2q3 * ax + 4.0f * q0q0 * _q1 - _2q0 * ay - _4q1 + _8q1 * q1q1 + _8q1 * q2q2 + _4q1 * az;
        s2 = 4.0f * q0q0 * _q2 + _2q0 * ax + _4q2 * q3q3 - _2q3 * ay - _4q2 + _8q2 * q1q1 + _8q2 * q2q2 + _4q2 * az;
        s3 = 4.0f * q1q1 * _q3 - _2q1 * ax + 4.0f * q2q2 * _q3 - _2q2 * ay;
        recipNorm = invSqrt(s0 * s0 + s1 * s1 + s2 * s2 + s3 * s3); // normalise step magnitude
        s0 *= recipNorm;
        s1 *= recipNorm;
        s2 *= recipNorm;
        s3 *= recipNorm;
        
        // Apply feedback step
        qDot1 -= _beta * s0;
        qDot2 -= _beta * s1;
        qDot3 -= _beta * s2;
        qDot4 -= _beta * s3;
    }
    
    // Integrate rate of change of quaternion to yield quaternion
    _q0 += qDot1 * (1.0f / _sampleFrequencyHz);
    _q1 += qDot2 * (1.0f / _sampleFrequencyHz);
    _q2 += qDot3 * (1.0f / _sampleFrequencyHz);
    _q3 += qDot4 * (1.0f / _sampleFrequencyHz);
    
    // Normalise quaternion
    recipNorm = invSqrt(_q0 * _q0 + _q1 * _q1 + _q2 * _q2 + _q3 * _q3);
    _q0 *= recipNorm;
    _q1 *= recipNorm;
    _q2 *= recipNorm;
    _q3 *= recipNorm;
}

// Update with gyroscope, accelerometer and magnetometer.
- (void)updateWithGyroscopeX:(float)gx
                  gyroscopeY:(float)gy
                  gyroscopeZ:(float)gz
              accelerometerX:(float)ax
              accelerometerY:(float)ay
              accelerometerZ:(float)az
               magnetometerX:(float)mx
               magnetometerY:(float)my
               magnetometerZ:(float)mz
{
    float recipNorm;
    float s0, s1, s2, s3;
    float qDot1, qDot2, qDot3, qDot4;
    float hx, hy;
    float _2q0mx, _2q0my, _2q0mz, _2q1mx, _2bx, _2bz, _4bx, _4bz, _2q0, _2q1, _2q2, _2q3, _2q0q2, _2q2q3, q0q0, q0q1, q0q2, q0q3, q1q1, q1q2, q1q3, q2q2, q2q3, q3q3;
    
    // Use IMU algorithm if magnetometer measurement invalid (avoids NaN in magnetometer normalisation)
    if ((mx == 0.0f) && (my == 0.0f) && (mz == 0.0f))
    {
        [self updateWithGyroscopeX:gx
                        gyroscopeY:gy
                        gyroscopeZ:gz
                    accelerometerX:ax
                    accelerometerY:ay
                    accelerometerZ:az];
        return;
    }
    
    // Rate of change of quaternion from gyroscope
    qDot1 = 0.5f * (-_q1 * gx - _q2 * gy - _q3 * gz);
    qDot2 = 0.5f * (_q0 * gx + _q2 * gz - _q3 * gy);
    qDot3 = 0.5f * (_q0 * gy - _q1 * gz + _q3 * gx);
    qDot4 = 0.5f * (_q0 * gz + _q1 * gy - _q2 * gx);
    
    // Compute feedback only if accelerometer measurement valid (avoids NaN in accelerometer normalisation)
    if (!((ax == 0.0f) && (ay == 0.0f) && (az == 0.0f)))
    {
        // Normalise accelerometer measurement
        recipNorm = invSqrt(ax * ax + ay * ay + az * az);
        ax *= recipNorm;
        ay *= recipNorm;
        az *= recipNorm;
        
        // Normalise magnetometer measurement
        recipNorm = invSqrt(mx * mx + my * my + mz * mz);
        mx *= recipNorm;
        my *= recipNorm;
        mz *= recipNorm;
        
        // Auxiliary variables to avoid repeated arithmetic
        _2q0mx = 2.0f * _q0 * mx;
        _2q0my = 2.0f * _q0 * my;
        _2q0mz = 2.0f * _q0 * mz;
        _2q1mx = 2.0f * _q1 * mx;
        _2q0 = 2.0f * _q0;
        _2q1 = 2.0f * _q1;
        _2q2 = 2.0f * _q2;
        _2q3 = 2.0f * _q3;
        _2q0q2 = 2.0f * _q0 * _q2;
        _2q2q3 = 2.0f * _q2 * _q3;
        q0q0 = _q0 * _q0;
        q0q1 = _q0 * _q1;
        q0q2 = _q0 * _q2;
        q0q3 = _q0 * _q3;
        q1q1 = _q1 * _q1;
        q1q2 = _q1 * _q2;
        q1q3 = _q1 * _q3;
        q2q2 = _q2 * _q2;
        q2q3 = _q2 * _q3;
        q3q3 = _q3 * _q3;
        
        // Reference direction of Earth's magnetic field
        hx = mx * q0q0 - _2q0my * _q3 + _2q0mz * _q2 + mx * q1q1 + _2q1 * my * _q2 + _2q1 * mz * _q3 - mx * q2q2 - mx * q3q3;
        hy = _2q0mx * _q3 + my * q0q0 - _2q0mz * _q1 + _2q1mx * _q2 - my * q1q1 + my * q2q2 + _2q2 * mz * _q3 - my * q3q3;
        _2bx = sqrt(hx * hx + hy * hy);
        _2bz = -_2q0mx * _q2 + _2q0my * _q1 + mz * q0q0 + _2q1mx * _q3 - mz * q1q1 + _2q2 * my * _q3 - mz * q2q2 + mz * q3q3;
        _4bx = 2.0f * _2bx;
        _4bz = 2.0f * _2bz;
        
        // Gradient decent algorithm corrective step
        s0 = -_2q2 * (2.0f * q1q3 - _2q0q2 - ax) + _2q1 * (2.0f * q0q1 + _2q2q3 - ay) - _2bz * _q2 * (_2bx * (0.5f - q2q2 - q3q3) + _2bz * (q1q3 - q0q2) - mx) + (-_2bx * _q3 + _2bz * _q1) * (_2bx * (q1q2 - q0q3) + _2bz * (q0q1 + q2q3) - my) + _2bx * _q2 * (_2bx * (q0q2 + q1q3) + _2bz * (0.5f - q1q1 - q2q2) - mz);
        s1 = _2q3 * (2.0f * q1q3 - _2q0q2 - ax) + _2q0 * (2.0f * q0q1 + _2q2q3 - ay) - 4.0f * _q1 * (1 - 2.0f * q1q1 - 2.0f * q2q2 - az) + _2bz * _q3 * (_2bx * (0.5f - q2q2 - q3q3) + _2bz * (q1q3 - q0q2) - mx) + (_2bx * _q2 + _2bz * _q0) * (_2bx * (q1q2 - q0q3) + _2bz * (q0q1 + q2q3) - my) + (_2bx * _q3 - _4bz * _q1) * (_2bx * (q0q2 + q1q3) + _2bz * (0.5f - q1q1 - q2q2) - mz);
        s2 = -_2q0 * (2.0f * q1q3 - _2q0q2 - ax) + _2q3 * (2.0f * q0q1 + _2q2q3 - ay) - 4.0f * _q2 * (1 - 2.0f * q1q1 - 2.0f * q2q2 - az) + (-_4bx * _q2 - _2bz * _q0) * (_2bx * (0.5f - q2q2 - q3q3) + _2bz * (q1q3 - q0q2) - mx) + (_2bx * _q1 + _2bz * _q3) * (_2bx * (q1q2 - q0q3) + _2bz * (q0q1 + q2q3) - my) + (_2bx * _q0 - _4bz * _q2) * (_2bx * (q0q2 + q1q3) + _2bz * (0.5f - q1q1 - q2q2) - mz);
        s3 = _2q1 * (2.0f * q1q3 - _2q0q2 - ax) + _2q2 * (2.0f * q0q1 + _2q2q3 - ay) + (-_4bx * _q3 + _2bz * _q1) * (_2bx * (0.5f - q2q2 - q3q3) + _2bz * (q1q3 - q0q2) - mx) + (-_2bx * _q0 + _2bz * _q2) * (_2bx * (q1q2 - q0q3) + _2bz * (q0q1 + q2q3) - my) + _2bx * _q1 * (_2bx * (q0q2 + q1q3) + _2bz * (0.5f - q1q1 - q2q2) - mz);
        recipNorm = invSqrt(s0 * s0 + s1 * s1 + s2 * s2 + s3 * s3); // normalise step magnitude
        s0 *= recipNorm;
        s1 *= recipNorm;
        s2 *= recipNorm;
        s3 *= recipNorm;
        
//        NSLog(@"[%2.2f %2.2f %2.2f %2.2f]",s0, s1, s2, s3);

        
        // Apply feedback step
        qDot1 -= _beta * s0;
        qDot2 -= _beta * s1;
        qDot3 -= _beta * s2;
        qDot4 -= _beta * s3;
    }
    
    // Integrate rate of change of quaternion to yield quaternion
    _q0 += qDot1 * (1.0f / _sampleFrequencyHz);
    _q1 += qDot2 * (1.0f / _sampleFrequencyHz);
    _q2 += qDot3 * (1.0f / _sampleFrequencyHz);
    _q3 += qDot4 * (1.0f / _sampleFrequencyHz);
    
    // Normalise quaternion
    recipNorm = invSqrt(_q0 * _q0 + _q1 * _q1 + _q2 * _q2 + _q3 * _q3);
    _q0 *= recipNorm;
    _q1 *= recipNorm;
    _q2 *= recipNorm;
    _q3 *= recipNorm;
}


@end
