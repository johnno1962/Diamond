#!/usr/bin/env diamond

//
//  main.swift
//  TemplateProject
//

import Foundation
import SwiftRuby // clone RubyNative/SwiftRuby

print("Hello, \(CommandLine.arguments)!")

//// Uncomment below to turn the script into a fully fledged Cocoa App

// import Cocoa
// if Process.arguments.count < 2 {
//     print( "Usage: ./browse <http://url..>" )
//     exit(0)
// }
// var dummy_argv = [UnsafeMutablePointer<CChar>?]()
// dummy_argv.withUnsafeMutableBufferPointer {
//     NSApplicationMain( 0,  $0.baseAddress! )
// }
