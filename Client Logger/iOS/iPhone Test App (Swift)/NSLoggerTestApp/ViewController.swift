//
//  ViewController.swift
//  NSLoggerTestApp
//
//  Created by Mathieu Godart on 10/03/2017.
//  Copyright © 2017 Lauve. All rights reserved.
//

import UIKit

class ViewController: UIViewController {

    @IBAction func logSomeText(_ sender: Any) {
        
        Log(.View, .Info, "Button pressed.")
    }

    @IBAction func logSomeErrors(_ sender: Any) {

        Log(.Network, .Info, "Checking paper level…")
        Log(.Network, .Warning, "Paper level quite low.")
        Log(.Network, .Error, "Oups! No more paper.")
    }

    @IBAction func logSomeImage(_ sender: Any) {

        guard let anImage = UIImage(named: "NSLoggerTestImage") else { return }
        LogImage(.View, .Info, anImage)
    }

    @IBAction func logTheImage(_ sender: Any) {

        guard let anImage = UIImage(named: "Bohr_Einstein") else { return }

        let myDomain = LoggerDomain.Custom("My Domain")
        LogImage(myDomain, .Info, anImage)
        Log(myDomain, .Debug, "My custom log domain (Bohr and Einstein).")
        Log(myDomain, .Noise, "(Can I say Monad?)")
    }

}

