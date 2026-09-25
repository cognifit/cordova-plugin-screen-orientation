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

#import "CDVOrientation.h"
#import "CDVViewController+CDVOrientation.h"
#import <Cordova/CDVViewController.h>

// Values sent by www/screenorientation.js (window.OrientationLockType).
typedef NS_OPTIONS(NSInteger, CDVOrientationLockType) {
    CDVOrientationLockPortraitPrimary    = 1,
    CDVOrientationLockPortraitSecondary  = 2,
    CDVOrientationLockLandscapePrimary   = 4,
    CDVOrientationLockLandscapeSecondary = 8,
    CDVOrientationLockAny                = 15
};

static UIInterfaceOrientationMask CDVOrientationMaskFromLockType(NSInteger lockType)
{
    UIInterfaceOrientationMask mask = 0;
    if (lockType & CDVOrientationLockPortraitPrimary)    mask |= UIInterfaceOrientationMaskPortrait;
    if (lockType & CDVOrientationLockPortraitSecondary)  mask |= UIInterfaceOrientationMaskPortraitUpsideDown;
    // Same mapping as the original plugin: landscape-primary is the interface
    // orientation LandscapeRight (window.orientation == 90).
    if (lockType & CDVOrientationLockLandscapePrimary)   mask |= UIInterfaceOrientationMaskLandscapeRight;
    if (lockType & CDVOrientationLockLandscapeSecondary) mask |= UIInterfaceOrientationMaskLandscapeLeft;
    return mask;
}

@implementation CDVOrientation {
    // Set by doNotAutorotateOnNextUpdate, consumed by the next unlock.
    BOOL _skipRotationOnNextUnlock;
    // An unlock is waiting for the user to physically rotate the device.
    BOOL _pendingUnlock;
    UIDeviceOrientation _deviceOrientationAtUnlock;
    BOOL _observingDevice;
}

- (void)pluginInitialize
{
    _skipRotationOnNextUnlock = NO;
    _pendingUnlock = NO;
}

- (void)dispose
{
    [self stopObservingDevice];
    [super dispose];
}

#pragma mark - JS API

- (void)screenOrientation:(CDVInvokedUrlCommand*)command
{
    NSInteger lockType = [[command argumentAtIndex:0 withDefault:@(CDVOrientationLockAny)] integerValue];
    NSString* callbackId = command.callbackId;

    void (^work)(void) = ^{
        CDVPluginResult* result = [self applyLockType:lockType];
        [self.commandDelegate sendPluginResult:result callbackId:callbackId];
    };

    if ([NSThread isMainThread]) {
        work();
    } else {
        dispatch_async(dispatch_get_main_queue(), work);
    }
}

- (void)doNotAutorotateOnNextUpdate:(CDVInvokedUrlCommand*)command
{
    _skipRotationOnNextUnlock = YES;
    [self.commandDelegate sendPluginResult:[CDVPluginResult resultWithStatus:CDVCommandStatus_OK]
                                callbackId:command.callbackId];
}

#pragma mark - Implementation

- (CDVPluginResult*)applyLockType:(NSInteger)lockType
{
    if (![self.viewController isKindOfClass:[CDVViewController class]]) {
        return [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR
                                 messageAsString:@"CDVOrientation: no CDVViewController available"];
    }
    CDVViewController* vc = (CDVViewController*)self.viewController;

    UIInterfaceOrientationMask mask = CDVOrientationMaskFromLockType(lockType);
    if (mask == 0) {
        return [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR
                                 messageAsString:[NSString stringWithFormat:@"CDVOrientation: invalid orientation mask %ld", (long)lockType]];
    }

    if (lockType == CDVOrientationLockAny) {
        [self unlockViewController:vc];
    } else {
        [self lockViewController:vc toMask:mask];
    }
    return [CDVPluginResult resultWithStatus:CDVCommandStatus_OK];
}

