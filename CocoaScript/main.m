//
//  main.m
//  CocoaScript
//
//  Created by John Holdsworth on 18/09/2015.
//  Copyright © 2015 John Holdsworth. All rights reserved.
//
//  $Id: //depot/CocoaScript/CocoaScript/main.m#2 $
//
//  Repo: https://github.com/johnno1962/CocoaScript
//

#import <Foundation/Foundation.h>

#define SError( ... ) { NSLog( @"cocoa: " __VA_ARGS__ ); exit( EXIT_FAILURE ); }

static void watchProject( NSString *scriptName );
static NSString *libraryRoot, *scriptName;
static FSEventStreamRef fileEvents;

int main( int argc, const char * argv[] ) {

    @autoreleasepool {

        if ( argc < 2 )
            SError( "%s must be run from a script", argv[0] );

        NSString *home = [NSString stringWithUTF8String:getenv("HOME")];
        libraryRoot = [home stringByAppendingPathComponent:@"Library/CocoaScript"];

        const char *runIndicator = "running:";
        BOOL isRun = strcmp( argv[1], runIndicator ) == 0;
        NSString *script = isRun ? [NSString stringWithUTF8String:argv[2]] :
            [NSString stringWithFormat:@"%@/Resources/guardian", libraryRoot];
        NSString *lastArg = isRun && argv[argc-1][0] == '-' ? [NSString stringWithUTF8String:argv[argc-1]] : @"";

        NSString *scriptPath = script;
        NSFileManager *manager = [NSFileManager defaultManager];

        unichar path0 = [scriptPath characterAtIndex:0];
        if ( path0 != '/' && path0 != '.' )
            for ( NSString *component in [[NSString stringWithUTF8String:getenv("PATH")] componentsSeparatedByString:@":"] ) {
                NSString *result = [component stringByAppendingPathComponent:script];
                if ( [manager fileExistsAtPath:result] ) {
                    scriptPath = result;
                    break;
                }
            }

        scriptName = [[script lastPathComponent] stringByDeletingPathExtension];

        NSString *scriptProject = [scriptPath stringByAppendingString:@".scriptproj"];
        if ( ![manager fileExistsAtPath:scriptProject] )
            scriptProject = [[libraryRoot stringByAppendingPathComponent:@"Projects"]
                             stringByAppendingPathComponent:scriptName];

        NSString *prepareCommand = [NSString stringWithFormat:@"%@/Resources/prepare.rb \"%@\" \"%@\" \"%@\" \"%@\" \"%@\"",
                                    libraryRoot, libraryRoot, scriptPath, scriptName, scriptProject, lastArg];

        int status = system( [prepareCommand UTF8String] );

        if ( status >> 8 == 123 )
            exit( 0 );
        if ( status != EXIT_SUCCESS )
            SError( "%@ returns error %x", prepareCommand, status );

        setenv( "COCOA_LIBRARY_ROOT", strdup( [libraryRoot UTF8String] ), 1 );
        setenv( "COCOA_PROJECT_ROOT", strdup( [scriptProject UTF8String] ), 1 );
        argv[0] = strdup( [scriptPath UTF8String] );

        NSString *binaryPath = [NSString stringWithFormat:@"%@/bin/%@", home, scriptName];
        if ( [[NSFileManager defaultManager] isExecutableFileAtPath:binaryPath] &&
                execv( [binaryPath UTF8String], (char *const *)argv+2 ) )
            SError( "Unable to execute %@: %s", binaryPath, strerror(errno) );

        if ( !isRun ) {
            pid_t pid;
            if ( !(pid = fork()) ) {
                const char **shiftedArgv = calloc( argc+2, sizeof *shiftedArgv );
                shiftedArgv[0] = "/usr/bin/env";
                shiftedArgv[1] = "cocoa";
                shiftedArgv[2] = runIndicator;
                for ( int i=1 ; i<=argc ; i++ )
                    shiftedArgv[i+2] = argv[i];
                execv( shiftedArgv[0], (char *const *)shiftedArgv );
                SError( "execve failed" );
            }

            argv[0] = [[NSString stringWithFormat:@"%d", pid] UTF8String];
        }

        NSString *frameworkPath = [NSString stringWithFormat:@"%@/Frameworks/%@.framework",
                                   libraryRoot, scriptName];
        NSBundle *frameworkBundle = [NSBundle bundleWithPath:frameworkPath];

        if ( !frameworkBundle )
            SError( "Could not locate binary or framemork bundle %@", frameworkPath );

        if ( ![frameworkBundle load] )
            SError( "Could not load framemork bundle %@", frameworkBundle );

        CFBundleRef cfBundle = (__bridge CFBundleRef)[frameworkBundle valueForKey:@"cfBundle"];

        if ( !cfBundle )
            SError( "Could not access CFBundle %@", frameworkBundle );

        typedef int (*main_t)(int argc, const char * argv[]);
        main_t scriptMain = (main_t)CFBundleGetFunctionPointerForName( cfBundle, (CFStringRef)@"main" );

        if ( !scriptMain )
            SError( "Could not locate main() function in %@", frameworkBundle );

        if ( isRun )
            watchProject( scriptProject );

        @try {
            status = scriptMain( argc-isRun*2, argv+isRun*2 );
        }
        @catch ( NSException *e ) {
            SError( "Exception %@\n%@", e, e.callStackSymbols );
        }

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
