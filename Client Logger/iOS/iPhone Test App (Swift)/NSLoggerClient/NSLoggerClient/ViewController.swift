//
//  ViewController.swift
//  NSLoggerClient
//
//  Created by Guillaume Laurent on 10/04/15.
//  Copyright (c) 2015 Guillaume Laurent. All rights reserved.
//

import UIKit

class ViewController: UIViewController {

    var messageCount = 0

    let domain = "NSLoggerClientSwift"

    @IBOutlet weak var textField: UITextField!

    override func viewDidLoad() {
        super.viewDidLoad()
        // Do any additional setup after loading the view, typically from a nib.
    }

    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        // Dispose of any resources that can be recreated.
    }


    @IBAction func logRawMessage(sender: AnyObject) {

        SwiftLoggerClient.logMessage("A raw message")

    }

    @IBAction func logFormattedMessage(sender: AnyObject) {
        SwiftLoggerClient.logMessage(domain:domain, level:1, format:"A formatted message : \(messageCount++) \(textField.text)")
        SwiftLoggerClient.logMessage(filename: __FILE__, lineNumber: __LINE__, functionName: __FUNCTION__,
            domain:domain, level:1, format:"A formatted message : \(messageCount++) \(textField.text)")
    }

    @IBAction func logData(sender: AnyObject) {

        var str:NSString = "foobar"

        var someBytes = str.cStringUsingEncoding(NSASCIIStringEncoding)

        var data = NSData(bytes: someBytes, length: CFStringGetLength(str))

        SwiftLoggerClient.logData(filename: __FILE__, lineNumber: __LINE__, functionName: __FUNCTION__, domain: domain, level: 1, data: data)
    }

    @IBAction func logImage(sender: AnyObject) {

        var layer = view.layer

        UIGraphicsBeginImageContext(view.bounds.size)
        CGContextClipToRect(UIGraphicsGetCurrentContext(), view.frame)
        layer.renderInContext(UIGraphicsGetCurrentContext())
        let image = UIGraphicsGetImageFromCurrentImageContext()

        if image != nil {
            let dataProvider = CGImageGetDataProvider(image.CGImage)
            let data = CGDataProviderCopyData(dataProvider) as NSData

            SwiftLoggerClient.logImageData(domain: domain, level: 1, width:Int32(image.size.width), height:Int32(image.size.height), data: data)
        } else {

            let alert = UIAlertView(title: "screenshot error", message: "couldn't take screenshot", delegate: nil, cancelButtonTitle: nil)
            alert.show()
            
        }

    }
}