- (void)lockViewController:(CDVViewController*)vc toMask:(UIInterfaceOrientationMask)mask
{
    // A new lock cancels any unlock that was waiting for a device rotation.
    [self cancelPendingUnlock];

    [vc cdvo_setLockedOrientationMask:mask];
    // Tell UIKit the supported orientations changed (replaces the deprecated
    // +[UIViewController attemptRotationToDeviceOrientation]).
    [vc setNeedsUpdateOfSupportedInterfaceOrientations];

    UIWindowScene* scene = [self windowSceneForViewController:vc];
    if (scene == nil) {
        // Not attached to a scene yet: the stored mask will be honoured as soon
        // as the view controller is shown.
        return;
    }

    UIInterfaceOrientation current = scene.effectiveGeometry.interfaceOrientation;
    BOOL currentIsAllowed = current != UIInterfaceOrientationUnknown && (mask & (1 << current)) != 0;
    if (currentIsAllowed) {
        // Already in an allowed orientation: do not rotate (this avoids the
        // "double rotation"/180° flip when locking to 'landscape' while already
        // in landscape).
        return;
    }

    UIWindowSceneGeometryPreferencesIOS* prefs =
        [[UIWindowSceneGeometryPreferencesIOS alloc] initWithInterfaceOrientations:mask];
    [scene requestGeometryUpdateWithPreferences:prefs errorHandler:^(NSError* _Nonnull error) {
        // On iPad this fails when the app runs in a resizable window / multitasking.
        NSLog(@"[CDVOrientation] requestGeometryUpdate failed: %@", error);
    }];
}

- (void)unlockViewController:(CDVViewController*)vc
{
    BOOL skipRotation = _skipRotationOnNextUnlock;
    _skipRotationOnNextUnlock = NO;

    if ([vc cdvo_lockedOrientationMask] == 0) {
        // Nothing locked.
        [self cancelPendingUnlock];
        return;
    }

    if (skipRotation) {
        // Keep the current lock until the user physically rotates the device,
        // so the interface does not jump back to the device orientation now.
        _pendingUnlock = YES;
        _deviceOrientationAtUnlock = [UIDevice currentDevice].orientation;
        [self startObservingDevice];
        return;
    }

    [self cancelPendingUnlock];
    [vc cdvo_setLockedOrientationMask:0];
    [vc setNeedsUpdateOfSupportedInterfaceOrientations];
}

- (UIWindowScene*)windowSceneForViewController:(UIViewController*)vc
{
    UIWindowScene* scene = vc.viewIfLoaded.window.windowScene;
    if (scene != nil) {
        return scene;
    }

    UIWindowScene* fallback = nil;
    for (UIScene* s in UIApplication.sharedApplication.connectedScenes) {
        if (![s isKindOfClass:[UIWindowScene class]]) continue;
        if (s.activationState == UISceneActivationStateForegroundActive) {
            return (UIWindowScene*)s;
        }
        if (fallback == nil) fallback = (UIWindowScene*)s;
    }
    return fallback;
}

#pragma mark - Deferred unlock (doNotAutorotateOnNextUpdate)

- (void)startObservingDevice
{
    if (_observingDevice) return;
    _observingDevice = YES;
    [[UIDevice currentDevice] beginGeneratingDeviceOrientationNotifications];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(deviceOrientationDidChange:)
                                                 name:UIDeviceOrientationDidChangeNotification
                                               object:nil];
}

- (void)stopObservingDevice
{
    if (!_observingDevice) return;
    _observingDevice = NO;
    [[NSNotificationCenter defaultCenter] removeObserver:self
                                                    name:UIDeviceOrientationDidChangeNotification
                                                  object:nil];
    [[UIDevice currentDevice] endGeneratingDeviceOrientationNotifications];
}

- (void)cancelPendingUnlock
{
    _pendingUnlock = NO;
    [self stopObservingDevice];
}

- (void)deviceOrientationDidChange:(NSNotification*)notification
{
    if (!_pendingUnlock) return;

    UIDeviceOrientation device = [UIDevice currentDevice].orientation;
    // Ignore face up / face down / unknown and "no real change".
    if (!UIDeviceOrientationIsValidInterfaceOrientation(device) || device == _deviceOrientationAtUnlock) {
        return;
    }

    [self cancelPendingUnlock];
    if ([self.viewController isKindOfClass:[CDVViewController class]]) {
        CDVViewController* vc = (CDVViewController*)self.viewController;
        [vc cdvo_setLockedOrientationMask:0];
        [vc setNeedsUpdateOfSupportedInterfaceOrientations];
    }
}

@end
