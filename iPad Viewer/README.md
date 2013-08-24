#NSLogger iPad Viewer
NSLogger iPad Viewer aims to provide an in-field logging capacity to monitor your mobile application's behavior in unfabricated, real-world environments. NSLogger iPad Viewer makes use of Bluetooth connection to transmit an application's logging traces.

##Minimum Requirements
4.5 <= XCode   
5.1 <= iOS 
iPad 2 / iPad mini or higher  
<sup>*</sup>iCloud not supported.

##Status
A release version of 0.4 would be highly limited in terms of UI. Nontheless, its underlying logics are essentially the same as the current Desktop Viewer and you could capture logging traces with WiFi/Bluetooth connection.    
 
###iPad Viewer Screenshot (May 13, 2013)
<img width="576" src="https://raw.github.com/fpillet/NSLogger/master/Screenshots/ipad_viewer_13_05_11.png" />

## How to capture logging traces with Bluetooth
1. Checkout Bluetooth client branch.
2. Run NSLogger iPad Viewer with WiFi off and Bluetooth on from Setting.  
3. Run iOS client with Bluetooth on. (It's up to you to leave WiFi or cellular on).        
4. Start logging. Look at the Bluetooth mark on top right corner. :)  

##Work-In-Progress
CoreText now draws Timestamp, text message, binary messages. As CoreText is performing not as slowly as I suppose, I will expand its use cases.

##Issues
### Displaying logging message lags behind.

If you generate more than 110 logs/sec, you will see iPad Viewer starts laggin behind a client device's input. This is due to 1) CoreData processing log data slowly, and 2) it takes too much CPU cycle to convert raw image to CGImage and to get it on the screen.

Although no messages are missed, it renders iPad Viewer useless when one goes to highly pressured situation. Looking forward to replace CoreData with other backend such as plain SQLite3. Also, UIImage will be replaced with something else. 

Stay tuned.

##License
[Modified BSD license](https://github.com/fpillet/NSLogger/blob/master/iPad%20Viewer/LICENSE)   
_Version : 0.4.1_  
_Updated : Aug 25, 2013_