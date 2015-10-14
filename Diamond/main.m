//
//  main.m
//  Diamond
//
//  Created by John Holdsworth on 18/09/2015.
//  Copyright © 2015 John Holdsworth. All rights reserved.
//
//  $Id: //depot/Diamond/Diamond/main.m#17 $
//
//  Repo: https://github.com/johnno1962/Diamond
//

#import <Foundation/Foundation.h>

#define SError( ... ) { NSLog( @"diamond: " __VA_ARGS__ ); exit( EXIT_FAILURE ); }

static int execFramework( NSString *framework, int argc, const char **argv );
static void watchProject( NSString *scriptName );
static NSString *libraryRoot, *scriptName;
static FSEventStreamRef fileEvents;

static pid_t childPid;

static void ensureChildExits( int signal ) {
    kill( childPid, SIGKILL );
    exit( 1 );
}

//
// I won't deny this is a curly piece of code. It calls itself in a child process
// so traps can be detected and the symbolicated crash reports taken from
// ~/Library/Logs/DiagnosticReports and presented to the user.
//
// This shell has to be written in Objective-C to avoid linking with the swift
// static libraries which causes problems with multiple definitions when the
// frameworks load. Most of the work is done by the compile.rb script anyways.
//
// First time through argv is ["diamond", "script_name", "args.."]
// Child process argv is ["diamond", "run:", "script_name", "args.."]
//
// guardian.framework main() receives ["child_pid", "script_name", "args.."]
// script's framework main() receives ["script_name", "args.."]
//
// Entry point for frameworks is found using it's CFBundle by looking up the
// symbol main(). Frameworks for the main script are loaded as an NSBundle.
// Framework for parent process is "guardian". Framework for child is script.
//
// The file watcher to look for changes to inject into classes only runs in
// the child process.
//
// The final crinkle is "x.ccs" scripts produce standalone "~/bin/x.cce" binaries
// (subject to availability of frameworks it depends on in ~/Library/Diamond/...)
// Injection to a standalone ".cce" executable is not possible.
//

