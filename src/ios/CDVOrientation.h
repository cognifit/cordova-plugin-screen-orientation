/*
 *
 * Licensed to the Apache Software Foundation (ASF) under one
 * or more contributor license agreements.  See the NOTICE file
 * distributed with this work for additional information
 * regarding copyright ownership.  The ASF licenses this file
 * to you under the Apache License, Version 2.0 (the
 * "License"); you may not use this file except in compliance
 * with the License.  You may obtain a copy of the License at
 *
 *   http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing,
 * software distributed under the License is distributed on an
 * "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY
 * KIND, either express or implied.  See the License for the
 * specific language governing permissions and limitations
 * under the License.
 *
 */

#import <Cordova/CDVPlugin.h>
#import <UIKit/UIKit.h>

/**
 * CogniFit fork of cordova-plugin-screen-orientation (iOS side).
 *
 * Requirements: iOS 16+ APIs only (deployment target 17.0), scene-based app
 * lifecycle (cordova-ios >= 8). Also works with cordova-ios 7.
 *
 * The allowed orientations are stored on the CDVViewController instance and
 * returned from -supportedInterfaceOrientations (see
 * CDVViewController+CDVOrientation.m), because cordova-ios 8 removed the old
 * CDVViewController -setSupportedOrientations: API this plugin relied on.
 */
@interface CDVOrientation : CDVPlugin

/// args[0]: OrientationLockType bitmask coming from www/screenorientation.js
/// (1 portrait-primary, 2 portrait-secondary, 4 landscape-primary,
///  8 landscape-secondary, 3 portrait, 12 landscape, 15 any/unlock).
- (void)screenOrientation:(CDVInvokedUrlCommand*)command;

/// The next *unlock* ('any') will not rotate the interface to the device's
/// physical orientation right away; the unlock takes effect the next time the
/// user physically rotates the device.
- (void)doNotAutorotateOnNextUpdate:(CDVInvokedUrlCommand*)command;

@end
