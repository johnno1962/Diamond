//
//  main.m
//  SwiftScript
//
//  Created by John Holdsworth on 18/09/2015.
//  Copyright © 2015 John Holdsworth. All rights reserved.
//
//  $Id: //depot/SwiftScript/SwiftScript/main.m#3 $
//
//  Repo: https://github.com/johnno1962/SwiftScript
//

#import <Foundation/Foundation.h>

int main(int argc, const char * argv[]) {

    @autoreleasepool {
        NSString *script = [NSString stringWithUTF8String:argv[1]];
        BOOL isEdit = argc>2 ? strcmp( argv[argc-1], "-edit" ) == 0 : 0;

        NSString *scriptName = [[script lastPathComponent] stringByDeletingPathExtension];
        NSString *swiftScriptRoot = [[NSString stringWithUTF8String:getenv("HOME")]
                                     stringByAppendingPathComponent:@"Library/SwiftScript"];
        NSString *prepareCommand = [NSString stringWithFormat:@"%@/Resources/prepare.rb '%@' '%@' '%@' %d",
                                    swiftScriptRoot, script, scriptName, swiftScriptRoot, isEdit];

        int status = system( [prepareCommand UTF8String] ) >> 8;

        if ( isEdit )
            exit(0);

        if ( status != 0 ) {
            NSLog( @"%@ returns error", prepareCommand );
            exit( status );
        }

        NSString *frameworkPath = [NSString stringWithFormat:@"%@/Frameworks/%@.framework",
                                   swiftScriptRoot, scriptName];

        NSBundle *frameworkBundle = [NSBundle bundleWithPath:frameworkPath];
        [frameworkBundle load];

        CFBundleRef cfBundle = (__bridge CFBundleRef)[frameworkBundle valueForKey:@"cfBundle"];

        if ( !cfBundle ) {
            NSLog( @"Could not load framemork bundle %@", frameworkPath );
            exit(1);
        }

        typedef int (*main_t)(int argc, const char * argv[]);
        main_t scriptMain = (main_t)CFBundleGetFunctionPointerForName( cfBundle, (CFStringRef)@"main" );

        if ( !scriptMain ) {
            NSLog( @"Could not locate main() function in %@", frameworkBundle );
            exit(1);
        }

        @try {
            exit( scriptMain( argc-1, argv+1 ) );
        }
        @catch ( NSException *e ) {
            NSLog( @"Exception: %@\n%@", e, e.callStackSymbols );
        }
    }

    return 0;
}
