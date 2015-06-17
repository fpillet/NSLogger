//
//  PreferencesWindowController.swift
//  NSLoggerSW
//
//  Created by Guillaume Laurent on 15/06/15.
//  Copyright (c) 2015 Guillaume Laurent. All rights reserved.
//

import Cocoa

class PreferencesWindowController: NSWindowController, NSToolbarDelegate {

    override func windowDidLoad() {
        super.windowDidLoad()
    
        // Implement this method to handle any initialization after your window controller's window has been loaded from its nib file.
    }

    var allItemIdentifiers:[String]?

    func toolbarSelectableItemIdentifiers(toolbar: NSToolbar) -> [AnyObject] {

        if allItemIdentifiers == nil {
            let items = toolbar.items

            allItemIdentifiers = items.map( { (item:AnyObject) -> String in
                let i = item as! NSToolbarItem
                return i.itemIdentifier
                }
            )

        }

        return allItemIdentifiers!
    }


    @IBAction func test(sender: AnyObject) {
        NSLog("'general' item clicked")
    }

}
