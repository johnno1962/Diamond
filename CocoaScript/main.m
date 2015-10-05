//
//  main.m
//  CocoaScript
//
//  Created by John Holdsworth on 18/09/2015.
//  Copyright © 2015 John Holdsworth. All rights reserved.
//
//  $Id: //depot/CocoaScript/CocoaScript/main.m#16 $
//
//  Repo: https://github.com/johnno1962/CocoaScript
//

#import <Foundation/Foundation.h>

#define SError( ... ) { NSLog( @"cocoa: " __VA_ARGS__ ); exit( EXIT_FAILURE ); }

static void watchProject( NSString *scriptName );
static NSString *libraryRoot, *scriptName;
static FSEventStreamRef fileEvents;

//
// I won't deny this is a cury peice of code. It calls itself in a child process
// so traps can be detected and the symbolicated crash reports taken from
// ~/Library/Logs/DiagnosticReports are presented to the user
//
// First time through argv is ["cocooa", "script_name", "args.."]
// Child process gets ["cocoa", "run:", "script_name", "args.."]
//
// Entry point for frameworks is found using it's CFBundle by looking up the
// symbol main(). Frameworks for the main script are loaded as an NSBundle.
// Framework for parent process is "guardian". Framework for child is script.
//
// This is complicated by the fact the  file watcher for must only run in the
// child process to look for changes to inject into classes in reaal time.
//
// The final crinkle is "x.ccs" scripts produce standalone "~/bin/x.cce" binaries
// (subject to availablility of framework it depends on in ~/Library/CocoaPods/...)
//

int main( int argc, const char * argv[] ) {

    @autoreleasepool {

        if ( argc < 2 )
            SError( "must be run with a script name" );

        NSString *home = [NSString stringWithUTF8String:getenv("HOME")];
        libraryRoot = [home stringByAppendingPathComponent:@"Library/CocoaScript"];

        // cocoa is called twice. Once to execute the "guardian" framework
        // and once with the first argument run: to run the actual script.
        // The guardian process watches for traps in the child process and
        // processes the generated crash report to display the line number
        // the script failed at in a full stack trace.
        const char *runIndicator = "run:";
        BOOL isRun = strcmp( argv[1], runIndicator ) == 0;

        NSString *script = isRun ? [NSString stringWithUTF8String:argv[2]] :
            [libraryRoot stringByAppendingPathComponent:@"Resources/guardian"];
        NSString *lastArg = isRun && argv[argc-1][0] == '-' ? [NSString stringWithUTF8String:argv[argc-1]] : @"";

        NSString *scriptPath = script;
        NSFileManager *manager = [NSFileManager defaultManager];

        // find the actual script path using $PATH from the environment.
        unichar path0 = [scriptPath characterAtIndex:0];
        if ( path0 != '/' && path0 != '.' )
            for ( NSString *component in [[NSString stringWithUTF8String:getenv("PATH")] componentsSeparatedByString:@":"] ) {
                NSString *result = [component stringByAppendingPathComponent:script];
                if ( [manager fileExistsAtPath:result] ) {
                    scriptPath = result;
                    break;
                }
            }

        // remove extension from last path component to find framework name
        scriptName = [[script lastPathComponent] stringByDeletingPathExtension];

        // find path to "hidden" or "shown" .scriptproj shadow Xcode project for editing/building
        NSString *scriptProject = [scriptPath stringByAppendingString:@".scriptproj"];
        if ( ![manager fileExistsAtPath:scriptProject] )
            scriptProject = [NSString stringWithFormat:@"%@/Projects/%@", libraryRoot, scriptName];

        // Call compile.rb to build script into framework (or binary.cce if extension is .ccs.)
        // Makes sure project is built if any frameworks it is dependant on are rebuilt recursively.
        NSString *compileCommand = [NSString stringWithFormat:@"%@/Resources/compile.rb \"%@\" \"%@\" \"%@\" \"%@\" \"%@\"",
                                    libraryRoot, libraryRoot, scriptPath, scriptName, scriptProject, lastArg];

        int status = system( [compileCommand UTF8String] );

        if ( status >> 8 == 123 )
            exit( 0 );
        if ( status != EXIT_SUCCESS )
            SError( "%@ returns error %x", compileCommand, status );

        if ( !isRun ) {
            pid_t pid;

            // This is where actual script is run as a child process leaving the
            // guardian framework monitoring it for traps/crashes to dump .crash
            
            if ( !(pid = fork()) ) {
                const char **shiftedArgv = calloc( argc+2, sizeof *shiftedArgv );
                shiftedArgv[0] = "/usr/bin/env";
                shiftedArgv[1] = "cocoa";
                shiftedArgv[2] = runIndicator;
                for ( int i=1 ; i<=argc ; i++ )
                    shiftedArgv[i+2] = argv[i];
                execv( shiftedArgv[0], (char *const *)shiftedArgv );
                SError( "execv failed" );
            }

            // argv[0] for guardian framework main() is process id of child process.
            argv[0] = strdup( [[NSString stringWithFormat:@"%d", pid] UTF8String] );
        }

        else {

            // This code relates to ".cce" binaries used as an alternative to frameworks
            if ( [scriptPath hasSuffix:@".ccs"] ) {

                setenv( "COCOA_LIBRARY_ROOT", strdup( [libraryRoot UTF8String] ), 1 );
                setenv( "COCOA_PROJECT_ROOT", strdup( [scriptProject UTF8String] ), 1 );
                argv[0] = strdup( [scriptPath UTF8String] );

                // execv binary in child process if present (and there is run: argument.)
                NSString *binaryPath = [NSString stringWithFormat:@"%@/bin/%@.cce", home, scriptName];
                if ( [[NSFileManager defaultManager] isExecutableFileAtPath:binaryPath] &&
                    execv( [binaryPath UTF8String], (char *const *)argv+2 ) )
                    SError( "Unable to execute %@: %s", binaryPath, strerror(errno) );
            }

            // If running actual script in child process,
            // start file watcher for code reloading.
            watchProject( scriptProject );
        }

        // Now look for Framework with the script's name determined before and load it as a bundle.
        NSString *frameworkPath = [NSString stringWithFormat:@"%@/Frameworks/macosx/Debug/%@.framework",
                                   libraryRoot, scriptName];
        NSBundle *frameworkBundle = [NSBundle bundleWithPath:frameworkPath];

        if ( !frameworkBundle )
            SError( "Could not locate binary or framemork bundle %@", frameworkPath );

        if ( ![frameworkBundle load] )
            SError( "Could not load framemork bundle %@", frameworkBundle );

        // Need CFBundle fro NSBundle so we can locate main function in main.swift
        CFBundleRef cfBundle = (__bridge CFBundleRef)[frameworkBundle valueForKey:@"cfBundle"];

        if ( !cfBundle )
            SError( "Could not access CFBundle %@", frameworkBundle );

        // find pointer to main( argc, argv )
        // can be guardian or actual script.
        typedef int (*main_t)(int argc, const char * argv[]);
        main_t scriptMain = (main_t)CFBundleGetFunctionPointerForName( cfBundle, (CFStringRef)@"main" );

        if ( !scriptMain )
            SError( "Could not locate main() function in %@", frameworkBundle );

        @try {
            // run guardian or script in child process.
            status = scriptMain( argc-isRun*2, argv+isRun*2 );
        }
        @catch ( NSException *e ) {
            SError( "Exception %@\n%@", e, e.callStackSymbols );
        }

        // That's it, close fileWatcher and exit.
        if ( fileEvents ) {
            FSEventStreamStop( fileEvents );
            FSEventStreamInvalidate( fileEvents );
            FSEventStreamRelease( fileEvents );
        }

        exit( status );
    }

    return 0;
}

