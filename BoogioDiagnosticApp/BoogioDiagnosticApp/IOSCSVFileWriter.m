//
//  IOSCSVFileWriter.m
//  BoogioDiagnosticApp
//
//  Created by Nate on 3/19/16.
//  Copyright © 2016 Reflx Labs. All rights reserved.
//

#import "IOSCSVFileWriter.h"
#import "BoogioPeripheral.h"

@implementation IOSCSVFileWriter {
    

    NSMutableArray *readingsQueue;
    
}
- (id)init {
    self = [super init];
    if (self) {
        readingsQueue        = [[NSMutableArray alloc]init];
        
    }
    return self;
}
#define MAX_SENSOR_READINGS_COUNT       4500
#define CSV_FILE_NAME                   @"boogio_readings.csv"
- (void)appendLine:(NSString*)line {
    [readingsQueue addObject:line];
    if([readingsQueue count] >= MAX_SENSOR_READINGS_COUNT) {
        [readingsQueue removeObjectAtIndex:0];
    }

    
}
-(void)eraseAllRecordingQueuesContents {
    [readingsQueue removeAllObjects];
}
-(void)initializeSensorReadingsFiles {
    
    [self eraseAllRecordingQueuesContents];
    
    
    NSString *documentsDirectory = [self getDocumentsDirectoryPath];
    
    //make a file name to write the data to using the documents directory:
    NSString *readingsFilePath          = [NSString stringWithFormat:@"%@/%@", documentsDirectory, CSV_FILE_NAME];
    
    NSString *header = @"TimeStamp yyyy/MM/dd HH:mm:ss.SSS, Left Toe, Left Ball, Left Arch, Left Heel, Left Acceleration X, Left Acceleration Y, Left Acceleration Z, Left Rotation X, Left Rotaiton Y, Left Rotation Z, Left Direction X, Left Direction Y, Left Direction Z, Right Toe, Right Ball, Right Arch, Right Heel, Right Acceleration X, Right Acceleration Y, Right Acceleration Z, Right Rotation X, Right Rotaiton Y, Right Rotation Z, Right Direction X, Right Direction Y, Right Direction Z\n";
    
    //save content to the documents directory
    [header writeToFile:readingsFilePath
             atomically:NO
               encoding:NSStringEncodingConversionExternalRepresentation
                  error:nil];
    
}

-(void)writeString:(NSString*)content toEndOfFile:(NSString *)filePath {
    
    //make a file name to write the data to using the documents directory:
    
    if([[NSFileManager defaultManager] fileExistsAtPath:filePath])
    {
        NSFileHandle *fileHandle = [NSFileHandle fileHandleForWritingAtPath:filePath];
        [fileHandle seekToEndOfFile];
        NSString *writedStr = [[NSString alloc]initWithContentsOfFile:filePath encoding:NSUTF8StringEncoding error:nil];
        content = [content stringByAppendingString:@""];
        writedStr = [writedStr stringByAppendingString:content];
        
        [writedStr writeToFile:filePath
                    atomically:NO
                      encoding:NSStringEncodingConversionExternalRepresentation
                         error:nil];
    }
    else {
        NSLog(@"could not write to file: %@", filePath);
    }
    
}
-(void)writeOutQueuesToFiles {
    NSString *documentsDirectory = [self getDocumentsDirectoryPath];
    
    NSString *readingsFilePath          = [NSString stringWithFormat:@"%@/%@", documentsDirectory, CSV_FILE_NAME];
    
    NSString *filePath;
    NSMutableArray *queue;
    
    queue = readingsQueue;
    filePath = readingsFilePath;
    for(NSString *dataLine in queue) {
        [self writeString:dataLine toEndOfFile:filePath];
    }
    
    
    [self eraseAllRecordingQueuesContents];
    
}
-(NSString*)getDocumentsDirectoryPath {
    //get the documents directory:
    NSArray *paths = NSSearchPathForDirectoriesInDomains
    (NSDocumentDirectory, NSUserDomainMask, YES);
    return [paths objectAtIndex:0];;
}
- (NSString*)getCSVFileName {
    return CSV_FILE_NAME;
}
@end
