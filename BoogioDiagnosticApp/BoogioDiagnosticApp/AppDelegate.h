//
//  AppDelegate.h
//  BoogioDiagnosticApp
//
//  Created by Nate on 12/9/17.
//  Copyright © 2017 Intrinsic Automations. All rights reserved.
//

#import <UIKit/UIKit.h>
#import "BoogioPeripheralNetworkManager.h"

@interface AppDelegate : UIResponder <UIApplicationDelegate>

- (BoogioPeripheralNetworkManager *)getBoogioPeripheralNetworkReference;

@property (strong, nonatomic) UIWindow *window;


@end

