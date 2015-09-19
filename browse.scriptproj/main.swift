#!/usr/bin/env swifts

import Cocoa
import WebKit

if Process.arguments.count < 2 {
    print( "Please specify URL" )
    exit(0)
}

let url = Process.arguments[1]

NSApplicationMain( 0,  UnsafeMutablePointer<UnsafeMutablePointer<Int8>>(nil) )

class AppDelegate: NSObject, NSApplicationDelegate {

    @IBOutlet weak var window: NSWindow!
    @IBOutlet weak var webView: WebView!

    func applicationDidFinishLaunching(aNotification: NSNotification) {
        // Insert code here to initialize your application
        NSApplication.sharedApplication().activateIgnoringOtherApps( true )
        webView.mainFrame.loadRequest(NSURLRequest(URL: NSURL(string: url)!))
    }

    func applicationWillTerminate(aNotification: NSNotification) {
        // Insert code here to tear down your application
    }
    
}
