#!/usr/bin/env ruby

#  reloader.rb
#  CocoaScript
#
#  Created by John Holdsworth on 18/09/2015.
#  Copyright © 2015 John Holdsworth. All rights reserved.
#
#  $Id: //depot/CocoaScript/CocoaScript/reloader.rb#1 $
#
#  Repo: https://github.com/johnno1962/CocoaScript
#

require 'fileutils'

libraryRoot, scriptName, fileChanged, bundlePath = ARGV

reloaderProject = "#{libraryRoot}/Reloader"
reloaderLog = "#{libraryRoot}/Reloader/#{scriptName}.log"

command = `grep -- '-primary-file #{fileChanged}' '#{reloaderLog}' | tail -1`
if command == ""
    abort( "CocoaScript Reloader: could not locate compile command for #{fileChanged} in #{reloaderLog}" )
end

command.gsub!( /( -o ).*/, '\1/tmp/reloader.o' )

puts "Recompiling #{fileChanged}"
if !system( command )
    abort( "CocoaScript Reloader: Compile Failed:\n"+command )
end

FileUtils.touch( "#{reloaderProject}/Reloader.m" )

out = `cd '#{reloaderProject}' && xcodebuild -configuration Debug install 2>&1`
if !$?.success?
    abort( "CocoaScript Reloader: Reload build error:\n"+out )
end

system( "rm -rf #{bundlePath} && cp -rf /tmp/Reloader.bundle #{bundlePath}" )
