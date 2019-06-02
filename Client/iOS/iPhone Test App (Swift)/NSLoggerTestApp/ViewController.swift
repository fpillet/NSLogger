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
		
		Logger.shared.log(.view, .info, "Button pressed.")
	}
	
	@IBAction func logSomeErrors(_ sender: Any) {
		
		Logger.shared.log(.network, .info, "Checking paper level…")
		Logger.shared.log(.network, .warning, "Paper level quite low.")
		Logger.shared.log(.network, .error, "Oups! No more paper. 💣")
	}
	
	@IBAction func logSomeImage(_ sender: Any) {
		
		guard let anImage = UIImage(named: "NSLoggerTestImage") else { return }
		Logger.shared.log(.view, .info, anImage)
	}
	
	@IBAction func logTheImage(_ sender: Any) {
		
		guard let anImage = UIImage(named: "Bohr_Einstein") else { return }
		
		let myDomain = Logger.Domain.custom("My Domain")
		Logger.shared.log(myDomain, .info, anImage)
		Logger.shared.log(myDomain, .info, "My custom log domain.")
		Logger.shared.log(myDomain, .debug, "Bohr developed the Bohr model of the atom, in which he proposed that energy levels of electrons are discrete and that the electrons revolve in stable orbits around the atomic nucleus but can jump from one energy level (or orbit) to another. Although the Bohr model has been supplanted by other models, its underlying principles remain valid. He conceived the principle of complementarity: that items could be separately analysed in terms of contradictory properties, like behaving as a wave or a stream of particles. The notion of complementarity dominated Bohr's thinking in both science and philosophy.\n\nBohr founded the Institute of Theoretical Physics at the University of Copenhagen, now known as the Niels Bohr Institute, which opened in 1920. Bohr mentored and collaborated with physicists including Hans Kramers, Oskar Klein, George de Hevesy, and Werner Heisenberg. He predicted the existence of a new zirconium-like element, which was named hafnium, after the Latin name for Copenhagen, where it was discovered. Later, the element bohrium was named after him.")
		Logger.shared.log(myDomain, .noise, "(Do you like Monads?)")
	}
	
	@IBAction func logBinaryData(_ sender: Any) {
		
		var randomized = [UInt8]()
		for _ in 0 ..< 200 {
			randomized.append(UInt8.random(in: 0 ... 255))
		}
		
		Logger.shared.log(.io, .verbose, Data(randomized))
	}
	
}

