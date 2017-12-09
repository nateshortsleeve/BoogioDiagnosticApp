//
//  BoogioGlobals.m
//  BoogioPeripheralNetworkManager
//
//  Created by Nate on 10/15/14.
//  Copyright (c) 2014 Reflx Labs. All rights reserved.
//

#import "BoogioGlobals.h"

@implementation BoogioGlobals

//Service and Characteristic UUIDs
NSString *const SENSOR_SERVICE_UUID                              = @"97290000-3B5A-4117-9834-A64CEA4AD41D";
    NSString *const FORCE_CHARACTERISTIC_UUID                    = @"97290001-3B5A-4117-9834-A64CEA4AD41D";
    NSString *const ACCELERATION_CHARACTERISTIC_UUID             = @"97290002-3B5A-4117-9834-A64CEA4AD41D";
    NSString *const ROTATION_CHARACTERISTIC_UUID                 = @"97290003-3B5A-4117-9834-A64CEA4AD41D";
    NSString *const ORIENTATION_CHARACTERISTIC_UUID              = @"97290004-3B5A-4117-9834-A64CEA4AD41D";
    NSString *const BODY_SENSOR_LOCATION_CHARACTERISTIC_UUID     = @"2A38";

NSString *const SYNCHRONIZATION_SERVICE_UUID                     = @"97290006-3B5A-4117-9834-A64CEA4AD41D";
    NSString *const SYNCHRONIZATION_CHARACTERISTIC_UUID          = @"97290007-3B5A-4117-9834-A64CEA4AD41D";


NSString *const BATTERY_SERVICE_UUID                             = @"180F";
    NSString *const BATTERY_LEVEL_CHARACTERISTIC_UUID            = @"2A19";

NSString *const DEVICE_INFORMATION_SERVICE_UUID                  = @"180A";
    NSString *const MANUFACTURER_NAME_STRING_CHARACTERISTIC_UUID = @"2A29";




//Settings Property List Keys
NSString * const LEFT_SHOE_UUID_KEY_STRING    = @"LeftShoeUUID";
NSString * const RIGHT_SHOE_UUID_KEY_STRING   = @"RightShoeUUID";
NSString * const LEFT_SHOE_NAME_KEY_STRING    = @"LeftShoeName";
NSString * const RIGHT_SHOE_NAME_KEY_STRING   = @"RightShoeName";
NSString * const SYNC_DIRECTORY_PATH_KEY_STRING = @"SyncDirectoryPath";
NSString * const SENSITIVITY_BIAS_KEY_STRING  = @"SensitivtyBias";
NSString * const RECALIBRATION_FORCE_KEY_STRING  = @"RecalibrationForce";

//-----------------------------------------------------------------------------------
//Persistent Settings Management
//-----------------------------------------------------------------------------------
//-----------------------------------------------------------------------------------

//TODO: Create the property list if one doesn't exist
//http://stackoverflow.com/questions/6697247/how-to-create-plist-files-programmatically-in-iphone
//https://developer.apple.com/library/mac/documentation/Cocoa/Conceptual/PropertyLists/CreatePropListProgram/CreatePropListProgram.html
+ (NSDictionary*)getSettingsDictionary {
    [self createSettingsFileIfItDoesntExist];
    
    
    NSError *error = nil;
    NSPropertyListFormat format;
    NSString *plistPath;
    NSString *rootPath = [NSSearchPathForDirectoriesInDomains(NSDocumentDirectory,
                                                              NSUserDomainMask, YES) objectAtIndex:0];
    plistPath = [rootPath stringByAppendingPathComponent:@"Settings.plist"];
    NSData *plistXML = [[NSFileManager defaultManager] contentsAtPath:plistPath];
    NSDictionary *settingsDictionary = (NSDictionary *)[NSPropertyListSerialization propertyListWithData:plistXML options:NSPropertyListMutableContainersAndLeaves format:&format error:&error];

    if (!settingsDictionary) {
        NSLog(@"Error reading plist: %@, format: %d", error.description, (int)format);
        return nil;
    }
    
    return settingsDictionary;
}
+ (NSString*)getPersistentSettingsValueForKey:(NSString*)key {
    NSDictionary *settingsDictionary = [self getSettingsDictionary];
    return [settingsDictionary valueForKey:key];
}

+ (BOOL)createSettingsFileIfItDoesntExist {
    NSString *rootPath = [NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES) objectAtIndex:0];
    NSString *plistPath = [rootPath stringByAppendingPathComponent:@"Settings.plist"];
    NSFileManager *fileManager = [NSFileManager defaultManager];
    if ([fileManager fileExistsAtPath: plistPath]) {
        return TRUE;
    }

    NSDictionary *plistDict = [[NSDictionary alloc]init];
    
    NSError *error = nil;
    // create NSData from dictionary
    NSData *plistData = [NSPropertyListSerialization dataWithPropertyList:plistDict format:NSPropertyListXMLFormat_v1_0 options:0 error:&error];
    // check is plistData exists
    if(plistData) {
        // write plistData to our Data.plist file
        BOOL success = [plistData writeToFile:plistPath atomically:YES];
        return success;
    }
    else {
        NSLog(@"Error in saveData: %@", error);
        return FALSE;
    }
    
    
}

+ (BOOL)setPersistentSettingsValue:(NSString*)value ForKey:(NSString*)key {
    NSString *rootPath = [NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES) objectAtIndex:0];
    NSString *plistPath = [rootPath stringByAppendingPathComponent:@"Settings.plist"];
    
    NSMutableDictionary *settingsDictionary = [[self getSettingsDictionary] mutableCopy];
    
    [settingsDictionary setValue:value forKey:key];
    
    NSDictionary *outputDictionary = [NSDictionary dictionaryWithDictionary:settingsDictionary];
    
    
    NSError *error = nil;
    // create NSData from dictionary
    NSData *plistData = [NSPropertyListSerialization dataWithPropertyList:outputDictionary format:NSPropertyListXMLFormat_v1_0 options:0 error:&error];
    
    // check is plistData exists
    if(plistData) {
        // write plistData to our Data.plist file
        BOOL success = [plistData writeToFile:plistPath atomically:YES];
        return success;
    }
    else {
        NSLog(@"Error in saveData: %@", error);
        return FALSE;
    }
    
}


@end
