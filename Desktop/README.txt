This is the macOS logs viewer source code (NSLogger)

BUILDING NSLogger (Code signing your build)
-----------------

Since NSLogger generates a self-signed certificate for SSL connections, you'll want to codesign
your build to avoid an issue with SSL connections failing the first time NSLogger is launched.

If you are a member of the iOS Developer Program or Mac Developer Program, you already have
such an identity.  If you need to create an identity for the sole purpose of signing your
builds, you can read Apple's Code Signing guide:

http://developer.apple.com/library/mac/#documentation/Security/Conceptual/CodeSigningGuide/Procedures/Procedures.html%23//apple_ref/doc/uid/TP40005929-CH4-SW1

You are not _required_ to codesign your build. If you don't, the first time you launch NSLogger
and the firewall is activated, incoming SSL connections will fail. You'll need to restart the
application once to get the authorization dialog allowing you to use the SSL certificate.
