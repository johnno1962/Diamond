#!/usr/bin/env ruby

#  prepare.rb
#  SwiftScript
#
#  Created by John Holdsworth on 18/09/2015.
#  Copyright © 2015 John Holdsworth. All rights reserved.
#
#  $Id: //depot/SwiftScript/SwiftScript/prepare.rb#4 $
#
#  Repo: https://github.com/johnno1962/SwiftScript
#

require 'fileutils'

# find full path to script

script = ARGV[0]
scriptName = ARGV[1]
libraryRoot = ARGV[2]

if /^\// !~ script
    path = ENV["PATH"].split(":")+["."]
    script = path.select { |component| File.exist?( component+"/"+script ) }[0]+"/"+script
end

def save( contents, path )
    f = File.open( path, "w" )
    f.write( contents )
    f.close
end

# create shadow project

scriptProject = script+".scriptproj"
scriptMain = scriptProject+"/main.swift"

newproj = scriptProject+"/"+scriptName+".xcodeproj"

if !File.exist?( scriptProject )
    if !system( "cp -rf '#{libraryRoot}/TemplateProject' '#{scriptProject}' && chmod -R +w '#{scriptProject}'" )
        abort( "could not copy TemplateProject" )
    end

    # move script into project and replace with symlink
    File.delete( scriptMain )
    File.rename( script, scriptMain )
    if !File.symlink( File.basename(scriptProject)+"/main.swift", script )
        File.rename( scriptMain, script )
        abort( "could not link script" )
    end

    File.chmod( 0755, scriptMain )

    # change name of project to that of script
    pbxproj = scriptProject+"/TemplateProject.xcodeproj/project.pbxproj"
    project = File.open( pbxproj, "r" ).read()

    save( project.gsub( /TemplateProject/, scriptName ), pbxproj )

    File.rename( scriptProject+"/TemplateProject.xcodeproj", newproj )
end

if ARGV[3] == "1" # --edit
    system( "open '#{newproj}'" )
    exit(123)
end

# carete dummy "Contents" folder in script directory (bundle of app)

scriptFramework = libraryRoot+"/Frameworks/"+scriptName+".framework"
mainSource = File.open( scriptMain, "r" ).read()

if /NSApplicationMain/ =~ mainSource
    contents = ENV["HOME"]+"/bin/Contents"
    menuTitle = "SwiftScript"

    FileUtils::mkdir_p( contents )
    save( <<INFO_PLIST, contents+"/Info.plist" )
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
    <dict>
        <key>BuildMachineOSBuild</key>
        <string>14F27</string>
        <key>CFBundleDevelopmentRegion</key>
        <string>en</string>
        <key>CFBundleExecutable</key>
        <string>#{menuTitle}</string>
        <key>CFBundleIdentifier</key>
        <string>com.johnholdsworth.SwiftScript</string>
        <key>CFBundleInfoDictionaryVersion</key>
        <string>6.0</string>
        <key>CFBundleName</key>
        <string>SwiftScript</string>
        <key>CFBundlePackageType</key>
        <string>APPL</string>
        <key>CFBundleShortVersionString</key>
        <string>1.0</string>
        <key>CFBundleSignature</key>
        <string>????</string>
        <key>CFBundleSupportedPlatforms</key>
        <array>
        <string>MacOSX</string>
        </array>
        <key>CFBundleVersion</key>
        <string>1</string>
        <key>NSMainNibFile</key>
        <string>MainMenu</string>
        <key>NSPrincipalClass</key>
        <string>NSApplication</string>
    </dict>
</plist>
INFO_PLIST
    FileUtils.rm_f( contents+"/Resources" )
    File.symlink( scriptFramework+"/Resources", contents+"/Resources" )
end

# determine pod dependancies

missingPods = ""

mainSource.scan( /^import\s+(\S+)\s*\/\/\s*(pod .*\n)/ )
    .each { |match|
        if !File.exists?( libraryRoot+"/Frameworks/"+match[0]+".framework" )
            missingPods += match[1]
        end
    }

# build and install any missing pods

if missingPods != ""
    podfile = <<PODFILE

platform :osx, '10.10'

plugin 'cocoapods-rome'

#{missingPods}
PODFILE

    save( podfile, libraryRoot+"/Pods/Podfile" )

    if !system( "cd '#{libraryRoot}/Pods' && pod install && mv -f Rome/*.framework ../Frameworks" )
        abort( "Could not build pods" )
    end
end

# check recompile required

binary = scriptFramework+"/Versions/Current/"+scriptName
skipRebuild = File.exists?( binary )

if skipRebuild
    lastBuild = File.new( binary ).mtime
    Dir.glob( scriptProject+"/*.*" ).each { |source|
        skipRebuild &&= lastBuild > File.new( source ).mtime
    }
end

if skipRebuild
    exit(0)
end

# build script project

puts "Building #{scriptProject} ..."
out = `cd '#{scriptProject}' && xcodebuild -configuration Debug install 2>&1`
if !$?.success?
    abort( "Script build error:\n"+out )
end

# return to swifts binary load bundle and call main
