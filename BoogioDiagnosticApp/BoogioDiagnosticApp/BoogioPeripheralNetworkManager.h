//
//  BoogioPeripheralNetworkManager.h
//  BoogioPeripheralNetworkManager
//
//  Created by Nate Shortsleeve on 9/19/14.
//  Copyright (c) 2014 Reflx Labs. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <CoreBluetooth/CoreBluetooth.h>
#import "BoogioGlobals.h"
#import "BoogioPeripheral.h"

@class BoogioPeripheralNetworkManager;






@protocol BoogioPeripheralNetworkManagerDelegate
//This protocol is intended to be implemented by ViewControllers in order to receive data
//only when that view controller is on top.
//When a view controller is about to appear (viewWillAppear:animated callback), it can
//set itself as the delegate and will effectively steal all updates from the other
//view controllers which have moved to the background anyway.
@optional
- (void)boogioPeripheralWasDiscovered:(BoogioPeripheral*)boogioPeripheral;
- (void)boogioPeripheralDidConnect:(BoogioPeripheral*)boogioPeripheral;
- (void)boogioPeripheralDidDisconnect:(BoogioPeripheral*)boogioPeripheral;
- (void)boogioPeripheral:(BoogioPeripheral*)boogioPeripheral
             DidSendData:(NSArray*)data
                  ofType:(BOOGIO_DATA_TYPE)sensorDataType;

@end


@interface BoogioPeripheralNetworkManager : NSObject <CBCentralManagerDelegate, BoogioPeripheralDelegate>

//Indexing Methods for Scanning UI
- (NSUInteger)getLeftShoeBoogioPeripheralsCount;
- (NSUInteger)getRightShoeBoogioPeripheralsCount;

- (BoogioPeripheral*)getLeftShoeBoogioPeripheralAtIndex:(NSUInteger)index;
- (BoogioPeripheral*)getRightShoeBoogioPeripheralAtIndex:(NSUInteger)index;

- (BOOL) isBoogioPeripheralConnectedAtLocation:(BOOGIO_PERIPHERAL_LOCATION)location;

//Pairing Methods
- (void) startScan;
- (void) stopScan;
- (NSString*) getPairedPeripheralUUID:(BOOGIO_PERIPHERAL_LOCATION)location;
- (BoogioPeripheral*) getPairedPeripheralAtLocation:(BOOGIO_PERIPHERAL_LOCATION)location;

- (void) pairWithPeripheralWith:(NSString*)uuidString atLocation:(BOOGIO_PERIPHERAL_LOCATION)location;

//Connection Methods
- (void) disconnectFromAllPeripherals;
- (void) connectToPairedPeripherals;



//Characteristics
- (void)readDataFromBoogioPeripheralAt:(BOOGIO_PERIPHERAL_LOCATION)location
                            ofDataType:(BOOGIO_DATA_TYPE)dataType;

///* For demo*/
//- (void)setBias:(float)bias;

//Streaming Data Routines
- (void)subscribeToBoogioPeripheralAt:(BOOGIO_PERIPHERAL_LOCATION)location
                forNotificationsAbout:(BOOGIO_DATA_TYPE)dataType;
- (void)unsubscribeFromBoogioPeripheralAt:(BOOGIO_PERIPHERAL_LOCATION)location
                forNotificationsAbout:(BOOGIO_DATA_TYPE)dataType;



//assigned to the top view controller typically in the (viewWillApear:animated) callback
@property (nonatomic, weak) id <BoogioPeripheralNetworkManagerDelegate> delegate;



@end
