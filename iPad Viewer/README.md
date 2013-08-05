#NSLogger iPad Viewer
NSLogger iPad Viewer aims to provide an in-field logging capacity to monitor your mobile application's behavior in unfabricated, real-world environments. NSLogger iPad Viewer makes use of Bluetooth connection to transmit an application's logging traces.

## Work-In-Progress

Aug. 6, 2013 : CoreText draws Message text and data binary. Yet, do not stress test since CoreText Objs are instantiated in main thread at draw() call, which prevents iPad viewer from having a tight graphics loop.  
  
This is really bad. :(  


##Minimum Requirements
4.5 <= XCode   
5.1 <= iOS 
iPad 2 / iPad mini or higher  
<sup>*</sup>iCloud not supported.

##Status
A release version of 0.4 would be highly limited in terms of UI. Nontheless, its underlying logics are essentially the same as the current Desktop Viewer and you could capture logging traces with WiFi/Bluetooth connection.    

### Work-In-Progress
UI : Preference/Multi-Window/Search

## How to capture logging traces with Bluetooth
1. Checkout Bluetooth client branch.
2. Run NSLogger iPad Viewer with WiFi off and Bluetooth on from Setting.  
3. Run iOS client with Bluetooth on. (It's up to you to leave WiFi or cellular on).        
4. Start logging. Look at the Bluetooth mark on top right corner. :)  
 
###iPad Viewer Screenshot (May 13, 2013)
<img width="576" src="https://raw.github.com/fpillet/NSLogger/master/Screenshots/ipad_viewer_13_05_11.png" />

##License
[Modified BSD license](https://github.com/fpillet/NSLogger/blob/master/iPad%20Viewer/LICENSE)   
_Version : 0.4.1_  
_Updated : Aug 3, 2013_