//
//  AppDelegate.m
//  NSLogger Bluetooth iPhone Test (ARC)
//
//  Created by Almighty Kim on 4/21/13.
//  Copyright (c) 2013 Colorful Glue. All rights reserved.
//

#import "AppDelegate.h"
#import "LoggerClientViewController.h"

@implementation AppDelegate

- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions
{
    self.window = [[UIWindow alloc] initWithFrame:[[UIScreen mainScreen] bounds]];
    // Override point for customization after application launch.

	self.window.rootViewController = [[LoggerClientViewController alloc] initWithNibName:@"LoggerTestAppViewController" bundle:nil];
    [self.window makeKeyAndVisible];
    return YES;
}

- (void)applicationWillResignActive:(UIApplication *)application
{
}

- (void)applicationDidEnterBackground:(UIApplication *)application
{
}

- (void)applicationWillEnterForeground:(UIApplication *)application
{
}

- (void)applicationDidBecomeActive:(UIApplication *)application
{
}

- (void)applicationWillTerminate:(UIApplication *)application
{
}

@end
