#!/usr/bin/env safescript

import Cocoa

if Process.argc < 2 {
    print( "Usage: \(Process.arguments[0]) <http://url..>" )
    exit(0)
}

// needs to be public when reloading
public let url = Process.arguments[1]

NSApplicationMain( 0,  UnsafeMutablePointer<UnsafeMutablePointer<CChar>>(nil) )
