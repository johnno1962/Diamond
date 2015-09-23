#!/usr/bin/env ruby

#  reloader.rb
#  Diamond
#
#  Created by John Holdsworth on 18/09/2015.
#  Copyright © 2015 John Holdsworth. All rights reserved.
#
#  $Id: //depot/Diamond/Diamond/reloader.rb#3 $
#
#  Repo: https://github.com/johnno1962/DiamondProject
#

require 'fileutils'

libraryRoot, scriptName, fileChanged, bundlePath = ARGV

reloaderProject = "#{libraryRoot}/Reloader"
reloaderLog = "#{libraryRoot}/Reloader/#{scriptName}.log"

command = `grep -- '-primary-file #{fileChanged}' '#{reloaderLog}' | tail -1`
if command == ""
    abort( "Diamond: could not locate compile command for #{fileChanged} in #{reloaderLog}" )
end

command.gsub!( /( -o ).*/, '\1/tmp/reloader.o' )

puts "Recompiling #{fileChanged}"
if !system( command )
    abort( "Diamond: Compile Failed:\n"+command )
end

FileUtils.touch( "#{reloaderProject}/Reloader.m" )

out = `cd '#{reloaderProject}' && xcodebuild -configuration Debug install 2>&1`
if !$?.success?
    abort( "Diamond: Reload build error:\n"+out )
end

system( "rm -rf #{bundlePath} && cp -rf /tmp/Reloader.bundle #{bundlePath}" )
