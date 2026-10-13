//
//  ProfilesNode.m
//  ProfilesManager
//
//  Created by Jakey on 15/4/30.
//  Copyright (c) 2015年 Jakey. All rights reserved.
//

#import "ProfilesNode.h"
#import "NSData+JKBase64.h"
#import "DateManager.h"
#import <CommonCrypto/CommonDigest.h>
#import "CertificateManager.h"
@implementation ProfilesNode

- (id)initWithRootNode:(ProfilesNode *)rootNode originInfo:(id)info key:(NSString*)key
{
    self = [super init];
    if (self) {
        _rootNode = rootNode;
        _key = key;
        if([info isKindOfClass:[NSDictionary class]] && [info objectForKey:@"AppIDName"]){
            NSMutableDictionary *dict = [info mutableCopy];
            [dict setObject:[ProfilesNode platformForInfo:info] forKey:@"ProfilePlatform"];
            [dict setObject:[ProfilesNode profileTypeForInfo:info] forKey:@"ProfileType"];
            info = [dict copy];
            
        }
        if ([info isKindOfClass:[NSDictionary class]]) {
            _type = @"Dictionary";
            
            
            NSMutableArray *children = [NSMutableArray array];
            NSDictionary *dict = info;
            _detail = [NSString stringWithFormat:@"%lu items", (unsigned long)[dict count]];
            _uuid = [dict objectForKey:@"UUID"];
            _filePath = [dict objectForKey:@"filePath"];
            _baseDir = [dict objectForKey:@"baseDir"];

            if(_uuid){
                _type  =  [dict objectForKey:@"Name"];
                [self readProfileSummary:dict];
            }
            if(rootNode){
                //root
                
                _expirationDate = [dict objectForKey:@"ExpirationDate"];
                _creationDate= [dict objectForKey:@"CreationDate"];
                NSInteger days = [self getDaysFrom:[NSDate date] endDate:_expirationDate];
                _days = [@(days) stringValue];
                for (NSString *key in dict) {
                    ProfilesNode *child = [[ProfilesNode alloc]initWithRootNode:self originInfo:dict[key] key:key];
                    [children addObject:child];
                }
                
            }else{
                NSArray *keys = [dict allKeys];
                NSString *bundleID = [[dict  objectForKey:@"Entitlements"] objectForKey:@"application-identifier"];
                for (int i=0;i<[keys count];i++) {
                    NSString *key = [keys objectAtIndex:i];
                    NSString *realKey = key;

                    if([key hasSuffix:@"mobileprovision"]){
                        bundleID =  [[[dict objectForKey:key] objectForKey:@"Entitlements"] objectForKey:@"application-identifier"];
                        realKey = bundleID;
                    }else{
                        realKey = key;
                    }
                    
                    ProfilesNode *child = [[ProfilesNode alloc]initWithRootNode:self originInfo:dict[key] key:realKey];
                    [children addObject:child];
                }
                [children sortUsingComparator:^NSComparisonResult(ProfilesNode *obj1, ProfilesNode *obj2) {
                    return [obj2.expirationDate compare:obj1.expirationDate];
                }];
            }
            
            _childrenNodes = [NSArray arrayWithArray:children];
        }
        else if([info isKindOfClass:[NSArray class]]) {
            _type = @"Array";
            
            NSMutableArray *children = [NSMutableArray array];
            NSArray *array = info;
            _detail = [NSString stringWithFormat:@"%lu items", (unsigned long)[array count]];
            
            for (int i=0; i<[array count]; i++) {
                ProfilesNode *child = [[ProfilesNode alloc]initWithRootNode:self originInfo:array[i] key:[NSString stringWithFormat:@"%d", i]];
                [children addObject:child];
            }
            _childrenNodes = [NSArray arrayWithArray:children];
        }
        else {
            _detail = [NSString stringWithFormat:@"%@", info];
            
            if ([info isKindOfClass:[NSString class]]) {
                _type = @"String";
            }
            else if([info isKindOfClass:[NSDate class]]){
                _type = @"Date";
                _detail = [[DateManager sharedManager] stringConvert_YMDHM_FromDate:info];
            }
            else if([info isKindOfClass:[NSNumber class]]) {
                _type = @"Number";
            }
            else {
                _type = @"Data";
                _detail = [info jk_base64EncodedString];
                if ([self.rootNode.key isEqualToString:@"DeveloperCertificates"]) {
                    NSDictionary *cerInfo =  [CertificateManager readCertificateInfo:info];
                    _extra = cerInfo;
                    _key  = [NSString stringWithFormat:@"%@",[cerInfo objectForKey:@"summary"]];
                    _type = @".cer";
                    
                    ProfilesNode *child = [[ProfilesNode alloc]initWithRootNode:self originInfo:_extra key:_key];
                    _childrenNodes = child.childrenNodes;
                }
            }
        }
        
        if (!rootNode && !key) {
            _key = @"Root";
        }
    }
    
    return self;
}
#pragma mark - profile summary
- (void)readProfileSummary:(NSDictionary *)dict {
    _profileType = [[ProfilesNode profileTypeForInfo:dict] stringByReplacingOccurrencesOfString:@"Distribution (" withString:@""];
    _profileType = [_profileType stringByReplacingOccurrencesOfString:@")" withString:@""];
    _platform = [ProfilesNode platformForInfo:dict];
    NSArray *teamIdentifiers = [dict objectForKey:@"TeamIdentifier"];
    _teamIdentifier = [teamIdentifiers isKindOfClass:[NSArray class]] ? [teamIdentifiers firstObject] : nil;
    NSString *teamName = [dict objectForKey:@"TeamName"];
    _teamName = _teamIdentifier ? [NSString stringWithFormat:@"%@ (%@)", teamName ?: @"", _teamIdentifier] : teamName;
    
    NSArray *devices = [dict objectForKey:@"ProvisionedDevices"];
    if ([[dict objectForKey:@"ProvisionsAllDevices"] boolValue]) {
        _deviceCount = @(-1);
    } else {
        _deviceCount = @([devices isKindOfClass:[NSArray class]] ? devices.count : 0);
    }
    
    _managed = [[dict objectForKey:@"IsXcodeManaged"] boolValue] ? @"Xcode" : JKLocalizedString(@"Manual", nil);
    _capabilities = [ProfilesNode capabilitiesForEntitlements:[dict objectForKey:@"Entitlements"]];
    
    _signingStatus = [CertificateManager signingStatusForCertificates:[dict objectForKey:@"DeveloperCertificates"]];
    switch (_signingStatus) {
        case CertificateSigningStatusReady:
            _signStatus = JKLocalizedString(@"Ready", nil);
            break;
        case CertificateSigningStatusCertificateExpired:
            _signStatus = JKLocalizedString(@"Certificate Expired", nil);
            break;
        case CertificateSigningStatusMissingPrivateKey:
            _signStatus = JKLocalizedString(@"No Private Key", nil);
            break;
        default:
            _signStatus = JKLocalizedString(@"No Certificate", nil);
            break;
    }
    
    NSDate *expiration = [dict objectForKey:@"ExpirationDate"];
    if ([[NSDate date] compare:expiration] == NSOrderedDescending) {
        self.status = ProfileStatusExpired;
    } else if ([self getDaysFrom:[NSDate date] endDate:expiration] <= 30) {
        self.status = ProfileStatusExpiringSoon;
    } else {
        self.status = ProfileStatusValid;
    }
}

