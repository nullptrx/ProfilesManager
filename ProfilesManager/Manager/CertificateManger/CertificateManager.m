//
//  CertificateManager.m
//  ProfilesManager
//
//  Created by Jakey on 2020/3/22.
//  Copyright © 2020 Jakey. All rights reserved.
//

#import "CertificateManager.h"
#import <CommonCrypto/CommonDigest.h>

@implementation CertificateManager
static NSMutableDictionary<NSData *, NSNumber *> *_identityCache;

+ (NSDictionary*)readCertificateInfo:(NSData *)certificateData{
    static NSString *const devCertSummaryKey = @"summary";
    static NSString *const devCertExpirationDateKey = @"expirationDate";

    NSMutableDictionary *detailsDict = [NSMutableDictionary dictionary];
    SecCertificateRef certificateRef = SecCertificateCreateWithData(NULL, (__bridge CFDataRef)certificateData);
    
    
    if (!certificateRef) {
        return detailsDict;
    }
    CFStringRef summaryRef = SecCertificateCopySubjectSummary(certificateRef);
    NSString *summary = (NSString *)CFBridgingRelease(summaryRef);
    if (summary) {
        [detailsDict setObject:summary forKey:devCertSummaryKey];
    }
    
    NSDate *expirationDate = [self expirationDateForCertificate:certificateRef];
    if (expirationDate) {
        [detailsDict setObject:expirationDate forKey:devCertExpirationDateKey];
    }
    
    CFRelease(certificateRef);
    [detailsDict setObject: [self sha1:certificateData] forKey:@"sha1"];
    [detailsDict setObject: [self sha256:certificateData] forKey:@"sha256"];
    return detailsDict;
}

//证书真正的到期时间是 X509 NotAfter，InvalidityDate 是 CRL 扩展，开发者证书里没有
+ (nullable NSDate *)expirationDateForCertificate:(SecCertificateRef)certificateRef {
    CFDictionaryRef valuesDict = SecCertificateCopyValues(certificateRef, (__bridge CFArrayRef)@[(__bridge id)kSecOIDX509V1ValidityNotAfter], NULL);
    if (!valuesDict) {
        return nil;
    }
    NSDictionary *values = CFBridgingRelease(valuesDict);
    id value = values[(__bridge id)kSecOIDX509V1ValidityNotAfter][(__bridge id)kSecPropertyKeyValue];
    if ([value isKindOfClass:[NSDate class]]) {
        return value;
    }
    if ([value isKindOfClass:[NSNumber class]]) {
        return [NSDate dateWithTimeIntervalSinceReferenceDate:[value doubleValue]];
    }
    return nil;
}

+ (CertificateSigningStatus)signingStatusForCertificates:(NSArray *)certificates {
    if (!_identityCache) {
        _identityCache = [NSMutableDictionary dictionary];
    }
    CertificateSigningStatus status = CertificateSigningStatusNoCertificate;
    for (NSData *certificateData in certificates) {
        if (![certificateData isKindOfClass:[NSData class]]) {
            continue;
        }
        SecCertificateRef certificateRef = SecCertificateCreateWithData(NULL, (__bridge CFDataRef)certificateData);
        if (!certificateRef) {
            continue;
        }
        //钥匙串里有对应私钥才能签名，查询较慢，按证书缓存
        NSNumber *hasIdentity = _identityCache[certificateData];
        if (!hasIdentity) {
            SecIdentityRef identityRef = NULL;
            hasIdentity = @(SecIdentityCreateWithCertificate(NULL, certificateRef, &identityRef) == errSecSuccess);
            if (identityRef) {
                CFRelease(identityRef);
            }
            _identityCache[certificateData] = hasIdentity;
        }
        NSDate *expirationDate = [self expirationDateForCertificate:certificateRef];
        CFRelease(certificateRef);
        
        if (![hasIdentity boolValue]) {
            if (status == CertificateSigningStatusNoCertificate) {
                status = CertificateSigningStatusMissingPrivateKey;
            }
        } else if (expirationDate && [expirationDate compare:[NSDate date]] == NSOrderedAscending) {
            status = CertificateSigningStatusCertificateExpired;
        } else {
            return CertificateSigningStatusReady;
        }
    }
    return status;
}

+ (void)clearCache {
    [_identityCache removeAllObjects];
}

