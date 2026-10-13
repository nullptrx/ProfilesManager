//
//  PlistManager.m
//  ProfilesManager
//
//  Created by Jakey on 2018/3/5.
//  Copyright © 2018年 Jakey. All rights reserved.
//

#import "PlistManager.h"

@implementation PlistManager
+ (NSDictionary*)readPlist:(NSString *)filePath plistString:(NSString**)plistString
{
    if ([[NSFileManager defaultManager]fileExistsAtPath:filePath]) {
        NSString *startString = @"<?xml version";
        NSString *endString = @"</plist>";
        
        NSData *rawData = [NSData dataWithContentsOfFile:filePath];
        NSData *startData = [NSData dataWithBytes:[startString UTF8String] length:startString.length];
        NSData *endData = [NSData dataWithBytes:[endString UTF8String] length:endString.length];
        
        NSRange fullRange = {.location = 0, .length = [rawData length]};
        
        NSRange startRange = [rawData rangeOfData:startData options:0 range:fullRange];
        NSRange endRange = [rawData rangeOfData:endData options:0 range:fullRange];
        //不是有效的描述文件，直接返回，避免越界崩溃
        if (startRange.location == NSNotFound || endRange.location == NSNotFound || endRange.location < startRange.location) {
            return nil;
        }
        
        NSRange plistRange = {.location = startRange.location, .length = endRange.location + endRange.length - startRange.location};
        NSData *plistData = [rawData subdataWithRange:plistRange];
        
        if (plistString) {
            *plistString = [[NSString alloc] initWithData:plistData encoding:NSUTF8StringEncoding];
        }

        id obj = [NSPropertyListSerialization propertyListWithData:plistData options:NSPropertyListMutableContainers format:NULL error:nil];
        
        if ([obj isKindOfClass:[NSDictionary class]]) {
            return obj;
        }
    }
    return nil;
}

@end
