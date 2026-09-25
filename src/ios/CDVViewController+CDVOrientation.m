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

#import <Cordova/CDVViewController.h>
#import <objc/runtime.h>
#import "CDVViewController+CDVOrientation.h"

static char kCDVOrientationLockedMaskKey;

@implementation CDVViewController (CDVOrientation)

- (UIInterfaceOrientationMask)cdvo_lockedOrientationMask
{
    NSNumber* mask = objc_getAssociatedObject(self, &kCDVOrientationLockedMaskKey);
    return (UIInterfaceOrientationMask)mask.unsignedIntegerValue;
}

- (void)cdvo_setLockedOrientationMask:(UIInterfaceOrientationMask)mask
{
    objc_setAssociatedObject(self, &kCDVOrientationLockedMaskKey,
                             mask == 0 ? nil : @(mask),
                             OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

/*
 * cordova-ios 8 removed CDVViewController's supportedOrientations handling, so
 * CDVViewController no longer overrides -supportedInterfaceOrientations and
 * UIKit's default is used (all-but-upside-down on iPhone, all on iPad, always
 * intersected with the Info.plist UISupportedInterfaceOrientations).
 *
 * We install our own -supportedInterfaceOrientations on CDVViewController:
 *  - when the plugin has a lock stored on the instance, return it;
 *  - otherwise forward to whatever implementation was there before
 *    (UIViewController's default on cordova-ios 8, CDVViewController's own
 *    implementation on cordova-ios 7).
 *
 * If the app's MainViewController/ViewController subclass overrides
 * -supportedInterfaceOrientations itself, that override wins and the plugin
 * cannot lock the orientation (same as with any other orientation plugin).
 */
+ (void)load
{
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        Class cls = [CDVViewController class];
        SEL sel = @selector(supportedInterfaceOrientations);
        Method inherited = class_getInstanceMethod(cls, sel);
        const char* types = method_getTypeEncoding(inherited);

        __block IMP previousIMP = method_getImplementation(inherited);

        IMP newIMP = imp_implementationWithBlock(^UIInterfaceOrientationMask(CDVViewController* vc) {
            UIInterfaceOrientationMask locked = [vc cdvo_lockedOrientationMask];
            if (locked != 0) {
                return locked;
            }
            return ((UIInterfaceOrientationMask (*)(id, SEL))previousIMP)(vc, sel);
        });

        // Adds the method only if CDVViewController itself does not implement it
        // (cordova-ios 8). previousIMP is then UIViewController's implementation.
        if (!class_addMethod(cls, sel, newIMP, types)) {
            // CDVViewController implements it itself (cordova-ios 7): wrap it.
            previousIMP = method_setImplementation(class_getInstanceMethod(cls, sel), newIMP);
        }
    });
}

@end
