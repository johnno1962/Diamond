#!/usr/bin/env ruby

#  prepare.rb
#  Diamond
#
#  Created by John Holdsworth on 18/09/2015.
#  Copyright © 2015 John Holdsworth. All rights reserved.
#
#  $Id: //depot/Diamond/Diamond/prepare.rb#11 $
#
#  Repo: https://github.com/johnno1962/ProjectDiamond
#

require 'fileutils'

def log( msg )
    puts( "Diamond: "+msg )
end

def die( msg )
    abort( "Diamond: "+msg )
end

def prepareScriptProject( libraryRoot, scriptPath, scriptName, scriptProject, lastArg )

    # create shadow project

    newProj = scriptProject+"/"+scriptName+".xcodeproj"
    scriptMain = scriptProject+"/main.swift"
    justCreated = false

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
        project.gsub!( /TemplateProject/, scriptName )
        File.write( pbxproj, project )
        File.rename( scriptProject+"/TemplateProject.xcodeproj", newProj )

        File.symlink( ENV["HOME"]+"/Library/Diamond/Projects/RubyNative", scriptProject+"/RubyNative" )

        justCreated = true
    end

    # keep script and main.swift in sync
    # symbolic links don't work in Xcode

    scriptDate = File.mtime( scriptPath ).to_f
    mainDate = File.mtime( scriptMain ).to_f

    # puts scriptDate, mainDate

    if scriptDate > mainDate
        while File.size( scriptPath ) == 0
            puts "Diamond: Watiing for #{scriptPath} to update..."
            sleep 1
        end
        File.unlink( scriptMain )
        FileUtils.cp( scriptPath, scriptMain )
        system( "perl -e 'utime #{scriptDate}, #{scriptDate}, \"#{scriptMain}\";'" )
        puts "Copied #{scriptPath} -> #{scriptMain}"
    elsif mainDate > scriptDate
        while File.size( scriptMain ) == 0
            puts "Diamond: Waiting for #{scriptMain} to update..."
            sleep 1
        end
        File.unlink( scriptPath )
        FileUtils.cp( scriptMain, scriptPath )
        system( "perl -e 'utime #{mainDate}, #{mainDate}, \"#{scriptPath}\";'" )
        puts "Copied #{scriptMain} -> #{scriptPath}"
    end

    # user options

    case lastArg

    when "-edit"
        if justCreated
            sleep 2 # eh?
        end
        system( "open '#{newProj}'" )
        puts "Opened #{newProj}"
        exit( 123 )

    when "-show"
        showProj = scriptPath+".scriptproj"
        if !File.rename( scriptProject, showProj )
            die "Could not move project to #{showProj}"
        end
        puts "Moved #{scriptProject} -> #{showProj}"
        exit( 123 )

    when "-hide"
        hideProj = libraryRoot+"/Projects/"+scriptName
        if !File.rename( scriptProject, hideProj )
            die "Could not move project to #{hideProj}"
        end
        puts "Moved #{scriptProject} -> #{hideProj}"
        exit( 123 )

    when "-rebuild"
        isRebuild = true

    end

    # determine pod dependancies

    mainSource = File.read( scriptPath )
    missingPods = ""

    # import a // pod
    # import b // pod 'b'
    # import c // pod 'c' -branch etc
    # import d // clone xx/yy etc

    mainSource.scan( /^import\s+(\S+)(\s*\/\/\s*(!)?(?:((pod)( .*)?)|(clone (\S+)(.*))))?/ ).each { |import|
        libName = import[0]
        if !import[1]
            libProj = libName+".scriptproj"

            [libraryRoot+"/Projects/"+libName,
                libProj,
                scriptPath+"/lib/"+libProj,
                ENV["HOME"]+"/bin/lib/"+libProj].each { |libProj|

                if File.exists?( libProj )
                    prepareScriptProject( libraryRoot, libProj+"/main.swift", libName, libProj, isRebuild ? lastArg : "" )
                end
            }
        elsif import[2] == "!" || !File.exists?( libraryRoot+"/Frameworks/"+import[0]+".framework" )
            if import[3]
                missingPods += import[4] + (import[5]||" '#{import[0]}'") + "\n"
            elsif import[6]
                if import[2] == "!"
                    system( "rm -rf '#{libraryRoot}/Projects/#{libName}'" )
                end
                url = "https://github.com/"+import[7]+".git"
                if !system( "cd '#{libraryRoot}/Projects' && git clone #{import[8]} #{url} && cd #{import[0]} && xcodebuild -configuration Debug -target Framework" )
                    die "Could not clone #{import[0]} from #{url}"
                end
            end
        end
    }

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
        menuTitle = "Diamond" || scriptName

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
        <string>Diamond</string>
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

    skipRebuild = FileUtils.uptodate?( binary, Dir.glob( scriptProject+"/*.*" ) )

    # build script project

    if !skipRebuild || isRebuild
        log "Building #{scriptProject} ..."
        reloaderLog = libraryRoot+"/Reloader/"+scriptName+".log"
        mode = "a+"

        if isRebuild || File.exists?( reloaderLog ) && File.size( reloaderLog ) > 1_000_000
            system( "cd '#{scriptProject}' && xcodebuild -configuration Debug -target #{target} clean" )
            mode = "w"
        end

        out = `cd '#{scriptProject}' && xcodebuild -configuration Debug -target #{target} 2>&1`
        if !$?.success?
            die( "Script build error:\n"+out )
        end

        File.open( reloaderLog, mode ).write( out )
        FileUtils.touch( binary )
    end
end

prepareScriptProject( *ARGV )

# return to diamond binary load bundle and call main
