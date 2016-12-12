//
//  main.m
//  Diamond
//
//  Created by John Holdsworth on 18/09/2015.
//  Copyright © 2015 John Holdsworth. All rights reserved.
//
//  $Id: //depot/Diamond/Diamond/main.m#34 $
//
//  Repo: https://github.com/johnno1962/Diamond
//

@import Foundation;
#import <sys/xattr.h>
#import <crt_externs.h>

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wcstring-format-directive"
#pragma clang diagnostic ignored "-Wcast-qual"

#define DError( ... ) { \
    fputs( [[NSString stringWithFormat:@"diamond: " __VA_ARGS__ ] UTF8String], stderr ); \
    exit( EXIT_FAILURE ); \
}

static NSString *extractLDFlags( const char **argv[] );
static NSString *locateScriptInPath( NSString *script, NSString *home );
static int execFramework( NSString *framework, int argc, const char **argv );
static void watchProject( NSString *scriptName );

static NSString *libraryRoot, *scriptName;
static FSEventStreamRef fileEvents;
static void (*savedHandler)( int );
static pid_t childPid;

static void ensureChildExits( int signum ) {
    if ( childPid ) {
        kill( childPid, SIGABRT );
        fprintf( stderr, " Signal sent. Type ^C again to exit or wait for stacktrace\n" );
    }
    signal( SIGINT, savedHandler );
}

//
// I won't deny this is a curly piece of code. It calls itself in a child process
// so traps can be detected and the symbolicated crash reports taken from
// ~/Library/Logs/DiagnosticReports and presented to the user.
//
// This shell has to be written in Objective-C to avoid linking with the swift
// static libraries which causes problems with multiple definitions when the
// frameworks load. Most of the work is done by the prepare.rb script anyways.
//
// First time through argv is ["diamond", "script_name", "args.."]
// Child process argv is ["diamond", "run:", "script_name", "args.."]
//
// guardian.framework main() receives ["child_pid", "script_name", "args.."]
// script's framework main() receives ["script_name", "args.."]
//
// Frameworks for the main script are loaded as an NSBundle. Entry point for
// frameworks is found using it's CFBundle by looking up the symbol main().
// Framework for parent process is "guardian". Framework for child is script.
//
// The file watcher to look for changes to inject into classes only runs in
// the child process. When running it will apply source changes immediately.
//
// The final crinkle is "x.dmd" scripts produce standalone "~/bin/x.dme" binaries
// (subject to availability of frameworks it depends on in ~/Library/Diamond/...)
// File Watcher Injection to a standalone ".dme" executable is not possible.
//

