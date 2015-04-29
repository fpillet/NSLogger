//
//  EncryptionCertificateLoader.h
//  NSLoggerSW
//
//  Created by Guillaume Laurent on 29/04/15.
//  Copyright (c) 2015 Guillaume Laurent. All rights reserved.
//

#import <Foundation/Foundation.h>

@interface EncryptionCertificateLoader : NSObject

@property (nonatomic, readonly) CFArrayRef serverCerts;
@property (nonatomic, readonly) BOOL serverCertsLoadAttempted;

- (BOOL)loadEncryptionCertificate:(NSError **)outError;

@end
