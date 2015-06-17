//
//  ContainerViewController.swift
//  View Controller Transition Demo
//
//  Created by John Marstall on 3/20/15.
//  Copyright (c) 2015 John Marstall. All rights reserved.
//

import Cocoa

class ContainerViewController: NSViewController {
    
    override func viewDidLoad() {
        super.viewDidLoad()
        // Do view setup here.
        
        //self.view.wantsLayer = true
        let mainStoryboard: NSStoryboard = NSStoryboard(name: "Main", bundle: nil)!
        let sourceViewController = mainStoryboard.instantiateControllerWithIdentifier("GeneralPreferencesPanel") as! NSViewController
        self.insertChildViewController(sourceViewController, atIndex: 0)
        self.view.addSubview(sourceViewController.view)
        self.view.frame = sourceViewController.view.frame
        
        
    }
    
}
