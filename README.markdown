# NSLogger #
*NSLogger* is a high perfomance logging utility which displays traces emitted by client applications. It replaces your usual *NSLog()*-based traces and provides powerful additions like display filtering, image and binary logging, traces buffering, timing information, etc.

Clients automatically find the logger application running on Mac OS X via Bonjour networking. You have no setup to do: just start the logger on your Mac, launch your iOS or Mac OS X application then when your app emits traces, they will automatically show up in *NSLogger*.

# One-step setup #
All you have to do is add `LoggerClient.h`, `LoggerClient.m` and `LoggerCommon.h` to your iOS or Mac OS X application, then replace your *NSLog()* calls with *LogMessageCompat()* calls. We recommend using a macro, so you can turn off logs when building the distribution version of your application.

# Evolved logging facility #
It's very easy to log binary data or images using *NSLogger*. Use the *LogData()* and *LogImage()* calls in your application, and you're done. Advanced users can also instantiate multiple loggers. For example, you could log your debug messages using macros that only log in DEBUG mode. And you can additionally instrument your application with a second logger that connects to a remote URL / IP address, and sends live traces over the network directly from a client device. It can be very effective to diagnose problems remotely on client devices. (*this feature is currently in development*).

# Powerful desktop viewer #
The desktop viewer application provides powerful tools, like:
- Filters (with regular expression matching) that let your perform data mining in your traces
- Timing information: each message displays the time elapsed since the previous message in the filtered display, so you can get a sense of time between events in your application.
- Image and binary data display directly in the log window
- Very fast navigation in your traces

# High performance, low overhead #
*NSLogger* runs in its own thread in your application. It tries hard to consume as few CPU and memory as possible. If the desktop viewer has not been found yet, your traces can be buffered in memory until a connection is acquired. This allows for tracing in difficult situations, for example device wakeup times when the network connection is not up and running.

*NSLogger* can be used for low-level code in situations where only CoreFoundation can be called. Disable the **ALLOW_COCOA** flag in *LoggerClient.h* to prevent any use of Cocoa code.
