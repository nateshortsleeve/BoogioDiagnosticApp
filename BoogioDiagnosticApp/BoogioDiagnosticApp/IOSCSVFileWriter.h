//
//  IOSCSVFileWriter.h
//  BoogioDiagnosticApp
//
//  Created by Nate on 3/19/16.
//  Copyright © 2016 Reflx Labs. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "BoogioGlobals.h"

@interface IOSCSVFileWriter : NSObject

- (void)appendLine:(NSString*)line;
- (void)eraseAllRecordingQueuesContents;
- (void)initializeSensorReadingsFiles;
- (NSString*)getCSVFileName;
- (NSString*)getDocumentsDirectoryPath;
- (void)writeOutQueuesToFiles;
@end
