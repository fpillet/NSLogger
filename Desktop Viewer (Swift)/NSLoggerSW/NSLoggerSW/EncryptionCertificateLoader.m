//
//  EncryptionCertificateLoader.m
//  NSLoggerSW
//
//  Created by Guillaume Laurent on 29/04/15.
//  Copyright (c) 2015 Guillaume Laurent. All rights reserved.
//

#import "EncryptionCertificateLoader.h"

@implementation EncryptionCertificateLoader

- (BOOL)loadEncryptionCertificate:(NSError **)outError
{
    // Load the certificate we need to support encrypted incoming connections via SSL
    //
    // To this end, we will (once):
    // - generate a self-signed certificate and private key
    // - import the self-signed certificate and private key into the default keychain
    // - retrieve the certificate from the keychain
    // - create the required SecIdentityRef for the certificate to be recognized by the CFStream
    // - keep this in the running app and use for incoming connections

    if (outError != NULL)
        *outError = nil;

    _serverCertsLoadAttempted = YES;

    SecKeychainRef keychain;
    NSString *failurePoint = NSLocalizedString(@"Can't get the default keychain", @"");
    OSStatus status = SecKeychainCopyDefault(&keychain);
    for (int pass = 0; pass < 2 && status == noErr && self.serverCerts == NULL; pass++)
    {
        // Search through existing identities to find our NSLogger certificate
        SecIdentitySearchRef searchRef = NULL;
        failurePoint = NSLocalizedString(@"Can't search through default keychain", @"");
        status = SecIdentitySearchCreate(keychain, CSSM_KEYUSE_ANY, &searchRef);
        if (status == noErr)
        {
            SecIdentityRef identityRef = NULL;
            while (self.serverCerts == NULL && SecIdentitySearchCopyNext(searchRef, &identityRef) == noErr)
            {
                SecCertificateRef certRef = NULL;
                if (SecIdentityCopyCertificate(identityRef, &certRef) == noErr)
                {
                    CFStringRef commonName = NULL;
                    if (SecCertificateCopyCommonName(certRef, &commonName) == noErr)
                    {
                        if (commonName != NULL && CFStringCompare(commonName, CFSTR("NSLogger self-signed SSL"), 0) == kCFCompareEqualTo)
                        {
                            // We found our identity
                            CFTypeRef values[] = {
                                identityRef, certRef
                            };
                            _serverCerts = CFArrayCreate(NULL, values, 2, &kCFTypeArrayCallBacks);
                        }
                        if (commonName != NULL)
                        {
                            CFRelease(commonName);
                        }
                    }
                    CFRelease(certRef);
                }
                CFRelease(identityRef);
            }
            CFRelease(searchRef);
            status = noErr;
        }

        // Not found: create a cert, import it
        if (self.serverCerts == NULL && status == noErr && pass == 0)
        {
            // Path to our self-signed certificate
            NSString *tempDir = NSTemporaryDirectory();
            NSString *pemFileName = @"NSLoggerCert.pem";
            NSString *pemFilePath = [tempDir stringByAppendingPathComponent:pemFileName];
            NSFileManager *fm = [NSFileManager defaultManager];
            [fm removeItemAtPath:pemFilePath error:nil];

            // Generate a private certificate
            NSArray *args = [NSArray arrayWithObjects:
                             @"req",
                             @"-x509",
                             @"-nodes",
                             @"-days", @"3650",
                             @"-config", [[NSBundle mainBundle] pathForResource:@"NSLoggerCertReq" ofType:@"conf"],
                             @"-newkey", @"rsa:1024",
                             @"-keyout", pemFileName,
                             @"-out", pemFileName,
                             @"-batch",
                             nil];

            NSTask *certTask = [[NSTask alloc] init];
            [certTask setLaunchPath:@"/usr/bin/openssl"];
            [certTask setCurrentDirectoryPath:tempDir];
            [certTask setArguments:args];
            [certTask launch];
            do
            {
                [NSThread sleepUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.05]];
            }
            while([certTask isRunning]);

            // Load the NSLogger self-signed certificate
            NSData *certData = [NSData dataWithContentsOfFile:pemFilePath];
            if (certData == nil)
            {
                failurePoint = NSLocalizedString(@"Can't load self-signed certificate data", @"");
                status = -1;
            }
            else
            {
                // Import certificate and private key into our private keychain
                SecKeyImportExportParameters kp;
                bzero(&kp, sizeof(kp));
                kp.version = SEC_KEY_IMPORT_EXPORT_PARAMS_VERSION;
                SecExternalFormat inputFormat = kSecFormatPEMSequence;
                SecExternalItemType itemType = kSecItemTypeAggregate;
                failurePoint = NSLocalizedString(@"Failed importing self-signed certificate", @"");
                status = SecKeychainItemImport((__bridge CFDataRef)certData,
                                               (__bridge CFStringRef)pemFileName,
                                               &inputFormat,
                                               &itemType,
                                               0,				// flags are unused
                                               &kp,				// import-export parameters
                                               keychain,
                                               NULL);
            }
        }
    }
    
    if (keychain != NULL)
        CFRelease(keychain);
    
    if (self.serverCerts == NULL && outError != NULL)
    {
        if (status == noErr)
            failurePoint = NSLocalizedString(@"Failed retrieving our self-signed certificate", @"");
        
        NSString *errMsg = [NSString stringWithFormat:NSLocalizedString(@"Our private encryption certificate could not be loaded (%@, error code %d)", @""),
                            failurePoint, status];
        
        *outError = [NSError errorWithDomain:NSOSStatusErrorDomain
                                        code:status
                                    userInfo:[NSDictionary dictionaryWithObjectsAndKeys:
                                              NSLocalizedString(@"NSLogger won't be able to accept SSL connections", @""), NSLocalizedDescriptionKey,
                                              errMsg, NSLocalizedFailureReasonErrorKey,
                                              NSLocalizedString(@"Please contact the application developers", @""), NSLocalizedRecoverySuggestionErrorKey,
                                              nil]];
    }
    
    return (self.serverCerts != NULL);
}

@end
