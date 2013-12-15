## NSLogger Legacy Bluetooth Client (iOS 5 &amp; 6) ##

<sup>*</sup> Compatible with ver 1.5-RC2 22-NOV-2013

### Bluetooth Connections in iOS
There are three Bluetooth frameworks and one API publicly opened in iOS 5 &amp; 6  
1. [CoreBluetooth](http://developer.apple.com/library/ios/#documentation/CoreBluetooth/Reference/CoreBluetooth_Framework/_index.html)  
2. [External Accessary](http://developer.apple.com/library/ios/#documentation/ExternalAccessory/Reference/ExternalAccessoryFrameworkReference/_index.ht]ml)  
3. [GameKit](http://developer.apple.com/library/ios/#documentation/GameKit/Reference/GameKit_Collection/_index.html)  
4. [Bonjour over Bluetooth (DNS-SD)](http://developer.apple.com/library/ios/#qa/qa1753/_index.html#//apple_ref/doc/uid/DTS40011315)  

The one that is most clutter-free and provides best possible use case is, so far in my opinion, the last one. It requires no additional framework, library, and does not ask user to choose bluetooth connection. It simply finds the nearest possible service on Bluetooth interface and makes use of it.  

### How to run demo
1. Run iPad Viewer with WiFi off and Bluetooth on from system setting.  
2. Run iOS client with Bluetooth on. (It's up to you to leave WiFi or cellular on).      
3. Start logging. Look at the Bluetooth mark on top right corner. :)  

### iPhone Client Screenshot (Apr. 27, 2013)
<img width="320" src="https://raw.github.com/fpillet/NSLogger/master/Screenshots/iphone_bluetooth_13_04_27.png" />

NSLogger is Copyright (c) 2010-2013 Florent Pillet, All Rights Reserved, All Wrongs Revenged. Released under the [New BSD Licence](http://www.opensource.org/licenses/bsd-license.php).
The NSLogger icon is Copyright (c) [Louis Harboe](http://www.graphicpeel.com)
