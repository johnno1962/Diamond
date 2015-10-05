#!/usr/bin/env ruby -E UTF-8

#  prepare.rb
#  CocoaScript
#
#  Created by John Holdsworth on 18/09/2015.
#  Copyright © 2015 John Holdsworth. All rights reserved.
#
#  $Id: //depot/CocoaScript/CocoaScript/compile.rb#2 $
#
#  Repo: https://github.com/johnno1962/CocoaScript
#

require 'fileutils'

def log( msg )
    puts( "CocoaScript: "+msg.gsub( ENV["HOME"], "~" ) )
end

def die( msg )
    abort( "*** CocoaScript: "+msg )
end

$builtFramework = {}
$isRebuild = false

def prepareScriptProject( libraryRoot, scriptPath, scriptName, scriptProject, lastArg )

    # create shadow project

    newProj = scriptProject+"/"+scriptName+".xcodeproj"
    scriptMain = scriptProject+"/main.swift"
    justCreated = false

    if !File.exists?( scriptPath )
        log( "Creating #{scriptPath}" )

        if !system( "cp -f '#{libraryRoot}/TemplateProject/main.swift' '#{scriptPath}' && chmod +wx '#{scriptPath}'" )
            die( "Could not create script: "+scriptPath )
        end
    end

    if !File.exist?( scriptProject )

        log( "Creating #{scriptProject}" )

        if !system( "cp -rf '#{libraryRoot}/TemplateProject' '#{scriptProject}' && chmod -R +w '#{scriptProject}'" )
            die( "Could not copy TemplateProject" )
        end

        # move script into project and replace with symlink

        FileUtils.cp( scriptPath, scriptMain )
        File.chmod( 0755, scriptMain )

        # change name of project to that of script
        pbxproj = scriptProject+"/TemplateProject.xcodeproj/project.pbxproj"

        project = File.read( pbxproj )
        project.gsub!( /TemplateProject/, scriptName )
        File.write( pbxproj, project )
        File.rename( scriptProject+"/TemplateProject.xcodeproj", newProj )

        File.symlink( libraryRoot+"/Projects/RubyKit", scriptProject+"/RubyKit" )

        justCreated = true
    end

    # keep script and main.swift in sync
    # symbolic links don't work in Xcode

    scriptDate = File.mtime( scriptPath ).to_f
    mainDate = File.mtime( scriptMain ).to_f

    if scriptDate > mainDate
        File.unlink( scriptMain )
        FileUtils.cp( scriptPath, scriptMain )
        system( "perl -e 'utime #{scriptDate}, #{scriptDate}, \"#{scriptMain}\";'" )
        log( "Copied #{scriptPath} -> #{scriptMain}" )
    elsif mainDate > scriptDate
        File.unlink( scriptPath )
        FileUtils.cp( scriptMain, scriptPath )
        system( "perl -e 'utime #{mainDate}, #{mainDate}, \"#{scriptPath}\";'" )
        log( "Copied #{scriptMain} -> #{scriptPath}" )
    end

    # fix up any script style comments

    mainSource = File.read( scriptMain )
    if mainSource.gsub!( /^([ \t]*)#(?!!)/m, '\1//#' )
        File.write( scriptMain, mainSource )
    end

    # create dummy "Contents" folder in script directory (bundle of app)

    frameworkRoot = libraryRoot+"/Frameworks/macosx/Debug"
    scriptFramework = frameworkRoot+"/"+scriptName+".framework"

    if /NSApplicationMain/ =~ mainSource
        contents = ENV["HOME"]+"/bin/Contents"
        menuTitle = scriptName =~ /^[A-Z]/ ? scriptName : "CocoaScript"

        FileUtils::mkdir_p( contents )
        File.write( contents+"/Info.plist", plist = <<INFO_PLIST )
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
        <string>#{menuTitle}</string>
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
        
        # for use inside Xcode with debugger
        contents = libraryRoot+"/Frameworks/Debug/Contents"
        FileUtils.mkdir_p( contents )
        File.write( contents+"/Info.plist", plist )
        FileUtils.rm_f( contents+"/Resources" )
        File.symlink( scriptFramework+"/Resources", contents+"/Resources" )
    end

    # user options

    case lastArg

    when "-edit"
        if justCreated
            sleep 2 # eh?
        end
        system( "open '#{newProj}'" )
        log( "Opened #{newProj}" )
        exit( 123 )

    when "-show"
        showProj = scriptPath+".scriptproj"
        if !File.rename( scriptProject, showProj )
            die( "Could not move project to #{showProj}" )
        end
        log( "Moved #{scriptProject} -> #{showProj}" )
        exit( 123 )

    when "-hide"
        hideProj = libraryRoot+"/Projects/"+scriptName
        if !File.rename( scriptProject, hideProj )
            die( "Could not move project to #{hideProj}" )
        end
        log( "Moved #{scriptProject} -> #{hideProj}" )
        exit( 123 )

    when "-dump"
        if !system( "open `ls -t $HOME/Library/Logs/DiagnosticReports/cocoa*.crash | head -1`" )
            die( "Could not open crash log" )
        end
        exit( 123 )

    when "-rebuild"
        $isRebuild = 123

    end

    # determine pod dependancies

    moduleBinaries = [`xcode-select -p`]
    missingPods = ""

    # import a // pod
    # import b // pod 'b'
    # import c // pod 'c' -branch etc
    # import d // clone xx/yy etc

    mainSource.scan( /^\s*import\s+(\S+)(\s*\/\/\s*(!)?(?:((pod)( .*)?)|(clone (\S+)(.*))))?/ ).each { |import|
        libName = import[0]
        libFramework = frameworkRoot+"/"+libName+".framework"

        if import[2] == "!" || !File.exists?( libFramework )
            if import[3]
                missingPods += import[4] + (import[5]||" '#{import[0]}'") + "\n"
            elsif import[6]
                url = "https://github.com/"+import[7]+".git"
                if !system( "cd '#{libraryRoot}/Projects' && rm -rf '#{libName}' && git clone #{import[8]} #{url}" )
                    die "Could not clone #{libName} from #{url}"
                end
            end
        end

        if !$builtFramework[libName]
            $builtFramework[libName] = true

            # make sure ay projects script is dependent on are rebuilt
            for libProj in [libName+".scriptproj",
                        scriptPath+"/lib/"+libName+".scriptproj",
                        ENV["HOME"]+"/bin/lib/"+libName+".scriptproj",
                        libraryRoot+"/Projects/"+libName]

                if File.exists?( libProj )
                    prepareScriptProject( libraryRoot, libProj+"/main.swift", libName, libProj, lastArg )
                    break
                end
            end
        end

        # make sure script project is rebuilt if project it depends on has been rebuilt.
        moduleBinaries += [libFramework+"/Versions/Current/"+libName]
    }

    # build and install any missing or forced pods

    if missingPods != ""
        File.write( libraryRoot+"/Pods/Podfile", podfile = <<PODFILE )

platform :osx, '10.10'

plugin 'cocoapods-rome'

#{missingPods}
PODFILE

        log( "Fetching missing pods:\n"+podfile )
        if !system( "cd '#{libraryRoot}/Pods' && pod install" )
            die( "Could not build pods" )
        end

        log( "Copying new pods to #{frameworkRoot}" )
        if !system( "cd '#{libraryRoot}/Pods' && (rsync -rilvp Rome/ ../Frameworks/macosx/Debug || echo 'rsync warning')" )
            die( "Could not copy pods" )
        end
    end

    # scripts ending ".bin" create binaries rather than frameworks

    if /\.ccs$/ =~ scriptPath
        target = "Binary"
        binary = ENV["HOME"]+"/bin/"+scriptName
    else
        target = "Framework"
        binary = scriptFramework+"/Versions/Current/"+scriptName
    end

    # check if recompile required

    skipRebuild = FileUtils.uptodate?( binary, moduleBinaries + Dir.glob( scriptProject+"/**.*" ) )

    # build script project

    if !skipRebuild || $isRebuild

        settings = "SYMROOT=#{libraryRoot}/Frameworks/macosx"
        build = "cd '#{scriptProject}' && xcodebuild -sdk macosx -configuration Debug -target #{target} #{settings}"

        reloaderLog = libraryRoot+"/Reloader/"+scriptName+".log"
        mode = "a+"

        # make sure there is a complete xcodebuild log retained while keeping it under a mb
        if $isRebuild || File.exists?( reloaderLog ) && File.size( reloaderLog ) > 1_000_000
            log( "Cleaning #{scriptProject}")
            `#{build} clean 2>&1`
            mode = "w"
        end

        log( "Building #{scriptProject}")
        out = `#{build} 2>&1`
        if !$?.success?
            die( "Script build error:\n"+build+"\n"+out )
        end

        File.open( reloaderLog, mode ).write( out )
        FileUtils.touch( binary )
    end
end

# return to cocoa binary load bundle and call main

prepareScriptProject( *ARGV )
exit( $isRebuild || 0 )
