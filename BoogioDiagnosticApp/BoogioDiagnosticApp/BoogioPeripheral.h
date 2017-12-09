//
//  BoogioPeripheral.h
//  ConfigurationTool
//
//  Created by Nate on 12/15/14.
//  Copyright (c) 2014 Reflx Labs. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "BoogioGlobals.h"
#include <math.h>

typedef enum BOOGIO_CHARACTERISTIC_STATE : NSUInteger {
    SYNCHRONIZED = 0,
    NEEDS_READ,
    NEEDS_WRITE,
    NEEDS_UNSUBSCRIPTION,
    NEEDS_SUBSCRIPTION,
} BOOGIO_CHARACTERISTIC_STATE;



@class BoogioPeripheral;
@protocol BoogioPeripheralDelegate
@optional
- (void)boogioPeripheralDidConnect:(BoogioPeripheral*)peripheral;
- (void)boogioPeripheralDidDisconnect:(BoogioPeripheral*)peripheral;
- (void)boogioPeripheral:(BoogioPeripheral*)peripheral
             DidSendData:(NSArray*)data
                  ofType:(BOOGIO_DATA_TYPE)sensorDataType;
@end

@interface BoogioPeripheral : NSObject <CBPeripheralDelegate>




//Characteristic Values
@property NSDate* originTime;


//Internal State
@property CBPeripheralState intendedConnectionState;
@property CBPeripheral *cbPeripheralReference;
@property CBCentralManager *centralManager;

//External Interface
- (NSNumber*)getRSSI;
- (void)setRSSI:(NSNumber*)RSSI;

- (void)subscribeForNotificationsAbout:(BOOGIO_DATA_TYPE)dataType;
- (void)unsubscribeFromNotificationsAbout:(BOOGIO_DATA_TYPE)dataType;
- (CBCharacteristic *)getCharacteristic:(BOOGIO_DATA_TYPE)dataType;
- (BOOL)readDataFromBoogioPeripheral:(BOOGIO_DATA_TYPE)dataType;

- (double)getApproximateSynchronizationPercentageCompleted;
- (double)getCurrentSynchronizationNotificationBatchPercentageCompleted;


- (void)setAHRSSensitivity:(float)sensitivity;

- (BOOGIO_PERIPHERAL_LOCATION)getLocation;
- (void)setLocation:(BOOGIO_PERIPHERAL_LOCATION)location;

- (NSUInteger)getLastKnownBatteryLevel;

- (CBPeripheralState)getConnectionState;
- (NSString*)getUUIDString;
- (void)disconnect;
- (void)connect;

//Callback forwarding from the BoogioPeripheralNetwork into the respective peripherals so the
//peripheral objects themselves can handle connection recovery
- (void)centralManager:(CBCentralManager *)central didConnectPeripheral:(CBPeripheral *)peripheral;
- (void)centralManager:(CBCentralManager *)central didDisconnectPeripheral:(CBPeripheral *)peripheral
                 error:(NSError *)error;

@property NSUInteger secondsSpentWaitingForConnection;

@property (nonatomic, weak) id <BoogioPeripheralDelegate> delegate;

// Quaternion properties.
@property (nonatomic, readonly) float beta;
@property (nonatomic, readonly) float q0;
@property (nonatomic, readonly) float q1;
@property (nonatomic, readonly) float q2;
@property (nonatomic, readonly) float q3;

@end
