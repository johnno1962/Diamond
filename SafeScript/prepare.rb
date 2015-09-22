#!/usr/bin/env ruby

#  prepare.rb
#  SafeScript
#
#  Created by John Holdsworth on 18/09/2015.
#  Copyright © 2015 John Holdsworth. All rights reserved.
#
#  $Id: //depot/SafeScript/SafeScript/prepare.rb#14 $
#
#  Repo: https://github.com/johnno1962/SafeScript
#

require 'fileutils'

def log( msg )
    puts( "SafeScript: "+msg )
end

def die( msg )
    abort( "SafeScript: "+msg )
end

def prepareScriptProject( libraryRoot, scriptPath, scriptName, scriptProject, isRebuild, isEdit )

    # create shadow project

    newProj = scriptProject+"/"+scriptName+".xcodeproj"
    scriptMain = scriptProject+"/main.swift"

    if !File.exist?( scriptProject )

        if !File.exists?( scriptPath )
            log "Creating #{scriptPath}"

            if !system( "cp -f '#{libraryRoot}/TemplateProject/main.swift' '#{scriptPath}' && chmod +x '#{scriptPath}'" )
                die( "could not create script: "+scriptPath )
            end
        end

        log "Creating #{scriptProject}"

        if !system( "cp -rf '#{libraryRoot}/TemplateProject' '#{scriptProject}' && chmod -R +w '#{scriptProject}'" )
            die( "could not copy TemplateProject" )
        end

        # move script into project and replace with symlink

        FileUtils.mv( scriptPath, scriptMain, :force => true )
        if !File.link( scriptMain, scriptPath )
            File.rename( scriptMain, scriptPath )
            die( "Could not link script "+scriptPath )
        end

        File.chmod( 0755, scriptMain )

        # change name of project to that of script
        pbxproj = scriptProject+"/TemplateProject.xcodeproj/project.pbxproj"
        project = File.read( pbxproj )

        File.write( pbxproj, project.gsub( /TemplateProject/, scriptName ) )

        File.rename( scriptProject+"/TemplateProject.xcodeproj", newProj )
    end

    if isEdit == "1" # --edit
        system( "open '#{newProj}'" )
        exit(0)
    end

    # determine pod dependancies

    mainSource = File.read( scriptPath )
    missingPods = ""

    mainSource.scan( /^import\s+(\S+)(\s*\/\/\s*(!)?((pod)( .*)?))?/ ).each { |import|
        if !import[1]
            [scriptPath, ENV["HOME"]+"/bin"].each { |libDir|
                libPath = File.dirname( libDir )+"/lib/"+import[0]

                if File.exists?( libPath )
                    libName = File.basename(libPath)
                    libProj = File.dirname(libPath)+"/"+libName+".scriptproj"
                    prepareScriptProject( libraryRoot, libPath, libName, libProj, isRebuild, "0" )
                end
            }
            elsif import[2] == "!" || !File.exists?( libraryRoot+"/Frameworks/"+import[0]+".framework" )
            missingPods += import[4] + (import[5]||" '#{import[0]}'") + "\n"
        end
    }

    # keep script and main.swift in sync
    # symbolic links don't work in Xcode

    scriptDate = File.mtime( scriptPath ).to_f
    mainDate = File.mtime( scriptMain ).to_f

    if scriptDate > mainDate
        File.rm_f( scriptMain )
        File.link( scriptPath, scriptMain )
    elsif mainDate > scriptDate
        File.rm_f( scriptPath )
        File.link( scriptMain, scriptPath )
    end

    # build and install any missing or forced pods

    if missingPods != ""
        File.write( libraryRoot+"/Pods/Podfile", podfile = <<PODFILE )

platform :osx, '10.10'

plugin 'cocoapods-rome'

#{missingPods}
PODFILE

        log "Fetching missing pods:\n"+podfile
        if !system( "cd '#{libraryRoot}/Pods' && pod install" )
            die( "Could not build pods" )
        end

        log "Copying new pods to #{libraryRoot}/Frameworks"
        if !system( "cd '#{libraryRoot}/Pods' && (rsync -rilvp Rome/ ../Frameworks || echo 'rsync warning')" )
            die( "Could not copy pods" )
        end
    end

    # create dummy "Contents" folder in script directory (bundle of app)

    scriptFramework = libraryRoot+"/Frameworks/"+scriptName+".framework"

    if /NSApplicationMain/ =~ mainSource
        contents = ENV["HOME"]+"/bin/Contents"
        menuTitle = "SafeScript"

        FileUtils::mkdir_p( contents )
        File.write( contents+"/Info.plist", <<INFO_PLIST )
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
        FileUtils.rm_f( contents+"/Resources" )
        File.symlink( scriptFramework+"/Resources", contents+"/Resources" )
    end

    # check if recompile required

    if /\.bin$/ =~ scriptPath
        target = "Binary"
        binary = ENV["HOME"]+"/bin/"+scriptName
    else
        target = "Framework"
        binary = scriptFramework+"/Versions/Current/"+scriptName
    end

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

    isRebuild = isRebuild == "1"

    if !skipRebuild || isRebuild
        log "Building #{scriptProject} ..."
        reloaderLog = libraryRoot+"/Reloader/"+scriptName+".log"
        mode = "a+"

        if isRebuild || File.exists?( reloaderLog ) && File.size( reloaderLog ) > 1_000_000
            system( "cd '#{scriptProject}' && xcodebuild -configuration Debug -target #{target} clean" )
            mode = "w"
        end

        out = `cd '#{scriptProject}' && xcodebuild -configuration Debug -target #{target} install 2>&1`
        if !$?.success?
            die( "Script build error:\n"+out )
        end

        File.open( reloaderLog, mode ).write( out )
        FileUtils.touch( binary )
    end
end

prepareScriptProject( *ARGV )

# return to safescript binary load bundle and call main
