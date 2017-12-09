//
//  AppDelegate.m
//  BoogioDiagnosticApp
//
//  Created by Nate on 12/9/17.
//  Copyright © 2017 Intrinsic Automations. All rights reserved.
//

#import "AppDelegate.h"

@interface AppDelegate (){
    BoogioPeripheralNetworkManager *peripheralNetwork;
}

@end

@implementation AppDelegate


- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions {
    
    //The AppDelegate will set up the initial association between the FirstViewController
    //instance. Afterwards, it's the responsibility of the top view controller to assign
    //itself as the delegate of the BoogioPeripheralNetwork when that view controller appears.
    peripheralNetwork = [[BoogioPeripheralNetworkManager alloc]init];
    
    
    // Override point for customization after application launch.
    return YES;
}


- (void)applicationWillResignActive:(UIApplication *)application {
    // Sent when the application is about to move from active to inactive state. This can occur for certain types of temporary interruptions (such as an incoming phone call or SMS message) or when the user quits the application and it begins the transition to the background state.
    // Use this method to pause ongoing tasks, disable timers, and invalidate graphics rendering callbacks. Games should use this method to pause the game.
    
    [peripheralNetwork disconnectFromAllPeripherals];
}


- (void)applicationDidEnterBackground:(UIApplication *)application {
    // Use this method to release shared resources, save user data, invalidate timers, and store enough application state information to restore your application to its current state in case it is terminated later.
    // If your application supports background execution, this method is called instead of applicationWillTerminate: when the user quits.
    
    [peripheralNetwork disconnectFromAllPeripherals];
}


- (void)applicationWillEnterForeground:(UIApplication *)application {
    // Called as part of the transition from the background to the active state; here you can undo many of the changes made on entering the background.
    
    [peripheralNetwork connectToPairedPeripherals];
}


- (void)applicationDidBecomeActive:(UIApplication *)application {
    // Restart any tasks that were paused (or not yet started) while the application was inactive. If the application was previously in the background, optionally refresh the user interface.
    
    [peripheralNetwork connectToPairedPeripherals];
}


- (void)applicationWillTerminate:(UIApplication *)application {
    // Called when the application is about to terminate. Save data if appropriate. See also applicationDidEnterBackground:.
    [peripheralNetwork disconnectFromAllPeripherals];
}

//-----------------------------------------------------------------------------------
//External Interface
//-----------------------------------------------------------------------------------
//-----------------------------------------------------------------------------------
- (BoogioPeripheralNetworkManager*)getBoogioPeripheralNetworkReference {
    //The AppDelegate will set up the initial association between the FirstViewController
    //instance. Afterwards, it's the responsibility of the top view controller to assign
    //itself as the delegate of the BoogioPeripheralNetwork when that view controller appears.
    return peripheralNetwork;
}

@end
