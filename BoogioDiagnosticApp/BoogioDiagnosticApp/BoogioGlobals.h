//
//  BoogioGlobals.h
//  BoogioPeripheralNetworkManager
//
//  Created by Nate on 10/15/14.
//  Copyright (c) 2014 Reflx Labs. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <CoreBluetooth/CoreBluetooth.h>

typedef enum BOOGIO_PERIPHERAL_LOCATION : UInt8 {
    UNKNOWN_LOCATION = 0,
    LEFT_SHOE = 6,
    RIGHT_SHOE = 7,
} BOOGIO_PERIPHERAL_LOCATION;

typedef enum BOOGIO_DATA_TYPE : NSUInteger {
    BATTERY_LEVEL_TYPE = 0,      //READ
    BODY_SENSOR_LOCATION_TYPE,   //READ
    RSSI_TYPE,                   //READ
    FORCE_TYPE,                  //NOTIFY, READ
    ACCELERATION_TYPE,           //NOTIFY, READ
    ROTATION_TYPE,               //NOTIFY, READ
    DIRECTION_TYPE,              //NOTIFY, READ
    SYNCHRONIZATION_TYPE,        //NOTIFY, READ, WRITE
    AHRS_QUATERNION_TYPE         //VIRTUAL (Master only)
} BOOGIO_DATA_TYPE;

#define SAMPLE_RATE 30

#define MAX_FORCE_READING 10.0f
#define ACCELERATION_FROM_GRAVITY 9.80665f
#define MAX_ACCELERATION_READING (8.0f * ACCELERATION_FROM_GRAVITY)
#define MAX_ROTATION_READING 1000.0f
#define MAX_DIRECTION_READING 4800.0f
#define MAX_SHORT_VALUE 65535
#define HALF_OF_MAX_SHORT_VALUE 32767

#define DATA_INDEX_FORCE_TOE 0
#define DATA_INDEX_FORCE_BALL 1
#define DATA_INDEX_FORCE_ARCH 2
#define DATA_INDEX_FORCE_HEEL 3

#define DATA_INDEX_ACCELERATION_X 0
#define DATA_INDEX_ACCELERATION_Y 1
#define DATA_INDEX_ACCELERATION_Z 2

#define DATA_INDEX_ROTATION_X 0
#define DATA_INDEX_ROTATION_Y 1
#define DATA_INDEX_ROTATION_Z 2

#define DATA_INDEX_DIRECTION_X 0
#define DATA_INDEX_DIRECTION_Y 1
#define DATA_INDEX_DIRECTION_Z 2

#define DATA_INDEX_BATTERY_CHARGE 0
#define DATA_INDEX_RSSI 0

#define DATA_INDEX_AHRS_Q0 0
#define DATA_INDEX_AHRS_Q1 1
#define DATA_INDEX_AHRS_Q2 2
#define DATA_INDEX_AHRS_Q3 3

@interface BoogioGlobals : NSObject


extern NSString* const SENSOR_SERVICE_UUID;
    extern NSString* const FORCE_CHARACTERISTIC_UUID;
    extern NSString* const ACCELERATION_CHARACTERISTIC_UUID;
    extern NSString* const ROTATION_CHARACTERISTIC_UUID;
    extern NSString* const ORIENTATION_CHARACTERISTIC_UUID;
    extern NSString* const BODY_SENSOR_LOCATION_CHARACTERISTIC_UUID;

extern NSString* const SYNCHRONIZATION_SERVICE_UUID;
    extern NSString* const SYNCHRONIZATION_CHARACTERISTIC_UUID;

extern NSString* const BATTERY_SERVICE_UUID;
    extern NSString* const BATTERY_LEVEL_CHARACTERISTIC_UUID;

extern NSString* const DEVICE_INFORMATION_SERVICE_UUID;
    extern NSString* const MANUFACTURER_NAME_STRING_CHARACTERISTIC_UUID;


extern NSString* const LEFT_SHOE_UUID_KEY_STRING;
extern NSString* const RIGHT_SHOE_UUID_KEY_STRING;
extern NSString* const LEFT_SHOE_NAME_KEY_STRING;
extern NSString* const RIGHT_SHOE_NAME_KEY_STRING;
extern NSString* const SYNC_DIRECTORY_PATH_KEY_STRING;
extern NSString* const SENSITIVITY_BIAS_KEY_STRING;
extern NSString* const RECALIBRATION_FORCE_KEY_STRING;

+ (NSString*)getPersistentSettingsValueForKey:(NSString*)key;
+ (BOOL)setPersistentSettingsValue:(NSString*)value ForKey:(NSString*)key;


@end
