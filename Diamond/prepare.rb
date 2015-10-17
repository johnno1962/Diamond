#!/usr/bin/env ruby -E UTF-8

#  prepare.rb
#  Diamond
#
#  Created by John Holdsworth on 18/09/2015.
#  Copyright © 2015 John Holdsworth. All rights reserved.
#
#  $Id: //depot/Diamond/Diamond/prepare.rb#24 $
#
#  Repo: https://github.com/johnno1962/Diamond
#

require 'fileutils'

$builtFramework = {}
$isRebuild = false
$doReclone = false
$indent = ""

def log( msg )
    puts( "Diamond: "+$indent+msg.gsub( ENV["HOME"], "~" ) )
end

def die( msg )
    abort( "*** Diamond: "+$indent+msg )
end

def dateCopy( from, to )
    if File.exists?( to )
        File.unlink( to )
    end
    FileUtils.cp( from, to )
    date = File.mtime( from ).to_f
    system( "perl -e 'utime #{date}, #{date}, \"#{to}\";'" )
    log( "Copied #{from} -> #{to}" )
end

def prepareScriptProject( libraryRoot, scriptPath, scriptName, scriptProject, lastArg )

    # create shadow project

    newProj = scriptProject+"/"+scriptName+".xcodeproj"
    scriptMain = scriptProject+"/main.swift"
    justCreated = false

    if !File.exists?( scriptPath )
        template = File.exists?( scriptMain ) ? scriptMain : libraryRoot+"/TemplateProject/main.swift"
        dateCopy( template, scriptPath )
    end

    if !File.exist?( scriptProject )

        log( "Creating #{scriptProject}" )

        if !system( "cp -rf '#{libraryRoot}/TemplateProject' '#{scriptProject}' && chmod -R +w '#{scriptProject}'" )
            die( "Could not copy TemplateProject" )
        end

        # move script into project and replace with symlink

        dateCopy( scriptPath, scriptMain )

        # change name of project to that of script
        pbxproj = scriptProject+"/TemplateProject.xcodeproj/project.pbxproj"

        project = File.read( pbxproj )
        project.gsub!( /TemplateProject/, scriptName )
        File.write( pbxproj, project )
        File.rename( scriptProject+"/TemplateProject.xcodeproj", newProj )

        justCreated = true
    end

    # keep script and main.swift in sync
    # symbolic links don't work in Xcode

    scriptDate = File.mtime( scriptPath ).to_f
    mainDate = File.mtime( scriptMain ).to_f

    if scriptDate > mainDate
        dateCopy( scriptPath, scriptMain )
    elsif mainDate > scriptDate
        dateCopy( scriptMain, scriptPath )
    end

    File.chmod( 0755, scriptPath )

    # fix up any script style comments

    mainSource = File.read( scriptMain )
    if mainSource.gsub!( /^([ \t]*)#(?!!)/m, '\1//#' )
        File.write( scriptMain, mainSource )
    end

    # create dummy "Contents" folder in script directory (bundle of app)

    frameworkRoot = libraryRoot+"/Frameworks"
    scriptFramework = frameworkRoot+"/"+scriptName+".framework"

    if mainSource =~ /NSApplicationMain/ && $indent == ""
        for contents in [ENV["HOME"]+"/bin/Contents", libraryRoot+"/Build/Debug/Contents"]
            FileUtils.mkdir_p( contents )
            FileUtils.rm_f( contents+"/Resources" )
                        resourceFramework = mainSource[/Resources: (\w+)/, 1] || scriptName
            File.symlink( frameworkRoot+"/"+resourceFramework+".framework/Resources", contents+"/Resources" )
            FileUtils.rm_f( contents+"/Info.plist" )
            File.symlink( "Resources/Info.plist", contents+"/Info.plist" )
        end
    end

    # user options

    case lastArg

    when "-edit"
        if justCreated
            sleep 2 # eh?
        end
        system( "open '#{newProj}'" )
        system( "(sleep 2; open '#{scriptMain}')&" )
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
        if !system( "open `ls -t $HOME/Library/Logs/DiagnosticReports/diamond*.crash | head -1`" )
            die( "Could not open crash log" )
        end
        exit( 123 )

    when "-reclone"
        $isReclone = 123
    
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

        if $isReclone || import[2] == "!" || !File.exists?( libFramework )
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
                    saveIndent = $indent
                    $indent += "  "
                    if prepareScriptProject( libraryRoot, libProj+"/main.swift", libName, libProj, lastArg )
                        FileUtils.touch( scriptMain )
                    end
                    if !File.exists?( scriptProject+"/"+libName )
                        File.symlink( File.absolute_path( libProj ), scriptProject+"/"+libName )
                    end
                    $indent = saveIndent
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
        if !system( "cd '#{libraryRoot}/Pods' && (rsync -rilvp Rome/ ../Frameworks || echo 'rsync warning')" )
            die( "Could not copy pods" )
        end
    end

    # scripts ending ".bin" create binaries rather than frameworks

    if /\.ccs$/ =~ scriptPath
        target = "-target Binary"
        binary = ENV["HOME"]+"/bin/"+scriptName
    else
        target = "-target Framework"
        binary = scriptFramework+"/"+scriptName
    end

    # check if recompile required

    skipRebuild = FileUtils.uptodate?( binary, moduleBinaries + Dir.glob( scriptProject+"/{*,*/*}.*" ) )

    # build script project

    if !skipRebuild || $isRebuild

        settings = "SYMROOT=#{libraryRoot}/Build/macosx"
        build = "cd '#{scriptProject}' && xcodebuild -sdk macosx -configuration Debug #{target} #{settings}"

        reloaderLog = libraryRoot+"/Reloader/"+scriptName+".log"
        mode = "a+"

        # make sure there is a complete xcodebuild log retained while keeping it under a mb
        if $isRebuild || File.exists?( reloaderLog ) && File.size( reloaderLog ) > 1_000_000
            log( "Cleaning #{scriptProject}")
            `#{build} clean 2>&1`
            mode = "w"
        end

        log( "Building #{scriptProject} #{target}")
        out = `#{build} 2>&1`
        if !$?.success?
            die( "Script build error:\n"+build+"\n"+out )
        end

        File.open( reloaderLog, mode ).write( out )
        FileUtils.touch( binary )
        return true
    end

    return false
end

# return to diamond binary load bundle and call main

prepareScriptProject( *ARGV )
exit( $isRebuild || 0 )
