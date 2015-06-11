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
    @IBOutlet weak var imageView: UIImageView!
    @IBOutlet weak var testImageView: UIImageView!

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

        if let image = imageView.image {

            let data = UIImagePNGRepresentation(image)

            SwiftLoggerClient.logImageData(domain: domain, level: 1, width:Int32(image.size.width), height:Int32(image.size.height), data: data)

            if let testImage = UIImage(data: data) {
                testImageView.image = testImage
            } else {
                NSLog("testImage nil")
            }

        } else {

            let alert = UIAlertView(title: "no image", message: "imageView is empty ?", delegate: nil, cancelButtonTitle: nil)
            alert.show()
            
        }

    }
}