+ (NSMutableArray*)readCertificateAllInfo:(NSData *)certificateData{
    const void *keys[] = {kSecOIDX509V1SubjectName};
    
    //    const void *keys[] = {kSecOIDADC_CERT_POLICY,
    //          kSecOIDAPPLE_CERT_POLICY,
    //          kSecOIDAPPLE_EKU_CODE_SIGNING,
    //          kSecOIDAPPLE_EKU_CODE_SIGNING_DEV,
    //          kSecOIDAPPLE_EKU_ICHAT_ENCRYPTION,
    //          kSecOIDAPPLE_EKU_ICHAT_SIGNING,
    //          kSecOIDAPPLE_EKU_RESOURCE_SIGNING,
    //          kSecOIDAPPLE_EKU_SYSTEM_IDENTITY,
    //          kSecOIDAPPLE_EXTENSION,
    //          kSecOIDAPPLE_EXTENSION_ADC_APPLE_SIGNING,
    //          kSecOIDAPPLE_EXTENSION_ADC_DEV_SIGNING,
    //          kSecOIDAPPLE_EXTENSION_APPLE_SIGNING,
    //          kSecOIDAPPLE_EXTENSION_CODE_SIGNING,
    //          kSecOIDAPPLE_EXTENSION_INTERMEDIATE_MARKER,
    //          kSecOIDAPPLE_EXTENSION_WWDR_INTERMEDIATE,
    //          kSecOIDAPPLE_EXTENSION_ITMS_INTERMEDIATE,
    //          kSecOIDAPPLE_EXTENSION_AAI_INTERMEDIATE,
    //          kSecOIDAPPLE_EXTENSION_APPLEID_INTERMEDIATE,
    //          kSecOIDAuthorityInfoAccess,
    //          kSecOIDAuthorityKeyIdentifier,
    //          kSecOIDBasicConstraints,
    //          kSecOIDBiometricInfo,
    //          kSecOIDCSSMKeyStruct,
    //          kSecOIDCertIssuer,
    //          kSecOIDCertificatePolicies,
    //          kSecOIDClientAuth,
    //          kSecOIDCollectiveStateProvinceName,
    //          kSecOIDCollectiveStreetAddress,
    //          kSecOIDCommonName,
    //          kSecOIDCountryName,
    //          kSecOIDCrlDistributionPoints,
    //          kSecOIDCrlNumber,
    //          kSecOIDCrlReason,
    //          kSecOIDDOTMAC_CERT_EMAIL_ENCRYPT,
    //          kSecOIDDOTMAC_CERT_EMAIL_SIGN,
    //          kSecOIDDOTMAC_CERT_EXTENSION,
    //          kSecOIDDOTMAC_CERT_IDENTITY,
    //          kSecOIDDOTMAC_CERT_POLICY,
    //          kSecOIDDeltaCrlIndicator,
    //          kSecOIDDescription,
    //          kSecOIDEKU_IPSec,
    //          kSecOIDEmailAddress,
    //          kSecOIDEmailProtection,
    //          kSecOIDExtendedKeyUsage,
    //          kSecOIDExtendedKeyUsageAny,
    //          kSecOIDExtendedUseCodeSigning,
    //          kSecOIDGivenName,
    //          kSecOIDHoldInstructionCode,
    //          kSecOIDInvalidityDate,
    //          kSecOIDIssuerAltName,
    //          kSecOIDIssuingDistributionPoint,
    //          kSecOIDIssuingDistributionPoints,
    //          kSecOIDKERBv5_PKINIT_KP_CLIENT_AUTH,
    //          kSecOIDKERBv5_PKINIT_KP_KDC,
    //          kSecOIDKeyUsage,
    //          kSecOIDLocalityName,
    //          kSecOIDMS_NTPrincipalName,
    //          kSecOIDMicrosoftSGC,
    //          kSecOIDNameConstraints,
    //          kSecOIDNetscapeCertSequence,
    //          kSecOIDNetscapeCertType,
    //          kSecOIDNetscapeSGC,
    //          kSecOIDOCSPSigning,
    //          kSecOIDOrganizationName,
    //          kSecOIDOrganizationalUnitName,
    //          kSecOIDPolicyConstraints,
    //          kSecOIDPolicyMappings,
    //          kSecOIDPrivateKeyUsagePeriod,
    //          kSecOIDQC_Statements,
    //          kSecOIDSerialNumber,
    //          kSecOIDServerAuth,
    //          kSecOIDStateProvinceName,
    //          kSecOIDStreetAddress,
    //          kSecOIDSubjectAltName,
    //          kSecOIDSubjectDirectoryAttributes,
    //          kSecOIDSubjectEmailAddress,
    //          kSecOIDSubjectInfoAccess,
    //          kSecOIDSubjectKeyIdentifier,
    //          kSecOIDSubjectPicture,
    //          kSecOIDSubjectSignatureBitmap,
    //          kSecOIDSurname,
    //          kSecOIDTimeStamping,
    //          kSecOIDTitle,
    //          kSecOIDUseExemptions,
    //          kSecOIDX509V1CertificateIssuerUniqueId,
    //          kSecOIDX509V1CertificateSubjectUniqueId,
    //          kSecOIDX509V1IssuerName,
    //          kSecOIDX509V1IssuerNameCStruct,
    //          kSecOIDX509V1IssuerNameLDAP,
    //          kSecOIDX509V1IssuerNameStd,
    //          kSecOIDX509V1SerialNumber,
    //          kSecOIDX509V1Signature,
    //          kSecOIDX509V1SignatureAlgorithm,
    //          kSecOIDX509V1SignatureAlgorithmParameters,
    //          kSecOIDX509V1SignatureAlgorithmTBS,
    //          kSecOIDX509V1SignatureCStruct,
    //          kSecOIDX509V1SignatureStruct,
    //          kSecOIDX509V1SubjectName,
    //          kSecOIDX509V1SubjectNameCStruct,
    //          kSecOIDX509V1SubjectNameLDAP,
    //          kSecOIDX509V1SubjectNameStd,
    //          kSecOIDX509V1SubjectPublicKey,
    //          kSecOIDX509V1SubjectPublicKeyAlgorithm,
    //          kSecOIDX509V1SubjectPublicKeyAlgorithmParameters,
    //          kSecOIDX509V1SubjectPublicKeyCStruct,
    //          kSecOIDX509V1ValidityNotAfter,
    //          kSecOIDX509V1ValidityNotBefore,
    //          kSecOIDX509V1Version,
    //          kSecOIDX509V3Certificate,
    //          kSecOIDX509V3CertificateCStruct,
    //          kSecOIDX509V3CertificateExtensionCStruct,
    //          kSecOIDX509V3CertificateExtensionCritical,
    //          kSecOIDX509V3CertificateExtensionId,
    //          kSecOIDX509V3CertificateExtensionStruct,
    //          kSecOIDX509V3CertificateExtensionType,
    //          kSecOIDX509V3CertificateExtensionValue,
    //          kSecOIDX509V3CertificateExtensionsCStruct,
    //          kSecOIDX509V3CertificateExtensionsStruct,
    //          kSecOIDX509V3CertificateNumberOfExtensions,
    //          kSecOIDX509V3SignedCertificate,
    //          kSecOIDX509V3SignedCertificateCStruct,
    //          kSecOIDSRVName
    //      };
    CFArrayRef keysArray = CFArrayCreate(NULL, keys , sizeof(keys)/sizeof(keys[0]), &kCFTypeArrayCallBacks);
    
    SecCertificateRef certificateRef = SecCertificateCreateWithData(NULL, (__bridge CFDataRef)certificateData);
    
    
    CFErrorRef error;
    CFDictionaryRef valuesDict = SecCertificateCopyValues(certificateRef, keysArray, &error);
    NSMutableArray* items = [NSMutableArray new];
    
    for(int i = 0; i < sizeof(keys)/sizeof(keys[0]); i++) {
        CFDictionaryRef dict = CFDictionaryGetValue(valuesDict, keys[i]);
        if(dict!=NULL){
            [items addObject:(__bridge NSDictionary*) dict];
        }
    }
    CFRelease(valuesDict);
    return items;
    
}
//https://stackoverflow.com/questions/7869278/get-ssl-certificate-details
+ (NSString*)sha1:(NSData*)certData {
    unsigned char sha1Buffer[CC_SHA1_DIGEST_LENGTH];
    CC_SHA1(certData.bytes, (CC_LONG)certData.length, sha1Buffer);
    NSMutableString *fingerprint = [NSMutableString stringWithCapacity:CC_SHA1_DIGEST_LENGTH * 3];
    for (int i = 0; i < CC_SHA1_DIGEST_LENGTH; ++i)
        [fingerprint appendFormat:@"%02x ",sha1Buffer[i]];
    return [[fingerprint stringByReplacingOccurrencesOfString:@" " withString:@""] uppercaseString];
}
+ (NSString*)sha256:(NSData*)certData {
    unsigned char sha256Buffer[CC_SHA256_DIGEST_LENGTH];
    CC_SHA256(certData.bytes, (CC_LONG)certData.length, sha256Buffer);
    NSMutableString *fingerprint = [NSMutableString stringWithCapacity:CC_SHA256_DIGEST_LENGTH * 3];
    for (int i = 0; i < CC_SHA256_DIGEST_LENGTH; ++i)
        [fingerprint appendFormat:@"%02x ",sha256Buffer[i]];
    return [[fingerprint stringByReplacingOccurrencesOfString:@" " withString:@""] uppercaseString];
}

@end
