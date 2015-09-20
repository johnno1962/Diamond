//
//  main.m
//  SafeScript
//
//  Created by John Holdsworth on 18/09/2015.
//  Copyright © 2015 John Holdsworth. All rights reserved.
//
//  $Id: //depot/SafeScript/SafeScript/main.m#7 $
//
//  Repo: https://github.com/johnno1962/SafeScript
//

#import <Foundation/Foundation.h>

#define SError( ... ) { NSLog( @"SafeScript: " __VA_ARGS__ ); exit( EXIT_FAILURE ); }

static void watchProject( NSString *scriptName );
static NSString *libraryRoot, *scriptName;
static FSEventStreamRef fileEvents;

int main(int argc, const char * argv[]) {

    @autoreleasepool {

        if ( argc < 2 )
            SError( "%s must be run from a script", argv[0] );

        NSString *script = [NSString stringWithUTF8String:argv[1]];
        BOOL isRebuild = strcmp( argv[argc-1], "-rebuild" ) == 0;
        BOOL isEdit = strcmp( argv[argc-1], "-edit" ) == 0;

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

        libraryRoot = [[NSString stringWithUTF8String:getenv("HOME")]
                           stringByAppendingPathComponent:@"Library/SafeScript"];
        scriptName = [[script lastPathComponent] stringByDeletingPathExtension];

        NSString *scriptProject = [[scriptPath stringByDeletingLastPathComponent]
                                   stringByAppendingPathComponent:[NSString stringWithFormat:@"%@.scriptproj", [script lastPathComponent]]];
        NSString *prepareCommand = [NSString stringWithFormat:@"%@/Resources/prepare.rb '%@' '%@' '%@' '%@' %d %d",
                                    libraryRoot, libraryRoot, scriptPath, scriptName, scriptProject, isRebuild, isEdit];

        int status = system( [prepareCommand UTF8String] ) >> 8;

        if ( status != EXIT_SUCCESS )
            SError( "%@ returns error", prepareCommand );

        if ( isEdit || isRebuild )
            exit(0);

        NSString *frameworkPath = [NSString stringWithFormat:@"%@/Frameworks/%@.framework",
                                   libraryRoot, scriptName];
        NSBundle *frameworkBundle = [NSBundle bundleWithPath:frameworkPath];

        if ( !frameworkBundle )
            SError( "Could not create framemork bundle %@", frameworkPath );

        if ( ![frameworkBundle load] )
            SError( "Could not load framemork bundle %@", frameworkBundle );

        CFBundleRef cfBundle = (__bridge CFBundleRef)[frameworkBundle valueForKey:@"cfBundle"];

        if ( !cfBundle )
            SError( "Could not access CFBundle %@", frameworkBundle );

        typedef int (*main_t)(int argc, const char * argv[]);
        main_t scriptMain = (main_t)CFBundleGetFunctionPointerForName( cfBundle, (CFStringRef)@"main" );

        if ( !scriptMain )
            SError( "Could not locate main() function in %@", frameworkBundle );

        @try {
            watchProject( scriptProject );
            status = scriptMain( argc-1, argv+1 );
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

    if ( ![fileChanged hasSuffix:@".swift"] )
        return;

    static int busy;
    if ( !busy++ ) {

        static int reloadNumber;
        NSString *bundlePath = [NSString stringWithFormat:@"/tmp/Reloader%d.bundle", reloadNumber++];
        NSString *reloadCommand = [NSString stringWithFormat:@"%@/Resources/reloader.rb '%@' '%@' '%@' '%@'",
                                   libraryRoot, libraryRoot, scriptName, fileChanged, bundlePath];

        int status = system( [reloadCommand UTF8String] ) >> 8;

        if ( status != EXIT_SUCCESS )
            NSLog( @"SafeScript: %@ returns error", reloadCommand );
        else if ( ![[NSBundle bundleWithPath:bundlePath] load] )
            NSLog( @"SafeScript: Could not reload bundle: %@", bundlePath );
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
