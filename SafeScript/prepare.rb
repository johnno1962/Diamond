#!/usr/bin/env ruby

#  prepare.rb
#  SafeScript
#
#  Created by John Holdsworth on 18/09/2015.
#  Copyright © 2015 John Holdsworth. All rights reserved.
#
#  $Id: //depot/SafeScript/SafeScript/prepare.rb#4 $
#
#  Repo: https://github.com/johnno1962/SafeScript
#

require 'fileutils'

def save( contents, path, mode = "w" )
    f = File.open( path, mode )
    f.write( contents )
    f.close
end

def die( msg )
    abort( "SafeScript: "+msg )
end

libraryRoot, scriptPath, scriptName, scriptProject, isRebuild, isEdit = ARGV

isRebuild = isRebuild == "1"
isEdit = isEdit == "1"

# create shadow project

newProj = scriptProject+"/"+scriptName+".xcodeproj"

if !File.exist?( scriptProject )
    puts "SafeScript: Creating #{scriptProject}"

    if !system( "cp -rf '#{libraryRoot}/TemplateProject' '#{scriptProject}' && chmod -R +w '#{scriptProject}'" )
        die( "could not copy TemplateProject" )
    end

    # move script into project and replace with symlink
    scriptMain = scriptProject+"/main.swift"

    FileUtils.mv( scriptPath, scriptMain, :force => true )
    if !File.symlink( File.basename( scriptProject )+"/main.swift", scriptPath )
        File.rename( scriptMain, scriptPath )
        die( "Could not link script "+scriptPath )
    end

    File.chmod( 0755, scriptMain )

    # change name of project to that of script
    pbxproj = scriptProject+"/TemplateProject.xcodeproj/project.pbxproj"
    project = File.open( pbxproj, "r" ).read()

    save( project.gsub( /TemplateProject/, scriptName ), pbxproj )

    File.rename( scriptProject+"/TemplateProject.xcodeproj", newProj )
end

if isEdit # --edit
    system( "open '#{newProj}'" )
    exit(0)
end

# create dummy "Contents" folder in script directory (bundle of app)

scriptFramework = libraryRoot+"/Frameworks/"+scriptName+".framework"
mainSource = File.open( scriptPath, "r" ).read()

if /NSApplicationMain/ =~ mainSource
    contents = ENV["HOME"]+"/bin/Contents"
    menuTitle = "SafeScript"

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
        <string>com.johnholdsworth.#{menuTitle}</string>
        <key>CFBundleIconFile</key>
        <string>App.icns</string>
        <key>CFBundleInfoDictionaryVersion</key>
        <string>6.0</string>
        <key>CFBundleName</key>
        <string>SafeScript</string>
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
    FileUtils.symlink( scriptFramework+"/Resources", contents+"/Resources", :force => true )
end

# determine pod dependancies

missingPods = ""

mainSource.scan( /^import\s+(\S+)(\s*\/\/\s*(!)?((pod)( .*)?))?/ )
    .each { |import|
        if !import[1]
            [scriptPath, ENV["HOME"]+"/bin"].each { |libDir|
                libPath = File.dirname( libDir )+"/lib/"+import[0]
                if File.exists?( libPath )
                    libName = File.basename(libPath)
                    libProj = File.dirname(libPath)+"/"+libName+".scriptproj"
                    libCmd = "#{$0} '#{libraryRoot}' '#{libPath}' '#{libName}' '#{libProj}' #{isRebuild ? 1 : 0} 0"
                    if !system( libCmd )
                        die( "Error preparing #{libPath}: "+libCmd )
                    end
                end
            }
        elsif import[2] == "!" || !File.exists?( libraryRoot+"/Frameworks/"+import[0]+".framework" )
            missingPods += import[4] + (import[5]||" '#{import[0]}'") + "\n"
        end
    }

# build and install any missing or forced pods

if missingPods != ""
    podfile = <<PODFILE

platform :osx, '10.10'

plugin 'cocoapods-rome'

#{missingPods}
PODFILE

    save( podfile, libraryRoot+"/Pods/Podfile" )

    if !system( "cd '#{libraryRoot}/Pods' && pod install && (rsync -rilvp Rome/ ../Frameworks || echo 'rsync warning')" )
        die( "Could not build pods:\n"+podfile )
    end
end

# check if recompile required

binary = scriptFramework+"/Versions/Current/"+scriptName
skipRebuild = File.exists?( binary )

if skipRebuild
    lastBuild = File.new( binary ).mtime
    Dir.glob( scriptProject+"/*.*" ).each { |source|
        if File.new( source ).mtime > lastBuild
            skipRebuild = false
        end
    }
end

# build script project

if !skipRebuild || isRebuild
    puts "SafeScript: Building #{scriptProject} ..."
    logPath = libraryRoot+"/Reloader/"+scriptName+".log"
    mode = "a+"

    if File.exists?( logPath ) && File.size( logPath ) > 1_000_000 || isRebuild
        system( "cd '#{scriptProject}' && xcodebuild -configuration Debug clean" )
        mode = "w"
    end

    out = `cd '#{scriptProject}' && xcodebuild -configuration Debug install 2>&1`
    if !$?.success?
        die( "SafeScript: Script build error:\n"+out )
    end

    save( out, logPath, mode )
    FileUtils.touch( binary )
end

# return to safescript binary load bundle and call main
