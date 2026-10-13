//
//  ProfilesNode.h
//  ProfilesManager
//
//  Created by Jakey on 15/4/30.
//  Copyright (c) 2015年 Jakey. All rights reserved.
//

#import <Foundation/Foundation.h>

#define JKLocalizedString(key, comment) \
(([[[NSLocale preferredLanguages] objectAtIndex:0] hasPrefix:@"zh-Hans"])?([[NSBundle mainBundle] localizedStringForKey:(key) value:@"" table:nil]):([[NSBundle bundleWithPath:[[NSBundle mainBundle] pathForResource:@"en" ofType:@"lproj"]] localizedStringForKey:key value:@"" table:nil]))

#import "CertificateManager.h"

typedef NS_ENUM(NSInteger, ProfileStatus) {
    ProfileStatusNone = 0,
    ProfileStatusValid,
    ProfileStatusExpiringSoon,
    ProfileStatusOutdated,
    ProfileStatusExpired,
};

@interface ProfilesNode : NSObject

@property (nonatomic, weak)ProfilesNode *rootNode;
@property (nonatomic, strong)NSArray *childrenNodes;
@property (nonatomic, copy)NSString *key;
//@property (nonatomic, copy)NSString *name;
@property (nonatomic, copy)NSString *detail;
@property (nonatomic, copy)NSString *type;
@property (nonatomic, copy)NSString *uuid;
@property (nonatomic, copy)NSString *filePath;
@property (nonatomic, copy)NSString *baseDir;
@property (nonatomic, strong)NSDictionary *extra;
@property (nonatomic, strong)NSDate *expirationDate;
@property (nonatomic, strong)NSDate *creationDate;
 
@property (nonatomic, copy)NSString *days;

//描述文件摘要，只有描述文件节点才有值
@property (nonatomic, assign)ProfileStatus status;
@property (nonatomic, copy)NSString *profileType;
@property (nonatomic, copy)NSString *platform;
@property (nonatomic, copy)NSString *teamName;
@property (nonatomic, copy)NSString *teamIdentifier;
//-1 表示不限设备
@property (nonatomic, strong)NSNumber *deviceCount;
@property (nonatomic, copy)NSString *managed;
@property (nonatomic, copy)NSString *capabilities;
@property (nonatomic, assign)CertificateSigningStatus signingStatus;
@property (nonatomic, copy)NSString *signStatus;

+ (NSString *)profileTypeForInfo:(NSDictionary *)info;
- (id)initWithRootNode:(ProfilesNode *)rootNote originInfo:(id)info key:(NSString*)key;

@end