int main( int argc, const char *argv[] ) {

    @autoreleasepool {

        if ( argc < 2 )
            DError( "must be run with a script name\n" );

        NSString *home = [NSString stringWithUTF8String:getenv("HOME")];
        libraryRoot = [home stringByAppendingPathComponent:@"Library/Diamond"];

        // diamond is called twice. Once to execute the "guardian" framework
        // and once with the first argument run: to run the actual script.
        // The guardian process watches for traps in the child process and
        // processes the generated crash report to display the line number
        // the script failed in a full symbolicated, demagled stack trace.
        const char *childIndicator = "run:";
        BOOL isChild = strcmp( argv[1], childIndicator ) == 0;
        BOOL isRestarter = strcmp( argv[argc-1], "-restarter" ) == 0;

        const char **childArgv = argv + 2;
        NSString *ldFlags = isChild ? extractLDFlags( &childArgv ) : @"";

        NSString *script = isChild ? [NSString stringWithUTF8String:*childArgv] :
            [libraryRoot stringByAppendingPathComponent:@"Resources/guardian"];
        NSString *lastArg = isChild && argv[argc-1][0] == '-' ? [NSString stringWithUTF8String:argv[argc-1]] : @"";

        // find the actual script path using $PATH from the environment.
        NSString *scriptPath = locateScriptInPath( script, home );

        char quarantineAttr[] = "com.apple.quarantine", attrValue[PATH_MAX];
        if ( getxattr( [scriptPath UTF8String], quarantineAttr, attrValue, sizeof attrValue, 0, 0 ) >= 0 )
            DError( "Script has quarantine attribute set and can not be run.\nDownloaded by: %s\n"
                    "Use: xattr -d %s %@ if you are sure.\n", attrValue, quarantineAttr, scriptPath );

        // remove extension from last path component to find framework name
        scriptName = [[script lastPathComponent] stringByDeletingPathExtension];

        // find path to "hidden" or "shown" .scriptproj shadow Xcode project for editing/building
        NSString *scriptProject = [scriptPath stringByAppendingString:@".scriptproj"];
        if ( ![[NSFileManager defaultManager] fileExistsAtPath:scriptProject] )
            scriptProject = [NSString stringWithFormat:@"%@/Projects/%@", libraryRoot, scriptName];

        // Call compile.rb to build script into framework (or binary.dme if extension is .dmd.)
        // Makes sure project is built if any frameworks it is dependant on are rebuilt recursively.
        NSString *compileCommand = [NSString stringWithFormat:@"%@/Resources/prepare.rb \"%@\" \"%@\" \"%@\" \"%@\" \"%@\" \"%@\"",
                                    libraryRoot, libraryRoot, scriptPath, scriptName, scriptProject, ldFlags, lastArg];

        int status;
    restart:
        // call compile.rb to prepare Frameworks/Binary
        status = system( [compileCommand UTF8String] );

        // user option such as -edit, -show, -hide, -rebuild, -reclone
        if ( status >> 8 == 123 )
            exit( 0 );

        // compilation error
        if ( status >> 8 == 124 )
            exit( 1 );

        if ( status != EXIT_SUCCESS )
            DError( "%@ returns error %d\n", compileCommand, status>>8 );

        savedHandler = signal( SIGINT, ensureChildExits );

        if ( !isChild ) {

            setenv( "DIAMOND_LIBRARY_ROOT", [libraryRoot UTF8String], 1 );
            setenv( "DIAMOND_PROJECT_ROOT", [scriptProject UTF8String], 1 );

            // This is where actual script is run as a child process leaving the
            // guardian framework monitoring it for traps/crashes to dump .crash
            if ( (childPid = fork()) == 0 ) {

                const char **shiftedArgv = calloc( argc+3, sizeof *shiftedArgv );
                shiftedArgv[0] = "/usr/bin/env";
                shiftedArgv[1] = argv[0]; // "diamond";
                shiftedArgv[2] = childIndicator; // run:
                for ( int i=1 ; i<=argc ; i++ )
                    shiftedArgv[i+2] = argv[i];

                execv( shiftedArgv[0], (char *const *)shiftedArgv );
                DError( "execv failed\n" );
            }

            // ENV["DIAMOND_CHILD_PID"] for guardian framework main() is process id of child process.
            argv[0] = [[NSString stringWithFormat:@"%d", childPid] UTF8String];
            setenv( "DIAMOND_CHILD_PID", argv[0], 1 );

            // run the guardian script's .framework
            status = execFramework( scriptName, argc, argv );

            // restart on crash
            if ( isRestarter )
                goto restart;
        }

        else if ( isChild ) {
            if ( isRestarter )
                argv[--argc] = NULL;

            argv[2] = [scriptPath UTF8String];

            // This code relates to ".dme" binaries used as an alternative to frameworks
            if ( [scriptPath hasSuffix:@".dmd"] ) {

                // execv binary in child process if present (and there is run: argument.)
                NSString *binaryPath = [NSString stringWithFormat:@"%@/bin/%@.dme", home, scriptName];
                if ( [[NSFileManager defaultManager] isExecutableFileAtPath:binaryPath] )
                    execv( [binaryPath UTF8String], (char *const *)argv+2 );

                DError( "Unable to execute %@: %s\n", binaryPath, strerror(errno) );
            }

            // If running actual script in child process,
            // start file watcher for code reloading.
            watchProject( scriptProject );

            // run the actual script .framework
            status = execFramework( scriptName, argc-(int)(childArgv-argv), childArgv );

            if ( fileEvents ) {
                FSEventStreamStop( fileEvents );
                FSEventStreamInvalidate( fileEvents );
                FSEventStreamRelease( fileEvents );
            }
        }

        exit( status );
    }
}

