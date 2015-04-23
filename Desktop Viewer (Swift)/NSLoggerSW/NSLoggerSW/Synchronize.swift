//
//  Synchronize.swift
//  NSLoggerSW
//
//  Created by Guillaume Laurent on 22/04/15.
//  Copyright (c) 2015 Guillaume Laurent. All rights reserved.
//

import Foundation

// taken from http://stackoverflow.com/questions/24045895/what-is-the-swift-equivalent-to-objective-cs-synchronized

func synced(lock: AnyObject, closure: () -> ()) {
    objc_sync_enter(lock)
    closure()
    objc_sync_exit(lock)
}
