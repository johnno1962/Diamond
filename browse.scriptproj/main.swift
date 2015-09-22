#!/usr/bin/env safescript
//
//  main.swift
//  TemplateProject
//
//  Created by John Holdsworth on 18/09/2015.
//  Copyright © 2015 John Holdsworth. All rights reserved.
//

import Foundation
import Cocoa

if Process.arguments.count < 2 {
    print( "Please specify URL" )
    exit(0)
}

NSApplicationMain( 0,  UnsafeMutablePointer<UnsafeMutablePointer<CChar>>(nil) )
