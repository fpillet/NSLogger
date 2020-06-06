// swift-tools-version:5.2

import PackageDescription

let package = Package(
	name: "NSLogger",
	products: [
		.library(name: "NSLogger", targets: ["NSLogger"])
	],
	dependencies: [
	],
	targets: [
		.target(
			name: "NSLogger",
			dependencies: ["NSLoggerLibObjC"],
			path: "Client/iOS",
			sources: ["NSLogger.swift"],
            swiftSettings: [SwiftSetting.define("SPMBuild")]
		),
		.target(
			name: "NSLoggerLibObjC",
			dependencies: [],
			path: "Client/iOS",
			sources: ["LoggerClient.m"],
            publicHeadersPath: "PublicHeaders",
            cSettings: [CSetting.unsafeFlags(["-fno-objc-arc"])]
		),
        .testTarget(
            name: "NSLoggerTests",
            dependencies: ["NSLogger"],
            path: "SPMTests"
        )
	],
	swiftLanguageVersions: [.v5]
)
