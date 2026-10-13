//
//  CertificateManager.h
//  ProfilesManager
//
//  Created by Jakey on 2020/3/22.
//  Copyright © 2020 Jakey. All rights reserved.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, CertificateSigningStatus) {
    CertificateSigningStatusNoCertificate = 0,
    CertificateSigningStatusMissingPrivateKey,
    CertificateSigningStatusCertificateExpired,
    CertificateSigningStatusReady,
};

@interface CertificateManager : NSObject
+ (NSDictionary*)readCertificateInfo:(NSData *)certificateData;
//描述文件中任一证书在钥匙串中有私钥且未过期即可签名
+ (CertificateSigningStatus)signingStatusForCertificates:(NSArray *)certificates;
//钥匙串可能变化，刷新列表时清空缓存
+ (void)clearCache;
@end

NS_ASSUME_NONNULL_END
