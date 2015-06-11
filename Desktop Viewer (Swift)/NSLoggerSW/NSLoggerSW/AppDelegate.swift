//
//  AppDelegate.swift
//  NSLoggerSW
//
//  Created by Guillaume Laurent on 20/04/15.
//  Copyright (c) 2015 Guillaume Laurent. All rights reserved.
//

import Cocoa

@NSApplicationMain

class AppDelegate: NSObject, NSApplicationDelegate {

    var filterSets = [[String:AnyObject]]()
    var filterSortDescriptors = [NSSortDescriptor]()

    override init() {

        super.init()

        NSLog("AppDelegate init")

        let sortDescUID = NSSortDescriptor(key: "uid", ascending: true) { (uid1:AnyObject!, uid2:AnyObject!) -> NSComparisonResult in
            if let uid1I = uid1 as? NSNumber, uid2I = uid2 as? NSNumber {
                if uid1I.integerValue == 1 {
                    return NSComparisonResult.OrderedAscending
                }
                if uid2I.integerValue == 1 {
                    return NSComparisonResult.OrderedDescending
                }
            }
            return NSComparisonResult.OrderedSame
        }

        let sortDescTitle = NSSortDescriptor(key: "title", ascending: true)

        filterSortDescriptors.append(sortDescUID)
        filterSortDescriptors.append(sortDescTitle)


        // resurrect filters before the app nib loads
        let defaults = NSUserDefaults.standardUserDefaults()

        if let filterSetsData = defaults.objectForKey("filterSets") as? NSData {
            if let unarchivedFilterSets = NSKeyedUnarchiver.unarchiveObjectWithData(filterSetsData) as? [[String:AnyObject]] {
                filterSets = unarchivedFilterSets
            }
        }

        if filterSets.count == 0 {
            let filters = defaultFilters()
            let defaultSet:[String:AnyObject] = [
                "title" : NSLocalizedString("Default Set", comment: ""),
                "uid" : 1,
            "filters" : filters]
            filterSets.append(defaultSet)

        }


    }

    func applicationDidFinishLaunching(aNotification: NSNotification) {
        // Insert code here to initialize your application
    }

    func applicationWillTerminate(aNotification: NSNotification) {
        // Insert code here to tear down your application
    }


    func defaultFilters() -> [[String:AnyObject]] {

        var filters = [[String:AnyObject]]()

        filters.append(["uid" : 1,
            "title" : NSLocalizedString("All logs", comment: ""),
            "predicate" : NSPredicate(value: true)])

        let compoundPredicateTypeIsText = NSCompoundPredicate.andPredicateWithSubpredicates([NSPredicate(format: "(messageType == \"text\")", argumentArray: nil)])

        filters.append(["uid" : 2,
            "title" : NSLocalizedString("Text messages", comment: ""),
            "predicate" : compoundPredicateTypeIsText])

        let compoundPredicateTypeIsImg = NSCompoundPredicate.andPredicateWithSubpredicates([NSPredicate(format: "(messageType == \"img\")", argumentArray: nil)])

        filters.append(["uid" : 3,
            "title" : NSLocalizedString("Images", comment: ""),
            "predicate" : compoundPredicateTypeIsImg])

        let compoundPredicateTypeIsData = NSCompoundPredicate.andPredicateWithSubpredicates([NSPredicate(format: "(messageType == \"data\")", argumentArray: nil)])

        filters.append(["uid" : 3,
            "title" : NSLocalizedString("Data blocks", comment: ""),
            "predicate" : compoundPredicateTypeIsData])

        return filters
    }
}

