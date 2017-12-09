//
//  SettingsViewController.h
//  Boogio
//
//  Created by Nate on 11/27/15.
//  Copyright © 2015 REFLX Labs. All rights reserved.
//

#import <UIKit/UIKit.h>
#import "AppDelegate.h"

@interface SettingsViewController : UIViewController <BoogioPeripheralNetworkManagerDelegate, UITableViewDelegate, UITableViewDataSource>{
    
    BoogioPeripheralNetworkManager *peripheralNetwork;
    IBOutlet UITableView *leftPeripheralTableView;
    IBOutlet UITableView *rightPeripheralTableView;
    
}


@end

