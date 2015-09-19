
# SwiftScript

Of late I've been looking for a new scripting language when it comes to larger projects.
The nub of the problem is dynamically typed languages will always be prone to
run time errors that really should have been picked up when the script compiles.
If only you could write scripts in a type-safe, modern language like Swift. 

From the get-go you've been [able to](http://nomothetis.svbtle.com/swift-for-scripting)
but it leaves much unresolved such as dependency management and auto-completion in the
editor. The SwiftScript project is a binary `swifts` and a ruby script that seeks to
resolve these problems in particular dependency managment galvanised by a talk by 
[Ayaka Nonaka](https://realm.io/news/swift-scripting/) earlier this year.

To script in SwiftScript, download and build this project and start by placing the
following into a file in your path and making it executable:

```Swift
    #!/usr/bin/env swifts

    import Cocoa
    import AlamoFire // pod 'AlamoFire'

    print( "Hello SwiftScript" )
```

Execute the file with a `-edit` argument and
this should convert the script into a `.scriptproj` Xcode project in the same directory
and open it in Xcode so you can start creating. Your script will appear in the project as
`main.swift` and will also be available at it's original location via a
symbolic link to continue to callable from the command line.

This script shows how to use a Cocoapods dependency. By putting it's pod spec
in a comment after the import statement the pod will be automatically
downloaded when the script is run and installed
into ~/Library/SwiftScripts/Frameworks. As this directory is in the
framework search path for all script projects auto-completion in the
Xcode Editor will work. Use `!pod` to force a pod to reinstall at a later time.

You must have $HOME/bin in your UNIX $PATH for /usr/bin/env to work and for
external dependencies install CocoaPods and the handy "Rome" plugin.

```
    $ sudo gem install cocoapods
    $ sudo gem install cocoapods-rome
```

Multiple classes in your script project are fine along with interface nibs.
Scripts are built as frameworks. This means they can be also imported into each
other to share code provided the script being imported has been run at
some stage - even if it's main.swift does nothing.

A small example script `browse` is included in the project directory as an
example of how to add a UI to a script. All that is required is a `MainMenu.xib`
in it's project and calling NSApplicationMain() as below. Create an AppDelegate
object instance and wire it as the delegate of the file's owner as before.

```Swift
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
        }

    }
```

Raise any issues you encounter using SwiftScripting against this github project
or you can get in touch with any suggestions via script (at) johnholdsworth.com
or on Twitter [@Injection4Xcode](https://twitter.com/#!/@Injection4Xcode).

### MIT License

Copyright (c) 2015 John Holdsworth

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in
all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
THE SOFTWARE.
