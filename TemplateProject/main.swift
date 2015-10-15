#!/usr/bin/env diamond
//
//  main.swift
//  TemplateProject
//
//  Created by John Holdsworth on 18/09/2015.
//  Copyright © 2015 John Holdsworth. All rights reserved.
//

import Foundation
import SwiftRuby // clone RubyNative/SwiftRuby

print("Hello, \(Process.arguments)!")

//// uncomment this to turn this into a fully fledged Cocoa App

// import Cocoa
// if Process.arguments.count < 2 {
//     print( "Usage: ./browse <http://url..>" )
//     exit(0)
// }
// NSApplicationMain( 0,  UnsafeMutablePointer<UnsafeMutablePointer<CChar>>(nil) )
