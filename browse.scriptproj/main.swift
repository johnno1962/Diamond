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
        webView.mainFrame.loadRequest(NSURLRequest(URL: NSURL(string: url)!))
        NSApplication.sharedApplication().activateIgnoringOtherApps( true )
    }

    func applicationWillTerminate(aNotification: NSNotification) {
        // Insert code here to tear down your application
        print( "bye.." )
    }

    func webView( aWebView: WebView, didReceiveTitle aTitle: String, forFrame frame: WebFrame ) {
        window.title = aTitle
    }

}