static void fileCallback( ConstFSEventStreamRef streamRef,
                         void *clientCallBackInfo,
                         size_t numEvents, void *eventPaths,
                         const FSEventStreamEventFlags eventFlags[],
                         const FSEventStreamEventId eventIds[] ) {
    NSArray *changed = (__bridge NSArray *)eventPaths;
    NSString *fileChanged = changed[0];

    if ( ![fileChanged hasSuffix:@".swift"] || [fileChanged rangeOfString:@"~."].location != NSNotFound )
        return;

    static int busy;
    if ( !busy++ ) {

        static int reloadNumber;
        NSString *bundlePath = [NSString stringWithFormat:@"/tmp/Reloader%d.bundle", reloadNumber++];
        NSString *reloadCommand = [NSString stringWithFormat:@"%@/Resources/reloader.rb '%@' '%@' '%@' '%@'",
                                   libraryRoot, libraryRoot, scriptName, fileChanged, bundlePath];

        int status = system( [reloadCommand UTF8String] ) >> 8;

        if ( status != EXIT_SUCCESS )
            NSLog( @"cocoa: %@ returns error", reloadCommand );
        else if ( ![[NSBundle bundleWithPath:bundlePath] load] )
            NSLog( @"cocoa: Could not reload bundle: %@", bundlePath );
    }

    busy--;
}

static void watchProject( NSString *scriptProject ) {
    static struct FSEventStreamContext context;
    fileEvents = FSEventStreamCreate( kCFAllocatorDefault,
                                     fileCallback, &context,
                                     (__bridge CFArrayRef)@[scriptProject],
                                     kFSEventStreamEventIdSinceNow, .1,
                                     kFSEventStreamCreateFlagUseCFTypes|
                                     kFSEventStreamCreateFlagFileEvents);
    FSEventStreamScheduleWithRunLoop(fileEvents, CFRunLoopGetMain(), kCFRunLoopDefaultMode);
    FSEventStreamStart( fileEvents );
}
