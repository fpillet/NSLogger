# NSLogger #

*NSLogger* is a high perfomance logging utility which displays traces emitted by client applications running on **Mac OS X** or **iOS (iPhone OS)**. It replaces your usual *NSLog()*-based traces and provides powerful additions like display filtering, image and binary logging, traces buffering, timing information, etc.

*NSLogger* feature summary:

  * View logs using the Mac OS X desktop viewer
  * Online (application running and connected to _NSLogger_) and offline (saved logs) log viewing
  * Buffer all traces in memory or in a file, send them over to viewer when a connection is acquired
  * View logs from client applications on the local network, or remotely over the internet
  * Save viewer logs to share them and/or review them later
  * Export logs to text files
  * Open raw buffered traces files that you brought back from client applications not directly connected to the log viewer

You'll find instructions for use in the [NSLogger wiki](http://github.com/fpillet/NSLogger/wiki/).

Your application emits traces using the *NSLogger* [trace APIs](http://github.com/fpillet/NSLogger/wiki/NSLogger-API). The desktop viewer application (running on **Mac OS X 10.6 or later**) displays them.

Clients automatically find the logger application running on Mac OS X via Bonjour networking. You have no setup to do: just start the logger on your Mac, launch your iOS or Mac OS X application then when your app emits traces, they will automatically show up in *NSLogger*.

![Desktop Viewer (main window)](http://github.com/fpillet/NSLogger/raw/master/Screenshots/mainwindow.png "Desktop Viewer")

# One-step setup #
All you have to do is add `LoggerClient.h`, `LoggerClient.m` and `LoggerCommon.h` (as well as add the `CFNetwork.framework` and `SystemConfiguration.framework` frameworks) to your iOS or Mac OS X application, then replace your *NSLog()* calls with *LogMessageCompat()* calls. We recommend using a macro, so you can turn off logs when building the distribution version of your application.

# Using the desktop logger #
Start the NSLogger application on Mac OS X. Your client app must run on a device that is on the same network as your Mac. When it starts logging traces, it will automatically look for the desktop NSLogger using Bonjour. As soon as traces start coming, a new window will open on your Mac.

You can create custom filters to quickly switch between different views of your logs.

# Evolved logging facility #
It's very easy to log binary data or images using *NSLogger*. Use the *LogData()* and *LogImage()* calls in your application, and you're done. Advanced users can also instantiate multiple loggers. For example, you could log your debug messages using macros that only log in DEBUG mode. And you can additionally instrument your application with a second logger that connects to a remote URL / IP address, and sends live traces over the network directly from a client device. It can be very effective to diagnose problems remotely on client devices.

# Powerful desktop viewer #
The desktop viewer application provides powerful tools, like:

 * Filters (with regular expression matching) that let your perform data mining in your traces
 * Timing information: each message displays the time elapsed since the previous message in the filtered display, so you can get a sense of time between events in your application.
 * Image and binary data display directly in the log window
 * Very fast navigation in your traces
 
 
Your traces can be saved to a `.nsloggerdata` file, and reloaded later.
Note that the NSLogger Mac OS X viewer requires **Mac OS X 10.6 or later**.

![Filter Editor](http://github.com/fpillet/NSLogger/raw/master/Screenshots/filtereditor.png "Filter Editor")

# High performance, low overhead #
*NSLogger* runs in its own thread in your application. It tries hard to consume as few CPU and memory as possible. If the desktop viewer has not been found yet, your traces can be buffered in memory until a connection is acquired. This allows for tracing in difficult situations, for example device wakeup times when the network connection is not up and running.

*NSLogger* can be used for low-level code in situations where only CoreFoundation can be called. Disable the **ALLOW_COCOA** flag in *LoggerClient.h* to prevent any use of Cocoa code.

# Work in progress - Current status #
This tool comes from a personal need for a more powerful logger. There are more features planned for inclusion, here is a quick list of what I'm thinking of. Requests and suggestions are welcome.

 * Per-client application filter sets (with auto-detect)
 * For multiple subsequent connections by the same client (multiple app runs), reuse the same window much like Instruments does
 * Log entry colorization
 * Search and search term highlight in Details window
 * Support time-based filtering (filter clause based on the time lapse between a previous trace)


You'll find documentation in the [NSLogger Wiki](http://github.com/fpillet/NSLogger/wiki/)

NSLogger uses [Brandon Walkin's BWToolkit](http://www.brandonwalkin.com/bwtoolkit/). The source tree for BWToolkit is currently included here because I suck at Git.
