//
//  SettingsViewController.m
//  Boogio
//
//  Created by Nate on 11/27/15.
//  Copyright © 2015 REFLX Labs. All rights reserved.
//

#import "SettingsViewController.h"
#import "BoogioGlobals.h"

@interface SettingsViewController ()



@end

@implementation SettingsViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    
    [leftPeripheralTableView setDelegate:self];
    [leftPeripheralTableView setDataSource:self];

    [rightPeripheralTableView setDelegate:self];
    [rightPeripheralTableView setDataSource:self];

    
    AppDelegate *appDelegate = (AppDelegate*)[[UIApplication sharedApplication]delegate];
    peripheralNetwork = [appDelegate getBoogioPeripheralNetworkReference];
    
    

}
- (void)viewWillAppear:(BOOL)animated {

    [super viewWillAppear:animated];
    [peripheralNetwork setDelegate:self];
    [self.navigationController.navigationBar setTranslucent:NO];
    
    [peripheralNetwork disconnectFromAllPeripherals];
    
    [peripheralNetwork stopScan];
    [peripheralNetwork startScan];
    
    [self.navigationController.navigationBar setHidden:FALSE];

}
- (void)viewWillDisappear:(BOOL)animated{
    [super viewWillDisappear:animated];
    [peripheralNetwork stopScan];
    
}
- (void)didReceiveMemoryWarning {
    [super didReceiveMemoryWarning];
}
//-----------------------------------------------------------------------------------
//BoogioPeripheralNetworkManager Callbacks & Scanning Methods
//-----------------------------------------------------------------------------------
//-----------------------------------------------------------------------------------
- (void)boogioPeripheralWasDiscovered:(BoogioPeripheral*)boogioPeripheral {
    switch ([boogioPeripheral getLocation]) {
        case LEFT_SHOE:
            [leftPeripheralTableView reloadData];
            break;
        case RIGHT_SHOE:
            [rightPeripheralTableView reloadData];
            break;
            
        default:
            break;
    }

}
- (void)boogioPeripheral:(BoogioPeripheral*)boogioPeripheral
             DidSendData:(NSArray*)data
                  ofType:(BOOGIO_DATA_TYPE)sensorDataType {
    
    switch ([boogioPeripheral getLocation]) {
        case LEFT_SHOE:
            switch (sensorDataType) {
                case RSSI_TYPE:
                    //TODO: sort left tableview by signal strength
                    break;
                default:
                    break;
            }
            
            break;
        case RIGHT_SHOE:
            switch (sensorDataType) {
                case RSSI_TYPE:
                    //TODO: sort right tableview by signal strength
                    break;
                default:
                    break;
            }
            
            break;
        default:
            break;
    }
}
//-----------------------------------------------------------------------------------
//Scanning UITableView Delegate Callbacks (peripheralTableView)
//-----------------------------------------------------------------------------------
//-----------------------------------------------------------------------------------
- (NSInteger)tableView:(UITableView *)tableView
 numberOfRowsInSection:(NSInteger)section {
    if([tableView isEqual:leftPeripheralTableView]) {
        return [peripheralNetwork getLeftShoeBoogioPeripheralsCount];
    }
    else if([tableView isEqual:rightPeripheralTableView]) {
        return [peripheralNetwork getRightShoeBoogioPeripheralsCount];
    }
    else {
        NSLog(@"PROBLEM IN TABLE VIEW MANAGEMENT.");
    }
    return 1;
}
- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return 1;     // Return the number of sections.
}
- (UITableViewCell *)tableView:(UITableView *)tableView
         cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    static NSString *CellIdentifier = @"Cell";
    UITableViewCell *cell;
    BoogioPeripheral *boogioPeripheral;
    
    if([tableView isEqual:leftPeripheralTableView]) {
        cell = [leftPeripheralTableView dequeueReusableCellWithIdentifier:CellIdentifier];
        boogioPeripheral = [peripheralNetwork getLeftShoeBoogioPeripheralAtIndex:indexPath.row];
    }
    else if([tableView isEqual:rightPeripheralTableView]) {
        cell = [rightPeripheralTableView dequeueReusableCellWithIdentifier:CellIdentifier];
        boogioPeripheral = [peripheralNetwork getRightShoeBoogioPeripheralAtIndex:indexPath.row];
    }
    else {
        NSLog(@"PROBLEM IN TABLE VIEW MANAGEMENT.");
        return cell;
    }

    
    if (cell == nil) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:CellIdentifier];
        [cell setBackgroundColor:[UIColor colorWithRed: 98.0f/255.0f green:104.0f/255.0f blue:113.0f/255.0f alpha:1.0]];
        
    }

    NSString *uuidSubString = [[boogioPeripheral getUUIDString] substringFromIndex:32];
    NSString *titleText;
    switch ([boogioPeripheral getLocation]) {
        case LEFT_SHOE:
            titleText = [NSString stringWithFormat:@"Boogio %@", uuidSubString];
            break;
        case RIGHT_SHOE:
            titleText = [NSString stringWithFormat:@"Boogio %@", uuidSubString];
            break;
            
        default:
            break;
    }

    cell.textLabel.text = titleText;
    [cell.textLabel setTextColor:[UIColor whiteColor]];
    NSString *fontFamily = @"HelveticaNeue-Thin";
    NSString *boldFontFamily = @"HelveticaNeue-Bold";
    float fontSize = 18.0;
    [cell.textLabel setFont:[UIFont fontWithName:fontFamily size: fontSize]];
    
    UIView *selectionColor = [[UIView alloc] init];
    int gamma = 140;
    selectionColor.backgroundColor = [UIColor colorWithRed:(gamma/255.0) green:(gamma/255.0) blue:(gamma/255.0) alpha:1];
    cell.selectedBackgroundView = selectionColor;
    
    
    if(   [[boogioPeripheral getUUIDString] isEqualToString:[BoogioGlobals getPersistentSettingsValueForKey:LEFT_SHOE_UUID_KEY_STRING]]
       || [[boogioPeripheral getUUIDString] isEqualToString:[BoogioGlobals getPersistentSettingsValueForKey:RIGHT_SHOE_UUID_KEY_STRING]]) {
        [cell.textLabel setFont:[UIFont fontWithName:boldFontFamily size: fontSize]];
        [tableView selectRowAtIndexPath:indexPath animated:NO scrollPosition:UITableViewScrollPositionNone];
    }

    return cell;
}
- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {

    if([tableView isEqual:leftPeripheralTableView]) {
        BoogioPeripheral *boogioPeripheral = [peripheralNetwork getLeftShoeBoogioPeripheralAtIndex:indexPath.row];
        NSString *uuid = [boogioPeripheral getUUIDString];
        NSString *name = [NSString stringWithFormat:@"Boogio %@", [uuid substringFromIndex:32]];
        [peripheralNetwork pairWithPeripheralWith:uuid atLocation:LEFT_SHOE];
        [BoogioGlobals setPersistentSettingsValue:name ForKey:LEFT_SHOE_NAME_KEY_STRING];
    }
    else if([tableView isEqual:rightPeripheralTableView]) {
        BoogioPeripheral *boogioPeripheral = [peripheralNetwork getRightShoeBoogioPeripheralAtIndex:indexPath.row];
        NSString *uuid = [boogioPeripheral getUUIDString];
        NSString *name = [NSString stringWithFormat:@"Boogio %@", [uuid substringFromIndex:32]];
        [peripheralNetwork pairWithPeripheralWith:uuid atLocation:RIGHT_SHOE];
        [BoogioGlobals setPersistentSettingsValue:name ForKey:RIGHT_SHOE_NAME_KEY_STRING];
    }
    else {
        NSLog(@"PAIRING PROBLEM. UNKNOWN TABLEVIEW EVENT.");
        return;
    }
    NSString *boldFontFamily = @"HelveticaNeue-Bold";
    float fontSize = 18.0;
    UITableViewCell *cell = [tableView cellForRowAtIndexPath:indexPath];
    [cell.textLabel setFont:[UIFont fontWithName:boldFontFamily size: fontSize]];
    
    
}


@end