static NSString *extractLDFlags( const char **argv[] ) {
    NSMutableString *ldFlags = [NSMutableString new];
    while ( **argv ) {
        if ( strcmp( **argv, "-L" ) == 0 || strcmp( **argv, "-F" ) == 0 || strcmp( **argv, "-framework" ) == 0 ) {
            [ldFlags appendFormat:@"					\\\"%s\\\",\n", *(*argv)++];
            if ( **argv )
                [ldFlags appendFormat:@"					\\\"%@\\\",\n", [NSString stringWithUTF8String:*(*argv)++]];
        }
        else if ( strcmp( **argv, "-Xlinker" ) == 0 ) {
            if ( *++(*argv) )
                [ldFlags appendFormat:@"					\\\"%@\\\",\n", [NSString stringWithUTF8String:*(*argv)++]];
        }
        else if ( strncmp( **argv, "-l", 2 ) == 0 ) {
            [ldFlags appendFormat:@"					\\\"%@\\\",\n", [NSString stringWithUTF8String:*(*argv)++]];
        }
        else
            break;
    }
    return ldFlags;
}

static NSString *locateScriptInPath( NSString *script, NSString *home ) {
    NSString *path = [NSString stringWithUTF8String:getenv("PATH")];
    path = [path stringByAppendingFormat:@":%@/bin", home];
    setenv( "PATH", [path UTF8String], 1 );

    NSString *scriptPath = script, *mainPath = [script stringByAppendingString:@".scriptproj/main.swift"];

    if ( [scriptPath characterAtIndex:0] != '/' && ![scriptPath hasPrefix:@"./"] ) {
        NSFileManager *manager = [NSFileManager defaultManager];

        for ( NSString *component in [path componentsSeparatedByString:@":"] ) {
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
    }

    if ( [scriptPath characterAtIndex:0] == '.' ) {
        char cwd[PATH_MAX];
        NSString *cwdStr = [NSString stringWithUTF8String:getcwd( cwd, sizeof cwd )];
        if ( [scriptPath hasPrefix:@"./"] )
            scriptPath = [scriptPath substringFromIndex:2];
        scriptPath = [cwdStr stringByAppendingPathComponent:scriptPath];
    }

    return scriptPath;
}

static int execFramework( NSString *scriptName, int argc, const char **argv ) {
    // Now look for Framework with the script's name determined before and load it as a bundle.
    NSString *frameworkPath = [NSString stringWithFormat:@"%@/Frameworks/%@.framework",
                               libraryRoot, scriptName];
    NSBundle *frameworkBundle = [NSBundle bundleWithPath:frameworkPath];

    if ( !frameworkBundle )
        DError( "Could not locate binary or framework bundle %@\n", frameworkPath );

    if ( ![frameworkBundle load] )
        DError( "Could not load framework bundle %@\n", frameworkBundle );

    // Slight hack to get CFBundle from NSBundle so we can locate main function in main.swift
    CFBundleRef cfBundle = (__bridge CFBundleRef)[frameworkBundle valueForKey:@"cfBundle"];

    if ( !cfBundle )
        DError( "Could not access CFBundle %@\n", frameworkBundle );

    // find pointer to main( argc, argv )
    // ..can be guardian or actual script.
    typedef int (*main_t)( int argc, const char * argv[] );
    main_t scriptMain = (main_t)CFBundleGetFunctionPointerForName( cfBundle, (CFStringRef)@"main" );

    if ( !scriptMain )
        DError( "Could not locate main() function in %@\n", frameworkBundle );

    int status = 1;
    @try {
        // run guardian or script in child process.
        *_NSGetArgc() = argc;
        *_NSGetArgv() = (char **)argv;
        status = scriptMain( argc, argv );
    }
    @catch ( NSException *e ) {
        NSLog( @"diamond: Uncaught exception %@\n%@", e, e.callStackSymbols );
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

#pragma clang diagnostic pop
