#!/usr/bin/env ruby -E UTF-8

#  prepare.rb
#  Diamond
#
#  Created by John Holdsworth on 18/09/2015.
#  Copyright © 2015 John Holdsworth. All rights reserved.
#
#  $Id: //depot/Diamond/Diamond/prepare.rb#47 $
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
    system( "rsync -a \"#{from}\" \"#{to}\"" )
    log( "Copied #{from} -> #{to}" )
end

def prepareScriptProject( libraryRoot, scriptPath, scriptName, scriptProject, ldFlags, lastArg )

    # create shadow project

    newProject = scriptProject+"/"+scriptName+".xcodeproj"
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
        File.rename( scriptProject+"/TemplateProject.xcodeproj", newProject )

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

    if scriptName != "guardian"

        if $indent == ""
            for contents in [ENV["HOME"]+"/bin/Contents", libraryRoot+"/Build/Debug/Contents"]
                if !File.exists?( contents )
                    FileUtils.mkdir_p( contents )
                    File.symlink( "Resources/Info.plist", contents+"/Info.plist" )
                end
                resourceFramework = mainSource[/\/\/ Resources: (\w+)/, 1] || scriptName
                FileUtils.rm_f( contents+"/Resources" )
                FileUtils.ln_s( frameworkRoot+"/"+resourceFramework+".framework/Resources", contents+"/Resources" )
            end
        end

        # patch project with any LD options from the script

        if $indent == ""
            pbxproj = newProject+"/project.pbxproj"
            original = File.read( pbxproj )

            project = original.gsub( /OTHER_LDFLAGS = [^;]+;\n/, <<LDFLAGS )
OTHER_LDFLAGS = (
#{ldFlags}				);
LDFLAGS

            if project != original
                log( "Saving OTHER_LDFLAGS to #{pbxproj}" )
                File.write( pbxproj, project )
            end
        end

        # user options

        case lastArg

        when "-edit"
            if justCreated
                sleep 2 # eh?
            end
            system( "open '#{newProject}'" )
            log( "Opened #{newProject}" )
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
    end

    # determine pod dependancies

    missingPods = ""
    missingCarts = ""
    moduleBinaries = [`xcode-select -p`]

    # import a // pod
    # import b // pod 'b'
    # import c // pod 'c' -branch etc
    # import d // github "d"
    # import f // clone e/f etc

    mainSource.scan( /^\s*import\s+(\S+)(\s*\/\/\s*(!)?((pod|github|clone)\s+(\S+)(.*)))?/ ).each { |import|
        libName = import[0]
        libFramework = frameworkRoot+"/"+libName+".framework"

        if $isReclone || import[2] == "!" || !File.exists?( libFramework )
            if import[4] == "pod"
                missingPods += import[3]+"\n"
            elsif import[4] == "github"
                missingCarts += import[3]+"\n"
            elsif import[4] == "clone"
                url = import[5]
                if url !~ /^https?:/
                    url = "https://github.com/"+url+".git"
                end
                clone = "git clone #{import[6]} #{url}"
                if !system( "cd '#{libraryRoot}/Projects' && rm -rf '#{libName}' && "+clone )
                    die( "Could not "+clone )
                end
            end
        end

        if !$builtFramework[libName]
            $builtFramework[libName] = true
            libBuilt = false

            # make sure scripts imported are rebuilt
            for libScript in [libName, ENV["HOME"]+"/bin/lib/"+libName, ENV["HOME"]+"/bin/"+libName]
                if File.exists?( libScript )
                    saveIndent = $indent
                    $indent += "  "
                    libProj = libraryRoot+"/Projects/"+libName
                    if prepareScriptProject( libraryRoot, libScript, libName, libProj, ldFlags, lastArg )
                        FileUtils.touch( scriptMain )
                    end
                    $indent = saveIndent
                    libBuilt = true
                    break
                end
            end

            if !libBuilt
                # make sure ay projects script is dependent on are rebuilt
                for libProj in [libName+".scriptproj",
                            scriptPath+"/lib/"+libName+".scriptproj",
                            ENV["HOME"]+"/bin/lib/"+libName+".scriptproj",
                            libraryRoot+"/Projects/"+libName]

                    if File.exists?( libProj )
                        saveIndent = $indent
                        $indent += "  "
                        if prepareScriptProject( libraryRoot, libProj+"/main.swift", libName, libProj, ldFlags, lastArg )
                            FileUtils.touch( scriptMain )
                        end
                        if !File.exists?( scriptProject+"/"+libName ) && scriptName != "guardian"
                            FileUtils.ln_s( File.absolute_path( libProj ), scriptProject+"/"+libName, :force => true )
                        end
                        $indent = saveIndent
                        break
                    end
                end
            end
        end

        # make sure script project is rebuilt if project it depends on has been rebuilt.
        moduleBinaries += [libFramework+"/"+libName]
    }

    # build and install any missing or forced pods & carts

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
    
    if missingCarts != ""
        File.write( libraryRoot+"/Carthage/Cartfile", missingCarts )

        log( "Fetching missing carts:\n"+missingCarts )
        if !system( "cd '#{libraryRoot}/Carthage' && carthage update" )
            die( "Could not build carts" )
        end

        log( "Copying new carts to #{frameworkRoot}" )
        if !system( "cd '#{libraryRoot}/Carthage' && (rsync -rilvp Carthage/Build/Mac/ ../Frameworks || echo 'rsync warning')" )
            die( "Could not copy carts" )
        end
    end

    # scripts ending ".bin" create binaries rather than frameworks

    if /\.dmd$/ =~ scriptPath
        target = "-target Binary"
        binary = ENV["HOME"]+"/bin/"+scriptName
    else
        target = ""#"-target "+scriptName
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

        system( "rm -rf '#{frameworkRoot}'/*.swiftmodule" )
        log( "Building #{scriptProject} #{target}")
        out = `#{build} 2>&1`
        if !$?.success?
            errors = out.scan( /(?:\n.{1,200})*\berror:.*\n(?:.+\n)*/ ).uniq.join("")
            log( "Script build error for command:\n"+build+"\n\x1b[31m"+errors+"\x1b[0m" )
            exit( 124 )
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