- (void)setStatus:(ProfileStatus)status {
    _status = status;
    switch (status) {
        case ProfileStatusExpired:
            _detail = JKLocalizedString(@"Expired", nil);
            break;
        case ProfileStatusExpiringSoon:
            _detail = JKLocalizedString(@"Expiring Soon", nil);
            break;
        case ProfileStatusOutdated:
            _detail = JKLocalizedString(@"Outdated", nil);
            break;
        case ProfileStatusValid:
            _detail = JKLocalizedString(@"Valid", nil);
            break;
        default:
            break;
    }
}

// determine the profile type
// https://github.com/chockenberry/Provisioning
+ (NSString *)profileTypeForInfo:(NSDictionary *)info {
    BOOL getTaskAllow = NO;
    NSDictionary *entitlements = [info objectForKey:@"Entitlements"];
    if ([entitlements isKindOfClass:[NSDictionary class]]) {
        getTaskAllow = [[entitlements valueForKey:@"get-task-allow"] boolValue];
    }
    BOOL hasDevices = [[info objectForKey:@"ProvisionedDevices"] isKindOfClass:[NSArray class]];
    BOOL provisionsAllDevices = [[info objectForKey:@"ProvisionsAllDevices"] boolValue];
    
    if ([self isMacProfile:info]) {
        if (hasDevices) {
            return @"Development";
        }
        //Mac 上不限设备的是 Developer ID
        return provisionsAllDevices ? @"Developer ID" : @"Distribution (App Store)";
    }
    if (hasDevices) {
        return getTaskAllow ? @"Development" : @"Distribution (Ad Hoc)";
    }
    return provisionsAllDevices ? @"Enterprise" : @"Distribution (App Store)";
}

+ (BOOL)isMacProfile:(NSDictionary *)info {
    NSArray *platforms = [info objectForKey:@"Platform"];
    if ([platforms isKindOfClass:[NSArray class]] && platforms.count > 0) {
        return [platforms containsObject:@"OSX"];
    }
    return [[[[info objectForKey:@"filePath"] description] pathExtension] isEqualToString:@"provisionprofile"];
}

+ (NSString *)platformForInfo:(NSDictionary *)info {
    NSArray *platforms = [info objectForKey:@"Platform"];
    if (![platforms isKindOfClass:[NSArray class]] || platforms.count == 0) {
        return [self isMacProfile:info] ? @"macOS" : @"iOS";
    }
    NSDictionary *names = @{@"OSX": @"macOS", @"xrOS": @"visionOS"};
    NSMutableArray *result = [NSMutableArray array];
    for (NSString *platform in platforms) {
        NSString *name = names[platform] ?: [platform description];
        if (![result containsObject:name]) {
            [result addObject:name];
        }
    }
    return [result componentsJoinedByString:@", "];
}

