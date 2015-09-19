
# SwiftScript

Of late I've been looking for a new scripting language when it comes to larger projects.
The nub of the problem is dynamically typed languages will often be giving
run time errors that should have been picked up when the script was compiled.
If only you could write scripts in a type-safe, modern language like Swift. 

From the get-go [you've been able to](http://nomothetis.svbtle.com/swift-for-scripting)
but it leaves much unresolved such as dependency management and auto-completion in the
editor. The SwiftScript project is a binary "swifts" and a ruby script
that tries to resolve these problems galvanised by a talk by
[Ayaka Nonaka](https://realm.io/news/swift-scripting/) earlier this year.

To script in SwiftScript, download and build this project and start by placing the
following into a file in your path and making it executable:

```Swift
    #!/usr/bin/env swifts

    import Cocoa
    import AlamoFire // pod 'AlamoFire'

    print( "Hello SwiftScript" )
```

Type the name of the file on the command line with a "-edit" argument.
This should convert the script into a “.scriptproj” Xcode project and open it
for so you can start creating. Your script will appear in the project as
"main.swift" and will also be available at it's previous location via a
symbolic link so you can continue to use it from the command line.
This shows how to use a pod dependancy, by putting it's pod spec in
a comment after the import.

You must have $HOME/bin in your UNIX $PATH for SwiftScript to work and for
external dependencies install CocoaPods and the excellent "Rome" plugin.

```
    $ sudo gem install cocoapods
    $ sudo gem install cocoapods-rome
```

Multiple classes in your script project are fine along with interface nibs.
Scripts are built as frameworks so they can be also imported into each
other to share code provided the script being imported has been run at
some stage - even if it does nothing.

There is a small example script "browse" in the project directory to get
you up and running. Raise any issues you encounter against this project
or you can get in touch via script (at) johnholdsworth.com or on Twitter 
[@Injection4Xcode](https://twitter.com/#!/@Injection4Xcode).

MIT License

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
