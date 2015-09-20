#!/usr/bin/env safescript

import Cocoa

if Process.arguments.count < 2 {
    print( "Please specify URL" )
    exit(0)
}

// needs to be public when reloading
public let url = Process.arguments[1]

var a = 1

NSApplicationMain( 0,  UnsafeMutablePointer<UnsafeMutablePointer<Int8>>(nil) )