+ (NSString *)capabilitiesForEntitlements:(NSDictionary *)entitlements {
    if (![entitlements isKindOfClass:[NSDictionary class]]) {
        return @"";
    }
    //每个应用都有的基础字段不算能力
    NSSet *ignored = [NSSet setWithArray:@[@"application-identifier", @"com.apple.application-identifier", @"com.apple.developer.team-identifier", @"keychain-access-groups", @"get-task-allow", @"com.apple.security.get-task-allow", @"beta-reports-active"]];
    NSDictionary *names = @{@"com.apple.security.application-groups": @"App Groups",
                            @"com.apple.developer.associated-domains": @"Associated Domains",
                            @"com.apple.developer.applesignin": @"Sign in with Apple",
                            @"com.apple.developer.in-app-payments": @"Apple Pay",
                            @"com.apple.developer.game-center": @"Game Center",
                            @"com.apple.developer.siri": @"Siri",
                            @"com.apple.developer.nfc.readersession.formats": @"NFC",
                            @"com.apple.developer.networking.wifi-info": @"WiFi Info",
                            @"com.apple.developer.default-data-protection": @"Data Protection",
                            @"com.apple.developer.usernotifications.time-sensitive": @"Time Sensitive Notifications",
                            @"inter-app-audio": @"Inter-App Audio"};
    NSMutableArray *result = [NSMutableArray array];
    for (NSString *key in [[entitlements allKeys] sortedArrayUsingSelector:@selector(compare:)]) {
        if ([ignored containsObject:key]) {
            continue;
        }
        NSString *name = names[key];
        if (!name) {
            if ([key isEqualToString:@"aps-environment"] || [key isEqualToString:@"com.apple.developer.aps-environment"]) {
                name = [NSString stringWithFormat:@"Push (%@)", entitlements[key]];
            } else if ([key hasPrefix:@"com.apple.developer.healthkit"]) {
                name = @"HealthKit";
            } else if ([key hasPrefix:@"com.apple.developer.icloud"] || [key hasPrefix:@"com.apple.developer.ubiquity"]) {
                name = @"iCloud";
            } else if ([key hasPrefix:@"com.apple.developer.kernel."]) {
                name = @"Increased Memory";
            } else {
                name = [[key stringByReplacingOccurrencesOfString:@"com.apple.developer." withString:@""] stringByReplacingOccurrencesOfString:@"com.apple.security." withString:@""];
            }
        }
        if (![result containsObject:name]) {
            [result addObject:name];
        }
    }
    return [result componentsJoinedByString:@", "];
}

//https://stackoverflow.com/questions/7869278/get-ssl-certificate-details
- (NSString*)sha1:(NSData*)certData {
    unsigned char sha1Buffer[CC_SHA1_DIGEST_LENGTH];
    CC_SHA1(certData.bytes, (CC_LONG)certData.length, sha1Buffer);
    NSMutableString *fingerprint = [NSMutableString stringWithCapacity:CC_SHA1_DIGEST_LENGTH * 3];
    for (int i = 0; i < CC_SHA1_DIGEST_LENGTH; ++i)
        [fingerprint appendFormat:@"%02x ",sha1Buffer[i]];
    return [[fingerprint stringByReplacingOccurrencesOfString:@" " withString:@""] uppercaseString];
}
- (NSString*)sha256:(NSData*)certData {
    unsigned char sha256Buffer[CC_SHA256_DIGEST_LENGTH];
    CC_SHA256(certData.bytes, (CC_LONG)certData.length, sha256Buffer);
    NSMutableString *fingerprint = [NSMutableString stringWithCapacity:CC_SHA256_DIGEST_LENGTH * 3];
    for (int i = 0; i < CC_SHA256_DIGEST_LENGTH; ++i)
        [fingerprint appendFormat:@"%02x ",sha256Buffer[i]];
    return [[fingerprint stringByReplacingOccurrencesOfString:@" " withString:@""] uppercaseString];
}
 
- (NSInteger)getDaysFrom:(NSDate *)date endDate:(NSDate *)endDate
{
    if(!date || !endDate){
        return 0;
    }
    NSCalendar *gregorian = [[NSCalendar alloc]
    initWithCalendarIdentifier:NSCalendarIdentifierGregorian];
    [gregorian setFirstWeekday:2];
    NSDate *fromDate;
    NSDate *toDate;
    [gregorian rangeOfUnit:NSCalendarUnitDay startDate:&fromDate interval:NULL forDate:date];
    [gregorian rangeOfUnit:NSCalendarUnitDay startDate:&toDate interval:NULL forDate:endDate];
    NSDateComponents *dayComponents = [gregorian components:NSCalendarUnitDay fromDate:fromDate toDate:toDate options:0];
    if(dayComponents.day<0){
        return 0;
    }
    return dayComponents.day;
}

@end