int main( int argc, const char * argv[] ) {

    @autoreleasepool {

        if ( argc < 2 )
            SError( "must be run with a script name" );

        NSString *home = [NSString stringWithUTF8String:getenv("HOME")];
        libraryRoot = [home stringByAppendingPathComponent:@"Library/Diamond"];

        // diamond is called twice. Once to execute the "guardian" framework
        // and once with the first argument run: to run the actual script.
        // The guardian process watches for traps in the child process and
        // processes the generated crash report to display the line number
        // the script failed in a full symbolicated, demagled stack trace.
        const char *runIndicator = "run:";
        BOOL isChild = strcmp( argv[1], runIndicator ) == 0;

        NSString *script = isChild ? [NSString stringWithUTF8String:argv[2]] :
        [libraryRoot stringByAppendingPathComponent:@"Resources/guardian"];
        NSString *lastArg = isChild && argv[argc-1][0] == '-' ? [NSString stringWithUTF8String:argv[argc-1]] : @"";
        BOOL isRestarter = strcmp( argv[argc-1], "-restarter" ) == 0;

        // find the actual script path using $PATH from the environment.
        NSString *scriptPath = script, *mainPath = [script stringByAppendingString:@".scriptproj/main.swift"];
        NSFileManager *manager = [NSFileManager defaultManager];

        unichar path0 = [scriptPath characterAtIndex:0];
        if ( path0 != '/' && path0 != '.' )
            for ( NSString *component in [[NSString stringWithUTF8String:getenv("PATH")] componentsSeparatedByString:@":"] ) {
                NSString *result = [component stringByAppendingPathComponent:script];
                if ( [manager fileExistsAtPath:result] ) {
                    scriptPath = result;
                    break;
                }
                result = [component stringByAppendingPathComponent:mainPath];
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
        NSString *compileCommand = [NSString stringWithFormat:@"%@/Resources/prepare.rb \"%@\" \"%@\" \"%@\" \"%@\" \"%@\"",
                                    libraryRoot, libraryRoot, scriptPath, scriptName, scriptProject, lastArg];

        int status;
    restart:
        // call compile.rb to prepare Frameworks/Binary
        status = system( [compileCommand UTF8String] );

        // user option such as -edit, -show, -hide, -rebuild
        if ( status >> 8 == 123 )
            exit( 0 );

        if ( status != EXIT_SUCCESS )
            SError( "%@ returns error %x", compileCommand, status );

        if ( !isChild ) {

            setenv( "DIAMOND_LIBRARY_ROOT", [libraryRoot UTF8String], 1 );
            setenv( "DIAMOND_PROJECT_ROOT", [scriptProject UTF8String], 1 );

            // This is where actual script is run as a child process leaving the
            // guardian framework monitoring it for traps/crashes to dump .crash
            if ( (childPid = fork()) == 0 ) {

                const char **shiftedArgv = calloc( argc+3, sizeof *shiftedArgv );
                shiftedArgv[0] = "/usr/bin/env";
                shiftedArgv[1] = "diamond";
                shiftedArgv[2] = runIndicator; // run:
                for ( int i=1 ; i<=argc ; i++ )
                    shiftedArgv[i+2] = argv[i];

                execv( shiftedArgv[0], (char *const *)shiftedArgv );
                SError( "execv failed" );
            }

            // ENV["DIAMOND_CHILD_PID"] for guardian framework main() is process id of child process.
            setenv( "DIAMOND_CHILD_PID", argv[0] = [[NSString stringWithFormat:@"%d", childPid] UTF8String], 1 );

            signal( SIGINT, ensureChildExits );

            // run the guardian script .framework
            status = execFramework( scriptName, argc, argv );

            // restart on crash
            if ( isRestarter )
                goto restart;
        }

        else if ( isChild ) {
            if ( isRestarter )
                argv[--argc] = NULL;

            argv[2] = [scriptPath UTF8String];

            // This code relates to ".cce" binaries used as an alternative to frameworks
            if ( [scriptPath hasSuffix:@".ccs"] ) {

                // execv binary in child process if present (and there is run: argument.)
                NSString *binaryPath = [NSString stringWithFormat:@"%@/bin/%@.cce", home, scriptName];
                if ( [[NSFileManager defaultManager] isExecutableFileAtPath:binaryPath] )
                    execv( [binaryPath UTF8String], (char *const *)argv+2 );

                SError( "Unable to execute %@: %s", binaryPath, strerror(errno) );
            }

            // If running actual script in child process,
            // start file watcher for code reloading.
            watchProject( scriptProject );

            // runthe actual script .framework
            status = execFramework( scriptName, argc-2, argv+2 );

            if ( fileEvents ) {
                FSEventStreamStop( fileEvents );
                FSEventStreamInvalidate( fileEvents );
                FSEventStreamRelease( fileEvents );
            }
        }

        exit( status );
    }

    return 0;
}

static int execFramework( NSString *scriptName, int argc, const char **argv ) {
    // Now look for Framework with the script's name determined before and load it as a bundle.
    NSString *frameworkPath = [NSString stringWithFormat:@"%@/Frameworks/%@.framework",
                               libraryRoot, scriptName];
    NSBundle *frameworkBundle = [NSBundle bundleWithPath:frameworkPath];

    if ( !frameworkBundle )
        SError( "Could not locate binary or framemork bundle %@", frameworkPath );

    if ( ![frameworkBundle load] )
        SError( "Could not load framemork bundle %@", frameworkBundle );

    // Slight hack to get CFBundle from NSBundle so we can locate main function in main.swift
    CFBundleRef cfBundle = (__bridge CFBundleRef)[frameworkBundle valueForKey:@"cfBundle"];

    if ( !cfBundle )
        SError( "Could not access CFBundle %@", frameworkBundle );

    // find pointer to main( argc, argv )
    // ..can be guardian or actual script.
    typedef int (*main_t)( int argc, const char * argv[] );
    main_t scriptMain = (main_t)CFBundleGetFunctionPointerForName( cfBundle, (CFStringRef)@"main" );

    if ( !scriptMain )
        SError( "Could not locate main() function in %@", frameworkBundle );

    int status = 1;
    @try {
        // run guardian or script in child process.
        status = scriptMain( argc, argv );
    }
    @catch ( NSException *e ) {
        NSLog( @"Exception %@\n%@", e, e.callStackSymbols );
        abort();
    }

    return status;
}

static void fileCallback( ConstFSEventStreamRef streamRef,
                         void *clientCallBackInfo,
                         size_t numEvents, void *eventPaths,
                         const FSEventStreamEventFlags eventFlags[],
                         const FSEventStreamEventId eventIds[] ) {
    NSArray *changed = (__bridge NSArray *)eventPaths;

    for ( NSString *fileChanged in changed ) {

        if ( [fileChanged hasSuffix:@".swift"] && [fileChanged rangeOfString:@"~."].location == NSNotFound ) {
            static int busy;

            if ( !busy++ ) {

                static int reloadNumber;
                NSString *bundlePath = [NSString stringWithFormat:@"/tmp/Reloader%d.bundle", reloadNumber++];
                NSString *reloadCommand = [NSString stringWithFormat:@"%@/Resources/reloader.rb '%@' '%@' '%@' '%@'",
                                           libraryRoot, libraryRoot, scriptName, fileChanged, bundlePath];

                int status = system( [reloadCommand UTF8String] ) >> 8;

                if ( status != EXIT_SUCCESS )
                    NSLog( @"diamond: %@ returns error", reloadCommand );
                else if ( ![[NSBundle bundleWithPath:bundlePath] load] )
                    NSLog( @"diamond: Could not reload bundle: %@", bundlePath );
            }

            busy--;
        }
    }
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
