//
//  TGMapViewController.mm
//  TangramMap
//
//  Created by Matt Blair on 8/25/14.
//  Updated by Matt Smollinger on 7/29/16.
//  Updated by Karim Naaji on 2/15/17.
//  Copyright (c) 2017 Mapzen. All rights reserved.
//

#import "TGMapViewController.h"
#import "TGHelpers.h"
#import "platform_ios.h"
#import "data/propertyItem.h"
#import "tangram.h"

#import <functional>

__CG_STATIC_ASSERT(sizeof(TGMapMarkerId) == sizeof(Tangram::MarkerID));
__CG_STATIC_ASSERT(sizeof(TGGeoPoint) == sizeof(Tangram::LngLat));

@interface TGMapViewController ()

@property (nullable, copy, nonatomic) NSString* scenePath;
@property (nullable, strong, nonatomic) EAGLContext* context;
@property (assign, nonatomic) CGFloat contentScaleFactor;
@property (assign, nonatomic) BOOL renderRequested;
@property (assign, nonatomic, nullable) Tangram::Map* map;

@end

@implementation TGMapViewController

- (void)setDebugFlag:(TGDebugFlag)debugFlag value:(BOOL)on
{
    Tangram::setDebugFlag((Tangram::DebugFlags)debugFlag, on);
}

- (BOOL)getDebugFlag:(TGDebugFlag)debugFlag
{
    return Tangram::getDebugFlag((Tangram::DebugFlags)debugFlag);
}

- (void)toggleDebugFlag:(TGDebugFlag)debugFlag
{
    Tangram::toggleDebugFlag((Tangram::DebugFlags)debugFlag);
}

#pragma mark Scene loading interface

- (void)loadSceneFile:(NSString*)path
{
    [self loadSceneFile:path sceneUpdates:nil];
}

- (void)loadSceneFileAsync:(NSString*)path
{
    [self loadSceneFileAsync:path sceneUpdates:nil];
}

- (void)loadSceneFile:(NSString *)path sceneUpdates:(NSArray<TGSceneUpdate *> *)sceneUpdates
{
    if (!self.map) { return; }

    std::vector<Tangram::SceneUpdate> updates;

    if (sceneUpdates) {
        for (TGSceneUpdate* update in sceneUpdates) {
            updates.push_back({std::string([update.path UTF8String]), std::string([update.value UTF8String])});
        }
    }

    self.scenePath = path;
    self.map->loadScene([path UTF8String], false, updates);
    self.renderRequested = YES;
}

- (void)loadSceneFileAsync:(NSString *)path sceneUpdates:(NSArray<TGSceneUpdate *> *)sceneUpdates
{
    if (!self.map) { return; }

    self.scenePath = path;

    MapReady onReadyCallback = [self, path](void* _userPtr) -> void {
        if (self.mapViewDelegate && [self.mapViewDelegate respondsToSelector:@selector(mapView:didLoadSceneAsync:)]) {
            [self.mapViewDelegate mapView:self didLoadSceneAsync:path];
        }

        self.renderRequested = YES;
    };

    std::vector<Tangram::SceneUpdate> updates;

    if (sceneUpdates) {
        for (TGSceneUpdate* update in sceneUpdates) {
            updates.push_back({std::string([update.path UTF8String]), std::string([update.value UTF8String])});
        }
    }

    self.map->loadSceneAsync([path UTF8String], false, onReadyCallback, nullptr, updates);
}

#pragma mark Scene updates

- (void)queueSceneUpdates:(NSArray<TGSceneUpdate *> *)sceneUpdates
{
    if (!self.map) { return; }

    std::vector<Tangram::SceneUpdate> updates;

    if (sceneUpdates) {
        for (TGSceneUpdate* update in sceneUpdates) {
            updates.push_back({std::string([update.path UTF8String]), std::string([update.value UTF8String])});
        }
    }

    self.map->queueSceneUpdate(updates);
}

- (void)queueSceneUpdate:(NSString*)componentPath withValue:(NSString*)value
{
    if (!self.map) { return; }

    self.map->queueSceneUpdate([componentPath UTF8String], [value UTF8String]);
}

- (void)applySceneUpdates
{
    if (!self.map) { return; }

    self.map->applySceneUpdates();
}

#pragma mark Longitude/Latitude - Screen position conversions

- (CGPoint)lngLatToScreenPosition:(TGGeoPoint)lngLat
{
    static const CGPoint nullCGPoint = {(CGFloat)NAN, (CGFloat)NAN};

    if (!self.map) { return nullCGPoint; }

    double screenPosition[2];
    if (self.map->lngLatToScreenPosition(lngLat.longitude, lngLat.latitude,
        &screenPosition[0], &screenPosition[1])) {

        screenPosition[0] /= self.contentScaleFactor;
        screenPosition[1] /= self.contentScaleFactor;

        return CGPointMake((CGFloat)screenPosition[0], (CGFloat)screenPosition[1]);
    }

    return nullCGPoint;
}

- (TGGeoPoint)screenPositionToLngLat:(CGPoint)screenPosition
{
    static const TGGeoPoint nullTangramGeoPoint = {NAN, NAN};

    if (!self.map) { return nullTangramGeoPoint; }

    screenPosition.x *= self.contentScaleFactor;
    screenPosition.y *= self.contentScaleFactor;

    TGGeoPoint lngLat;
    if (self.map->screenPositionToLngLat(screenPosition.x, screenPosition.y,
        &lngLat.longitude, &lngLat.latitude)) {
        return lngLat;
    }

    return nullTangramGeoPoint;
}

#pragma mark Feature picking

- (void)setPickRadius:(float)logicalPixels
{
    if (!self.map) { return; }

    self.map->setPickRadius(logicalPixels);
}

- (void)pickFeatureAt:(CGPoint)screenPosition
{
    if (!self.map) { return; }

    screenPosition.x *= self.contentScaleFactor;
    screenPosition.y *= self.contentScaleFactor;

    self.map->pickFeatureAt(screenPosition.x, screenPosition.y, [screenPosition, self](const Tangram::FeaturePickResult* featureResult) {
        if (!self.mapViewDelegate || ![self.mapViewDelegate respondsToSelector:@selector(mapView:didSelectFeature:atScreenPosition:)]) {
            return;
        }

        CGPoint position = CGPointMake(0.0, 0.0);

        if (!featureResult) {
            [self.mapViewDelegate mapView:self didSelectFeature:nil atScreenPosition:position];
            return;
        }

        NSMutableDictionary* dictionary = [[NSMutableDictionary alloc] init];

        const auto& properties = featureResult->properties;
        position = CGPointMake(featureResult->position[0] / self.contentScaleFactor, featureResult->position[1] / self.contentScaleFactor);

        for (const auto& item : properties->items()) {
            NSString* key = [NSString stringWithUTF8String:item.key.c_str()];
            NSString* value = [NSString stringWithUTF8String:properties->asString(item.value).c_str()];
            dictionary[key] = value;
        }

        [self.mapViewDelegate mapView:self didSelectFeature:dictionary atScreenPosition:position];
    });
}

- (void)pickMarkerAt:(CGPoint)screenPosition
{
    if (!self.map) { return; }

    screenPosition.x *= self.contentScaleFactor;
    screenPosition.y *= self.contentScaleFactor;

    self.map->pickMarkerAt(screenPosition.x, screenPosition.y, [screenPosition, self](const Tangram::MarkerPickResult* markerPickResult) {
        if (!self.mapViewDelegate || ![self.mapViewDelegate respondsToSelector:@selector(mapView:didSelectMarker:atScreenPosition:)]) {
            return;
        }

        CGPoint position = CGPointMake(0.0, 0.0);

        if (!markerPickResult) {
            [self.mapViewDelegate mapView:self didSelectMarker:nil atScreenPosition:position];
            return;
        }

        position = CGPointMake(markerPickResult->position[0] / self.contentScaleFactor, markerPickResult->position[1] / self.contentScaleFactor);
        TGGeoPoint coordinates = TGGeoPointMake(markerPickResult->coordinates.longitude, markerPickResult->coordinates.latitude);
        TGMarkerPickResult* result = [[TGMarkerPickResult alloc] initWithCoordinates:coordinates identifier:markerPickResult->id];

        [self.mapViewDelegate mapView:self didSelectMarker:result atScreenPosition:position];
    });
}

- (void)pickLabelAt:(CGPoint)screenPosition
{
    if (!self.map) { return; }

    screenPosition.x *= self.contentScaleFactor;
    screenPosition.y *= self.contentScaleFactor;

    self.map->pickLabelAt(screenPosition.x, screenPosition.y, [screenPosition, self](const Tangram::LabelPickResult* labelPickResult) {
        if (!self.mapViewDelegate || ![self.mapViewDelegate respondsToSelector:@selector(mapView:didSelectLabel:atScreenPosition:)]) {
            return;
        }

        CGPoint position = CGPointMake(0.0, 0.0);

        if (!labelPickResult) {
            [self.mapViewDelegate mapView:self didSelectLabel:nil atScreenPosition:position];
            return;
        }

        NSMutableDictionary* dictionary = [[NSMutableDictionary alloc] init];

        const auto& touchItem = labelPickResult->touchItem;
        const auto& properties = touchItem.properties;
        position = CGPointMake(touchItem.position[0] / self.contentScaleFactor, touchItem.position[1] / self.contentScaleFactor);

        for (const auto& item : properties->items()) {
            NSString* key = [NSString stringWithUTF8String:item.key.c_str()];
            NSString* value = [NSString stringWithUTF8String:properties->asString(item.value).c_str()];
            dictionary[key] = value;
        }

        TGGeoPoint coordinates = TGGeoPointMake(labelPickResult->coordinates.longitude, labelPickResult->coordinates.latitude);
        TGLabelPickResult* tgLabelPickResult = [[TGLabelPickResult alloc] initWithCoordinates:coordinates
                                                                                         type:(TGLabelType)labelPickResult->type
                                                                                   properties:dictionary];
        [self.mapViewDelegate mapView:self didSelectLabel:tgLabelPickResult atScreenPosition:position];
    });
}

#pragma mark Marker implementation

- (TGMapMarkerId)markerAdd
{
    if (!self.map) { return 0; }

    return (TGMapMarkerId)self.map->markerAdd();
}

- (BOOL)markerRemove:(TGMapMarkerId)marker
{
    if (!self.map) { return NO; }

    return self.map->markerRemove(marker);
}

- (void)markerRemoveAll
{
    if (!self.map) { return; }

    self.map->markerRemoveAll();
}

- (BOOL)markerSetStyling:(TGMapMarkerId)identifier styling:(NSString *)styling
{
    if (!self.map) { return NO; }

    return self.map->markerSetStyling(identifier, [styling UTF8String]);
}

- (BOOL)markerSetPoint:(TGMapMarkerId)identifier coordinates:(TGGeoPoint)coordinates
{
    if (!self.map || !identifier) { return NO; }

    Tangram::LngLat lngLat(coordinates.longitude, coordinates.latitude);

    return self.map->markerSetPoint(identifier, lngLat);
}

- (BOOL)markerSetPointEased:(TGMapMarkerId)identifier coordinates:(TGGeoPoint)coordinates seconds:(float)seconds easeType:(TGEaseType)ease
{
    if (!self.map || !identifier) { return NO; }

    Tangram::LngLat lngLat(coordinates.longitude, coordinates.latitude);

    return self.map->markerSetPointEased(identifier, lngLat, seconds, [TGHelpers convertEaseTypeFrom:ease]);
}

- (BOOL)markerSetPolyline:(TGMapMarkerId)identifier polyline:(TGGeoPolyline *)polyline
{
    if (polyline.count < 2 || !identifier) { return NO; }

    return self.map->markerSetPolyline(identifier, reinterpret_cast<Tangram::LngLat*>([polyline coordinates]), polyline.count);
}

- (BOOL)markerSetPolygon:(TGMapMarkerId)identifier polygon:(TGGeoPolygon *)polygon;
{
    if (polygon.count < 3 || !identifier) { return NO; }

    auto coords = reinterpret_cast<Tangram::LngLat*>([polygon coordinates]);

    return self.map->markerSetPolygon(identifier, coords, [polygon rings], [polygon ringsCount]);
}

- (BOOL)markerSetVisible:(TGMapMarkerId)identifier visible:(BOOL)visible
{
    if (!self.map) { return NO; }

    return self.map->markerSetVisible(identifier, visible);
}

- (BOOL)markerSetImage:(TGMapMarkerId)identifier image:(UIImage *)image
{
    if (!self.map) { return NO; }

    CGImage* cgImage = [image CGImage];
    size_t w = CGImageGetHeight(cgImage);
    size_t h = CGImageGetWidth(cgImage);
    std::vector<unsigned int> bitmap;
    bitmap.resize(w * h);

    CGColorSpaceRef colorSpace = CGImageGetColorSpace(cgImage);
    CGContextRef cgContext = CGBitmapContextCreate(bitmap.data(), w, h, 8, w * 4, colorSpace, kCGImageAlphaPremultipliedLast);
    CGAffineTransform flipAffineTransform = CGAffineTransformMake(1, 0, 0, -1, 0, h);
    CGContextConcatCTM(cgContext, flipAffineTransform);
    CGContextDrawImage(cgContext, CGRectMake(0, 0, w, h), cgImage);
    CGContextRelease(cgContext);

    return self.map->markerSetBitmap(identifier, w, h, bitmap.data());
}

#pragma mark Map position implementation

- (void)setPosition:(TGGeoPoint)position {
    if (!self.map) { return; }

    self.map->setPosition(position.longitude, position.latitude);
}

- (void)animateToPosition:(TGGeoPoint)position withDuration:(float)seconds
{
    [self animateToPosition:position withDuration:seconds withEaseType:TGEaseTypeCubic];
}

- (void)animateToPosition:(TGGeoPoint)position withDuration:(float)seconds withEaseType:(TGEaseType)easeType
{
    if (!self.map) { return; }

    Tangram::EaseType ease = [TGHelpers convertEaseTypeFrom:easeType];
    self.map->setPositionEased(position.longitude, position.latitude, seconds, ease);
}

- (TGGeoPoint)position
{
    static const TGGeoPoint nullTangramGeoPoint = {NAN, NAN};

    if (!self.map) { return nullTangramGeoPoint; }

    TGGeoPoint returnVal;

    self.map->getPosition(returnVal.longitude, returnVal.latitude);

    return returnVal;
}

- (void)setZoom:(float)zoom
{
    if (!self.map) { return; }

    self.map->setZoom(zoom);
}

- (void)animateToZoomLevel:(float)zoomLevel withDuration:(float)seconds
{
    [self animateToZoomLevel:zoomLevel withDuration:seconds withEaseType:TGEaseTypeCubic];
}

- (void)animateToZoomLevel:(float)zoomLevel withDuration:(float)seconds withEaseType:(TGEaseType)easeType
{
    if (!self.map) { return; }

    Tangram::EaseType ease = [TGHelpers convertEaseTypeFrom:easeType];
    self.map->setZoomEased(zoomLevel, seconds, ease);
}

- (float)zoom
{
    if (!self.map) { return 0.0; }

    return self.map->getZoom();
}

- (void)animateToRotation:(float)radians withDuration:(float)seconds
{
    [self animateToRotation:radians withDuration:seconds withEaseType:TGEaseTypeCubic];
}

- (void)animateToRotation:(float)radians withDuration:(float)seconds withEaseType:(TGEaseType)easeType
{
    if (!self.map) { return; }

    Tangram::EaseType ease = [TGHelpers convertEaseTypeFrom:easeType];
    self.map->setRotationEased(radians, seconds, ease);
}

- (void)setRotation:(float)radians
{
    if (!self.map) { return; }

    self.map->setRotation(radians);
}

- (float)rotation
{
    if (!self.map) { return 0.0; }

    return self.map->getRotation();
}

- (float)tilt
{
    if (!self.map) { return 0.0; }

    return self.map->getTilt();
}

- (void)setTilt:(float)radians
{
    if (!self.map) { return; }

    self.map->setTilt(radians);
}

- (void)animateToTilt:(float)radians withDuration:(float)seconds
{
    [self animateToTilt:radians withDuration:seconds withEaseType:TGEaseType::TGEaseTypeCubic];
}

- (void)animateToTilt:(float)radians withDuration:(float)seconds withEaseType:(TGEaseType)easeType
{
    if (!self.map) { return; }

    Tangram::EaseType ease = [TGHelpers convertEaseTypeFrom:easeType];
    self.map->setTiltEased(radians, seconds, ease);
}

#pragma mark Camera type

- (TGCameraType)cameraType
{
    switch (self.map->getCameraType()) {
        case 0:
            return TGCameraTypePerspective;
        case 1:
            return TGCameraTypeIsometric;
        case 2:
            return TGCameraTypeFlat;
        default:
            return TGCameraTypePerspective;
    }
}

- (void)setCameraType:(TGCameraType)cameraType
{
    if (!self.map){ return; }

    self.map->setCameraType(cameraType);
}

#pragma mark Gestures

- (void)setupGestureRecognizers
{
    /* Construct Gesture Recognizers */
    //1. Tap
    UITapGestureRecognizer* tapRecognizer = [[UITapGestureRecognizer alloc]
                                             initWithTarget:self action:@selector(respondToTapGesture:)];
    tapRecognizer.numberOfTapsRequired = 1;
    // TODO: Figure a way to have a delay set for it not to tap gesture not to wait long enough for a doubletap gesture to be recognized
    tapRecognizer.delaysTouchesEnded = NO;

    //2. DoubleTap
    UITapGestureRecognizer* doubleTapRecognizer = [[UITapGestureRecognizer alloc]
                                                   initWithTarget:self action:@selector(respondToDoubleTapGesture:)];
    doubleTapRecognizer.numberOfTapsRequired = 2;
    // Distanle single tap when double tap occurs
    [tapRecognizer requireGestureRecognizerToFail:doubleTapRecognizer];

    //3. Pan
    UIPanGestureRecognizer* panRecognizer = [[UIPanGestureRecognizer alloc]
                                             initWithTarget:self action:@selector(respondToPanGesture:)];
    panRecognizer.maximumNumberOfTouches = 1;

    //4. Pinch
    UIPinchGestureRecognizer* pinchRecognizer = [[UIPinchGestureRecognizer alloc]
                                                 initWithTarget:self action:@selector(respondToPinchGesture:)];

    //5. Rotate
    UIRotationGestureRecognizer* rotationRecognizer = [[UIRotationGestureRecognizer alloc]
                                                       initWithTarget:self action:@selector(respondToRotationGesture:)];

    //6. Shove
    UIPanGestureRecognizer* shoveRecognizer = [[UIPanGestureRecognizer alloc]
                                               initWithTarget:self action:@selector(respondToShoveGesture:)];
    shoveRecognizer.minimumNumberOfTouches = 2;

    //7. Long press
    UILongPressGestureRecognizer* longPressRecognizer = [[UILongPressGestureRecognizer alloc]
                                                         initWithTarget:self action:@selector(respondToLongPressGesture:)];

    // Use the delegate method 'shouldRecognizeSimultaneouslyWithGestureRecognizer' for gestures that can be concurrent
    panRecognizer.delegate = self;
    pinchRecognizer.delegate = self;
    rotationRecognizer.delegate = self;

    /* Setup gesture recognizers */
    [self.view addGestureRecognizer:tapRecognizer];
    [self.view addGestureRecognizer:doubleTapRecognizer];
    [self.view addGestureRecognizer:panRecognizer];
    [self.view addGestureRecognizer:pinchRecognizer];
    [self.view addGestureRecognizer:rotationRecognizer];
    [self.view addGestureRecognizer:shoveRecognizer];
    [self.view addGestureRecognizer:longPressRecognizer];
}

// Implement touchesBegan to catch down events
- (void)touchesBegan:(NSSet *)touches withEvent:(UIEvent *)event {
    self.map->handlePanGesture(0.0f, 0.0f, 0.0f, 0.0f);
}

- (BOOL)gestureRecognizer:(UIGestureRecognizer *)gestureRecognizer shouldRecognizeSimultaneouslyWithGestureRecognizer:(UIGestureRecognizer *)otherGestureRecognizer
{
    // make shove gesture exclusive
    if ([gestureRecognizer isKindOfClass:[UIPanGestureRecognizer class]]) {
        return [gestureRecognizer numberOfTouches] != 2;
    }
    if ([otherGestureRecognizer isKindOfClass:[UIPanGestureRecognizer class]]) {
        return [otherGestureRecognizer numberOfTouches] != 2;
    }
    return YES;
}

#pragma mark - Gesture Recognizer Delegate Methods

- (void)respondToLongPressGesture:(UILongPressGestureRecognizer *)longPressRecognizer
{
    CGPoint location = [longPressRecognizer locationInView:self.view];
    if (self.gestureDelegate && [self.gestureDelegate respondsToSelector:@selector(mapView:recognizer:shouldRecognizeLongPressGesture:)] ) {
        if (![self.gestureDelegate mapView:self recognizer:longPressRecognizer shouldRecognizeLongPressGesture:location]) { return; }
    }

    if (self.gestureDelegate && [self.gestureDelegate respondsToSelector:@selector(mapView:recognizer:didRecognizeLongPressGesture:)]) {
        [self.gestureDelegate mapView:self recognizer:longPressRecognizer didRecognizeLongPressGesture:location];
    }
}

- (void)respondToTapGesture:(UITapGestureRecognizer *)tapRecognizer
{
    CGPoint location = [tapRecognizer locationInView:self.view];
    if (self.gestureDelegate && [self.gestureDelegate respondsToSelector:@selector(mapView:recognizer:shouldRecognizeSingleTapGesture:)]) {
        if (![self.gestureDelegate mapView:self recognizer:tapRecognizer shouldRecognizeSingleTapGesture:location]) { return; }
    }

    if (self.gestureDelegate && [self.gestureDelegate respondsToSelector:@selector(mapView:recognizer:didRecognizeSingleTapGesture:)]) {
        [self.gestureDelegate mapView:self recognizer:tapRecognizer didRecognizeSingleTapGesture:location];
    }
}

- (void)respondToDoubleTapGesture:(UITapGestureRecognizer *)doubleTapRecognizer
{
    CGPoint location = [doubleTapRecognizer locationInView:self.view];
    if (self.gestureDelegate && [self.gestureDelegate respondsToSelector:@selector(mapView:recognizer:shouldRecognizeDoubleTapGesture:)]) {
        if (![self.gestureDelegate mapView:self recognizer:doubleTapRecognizer shouldRecognizeDoubleTapGesture:location]) { return; }
    }

    if (self.gestureDelegate && [self.gestureDelegate respondsToSelector:@selector(mapView:recognizer:didRecognizeDoubleTapGesture:)]) {
        [self.gestureDelegate mapView:self recognizer:doubleTapRecognizer didRecognizeDoubleTapGesture:location];
    }
}

- (void)respondToPanGesture:(UIPanGestureRecognizer *)panRecognizer
{
    CGPoint displacement = [panRecognizer translationInView:self.view];

    if (self.gestureDelegate && [self.gestureDelegate respondsToSelector:@selector(mapView:recognizer:shouldRecognizePanGesture:)]) {
        if (![self.gestureDelegate mapView:self recognizer:panRecognizer shouldRecognizePanGesture:displacement]) {
            return;
        }
    }

    CGPoint velocity = [panRecognizer velocityInView:self.view];
    CGPoint end = [panRecognizer locationInView:self.view];
    CGPoint start = {end.x - displacement.x, end.y - displacement.y};

    [panRecognizer setTranslation:CGPointZero inView:self.view];

    switch (panRecognizer.state) {
        case UIGestureRecognizerStateChanged:
            self.map->handlePanGesture(start.x * self.contentScaleFactor, start.y * self.contentScaleFactor, end.x * self.contentScaleFactor, end.y * self.contentScaleFactor);
            break;
        case UIGestureRecognizerStateEnded:
            self.map->handleFlingGesture(end.x * self.contentScaleFactor, end.y * self.contentScaleFactor, velocity.x * self.contentScaleFactor, velocity.y * self.contentScaleFactor);
            break;
        default:
            break;
    }

    if (self.gestureDelegate && [self.gestureDelegate respondsToSelector:@selector(mapView:recognizer:didRecognizePanGesture:)]) {
        [self.gestureDelegate mapView:self recognizer:panRecognizer didRecognizePanGesture:displacement];
    }
}

- (void)respondToPinchGesture:(UIPinchGestureRecognizer *)pinchRecognizer
{
    CGPoint location = [pinchRecognizer locationInView:self.view];
    if (self.gestureDelegate && [self.gestureDelegate respondsToSelector:@selector(mapView:recognizer:shouldRecognizePinchGesture:)]) {
        if (![self.gestureDelegate mapView:self recognizer:pinchRecognizer shouldRecognizePinchGesture:location]) {
            return;
        }
    }

    CGFloat scale = pinchRecognizer.scale;
    [pinchRecognizer setScale:1.0];
    self.map->handlePinchGesture(location.x * self.contentScaleFactor, location.y * self.contentScaleFactor, scale, pinchRecognizer.velocity);

    if (self.gestureDelegate && [self.gestureDelegate respondsToSelector:@selector(mapView:recognizer:didRecognizePinchGesture:)]) {
        [self.gestureDelegate mapView:self recognizer:pinchRecognizer didRecognizePinchGesture:location];
    }
}

- (void)respondToRotationGesture:(UIRotationGestureRecognizer *)rotationRecognizer
{
    CGPoint position = [rotationRecognizer locationInView:self.view];
    if (self.gestureDelegate && [self.gestureDelegate respondsToSelector:@selector(mapView:recognizer:shouldRecognizeRotationGesture:)]) {
        if (![self.gestureDelegate mapView:self recognizer:rotationRecognizer shouldRecognizeRotationGesture:position]) {
            return;
        }
    }

    CGFloat rotation = rotationRecognizer.rotation;
    [rotationRecognizer setRotation:0.0];
    self.map->handleRotateGesture(position.x * self.contentScaleFactor, position.y * self.contentScaleFactor, rotation);

    if (self.gestureDelegate && [self.gestureDelegate respondsToSelector:@selector(mapView:recognizer:didRecognizeRotationGesture:)]) {
        [self.gestureDelegate mapView:self recognizer:rotationRecognizer didRecognizeRotationGesture:position];
    }
}

- (void)respondToShoveGesture:(UIPanGestureRecognizer *)shoveRecognizer
{
    CGPoint displacement = [shoveRecognizer translationInView:self.view];
    [shoveRecognizer setTranslation:{0, 0} inView:self.view];

    if (self.gestureDelegate && [self.gestureDelegate respondsToSelector:@selector(recognizer:shouldRecognizeShoveGesture:)]) {
        if (![self.gestureDelegate mapView:self recognizer:shoveRecognizer shouldRecognizeShoveGesture:displacement]) {
            return;
        }
    }

    // don't trigger shove on single touch gesture
    if ([shoveRecognizer numberOfTouches] == 2) {
        self.map->handleShoveGesture(displacement.y);

        if (self.gestureDelegate && [self.gestureDelegate respondsToSelector:@selector(recognizer:didRecognizeShoveGesture:)]) {
            [self.gestureDelegate mapView:self recognizer:shoveRecognizer didRecognizeShoveGesture:displacement];
        }
    }
}
#pragma mark Standard Initializer

- (instancetype)initWithNibName:(NSString *)nibNameOrNil bundle:(NSBundle *)nibBundleOrNil
{
    self = [super initWithNibName:nibNameOrNil bundle:nibBundleOrNil];
    if (self != nil) {
        std::shared_ptr<Platform> platform(new iOSPlatform(self));
        self.map = new Tangram::Map(platform);
    }
    return self;
}

- (instancetype)initWithCoder:(NSCoder *)aDecoder
{
    self = [super initWithCoder:aDecoder];
    if (self != nil) {
        std::shared_ptr<Platform> platform(new iOSPlatform(self));
        self.map = new Tangram::Map(platform);
    }
    return self;
}

#pragma mark Map view lifecycle

- (void)viewDidLoad
{
    [super viewDidLoad];

    self.context = [[EAGLContext alloc] initWithAPI:kEAGLRenderingAPIOpenGLES2];
    if (!self.context) {
        NSLog(@"Failed to create ES context");
    }

    self.renderRequested = YES;
    self.continuous = NO;

    if (!self.httpHandler) {
        self.httpHandler = [[TGHttpHandler alloc] initWithCachePath:@"/tangram_cache"
                                                cacheMemoryCapacity:4*1024*1024
                                                  cacheDiskCapacity:30*1024*1024];
    }

    GLKView* view = (GLKView *)self.view;
    view.context = self.context;
    view.drawableDepthFormat = GLKViewDrawableDepthFormat24;
    view.drawableMultisample = GLKViewDrawableMultisample4X;
    self.contentScaleFactor = view.contentScaleFactor;

    [self setupGestureRecognizers];
    [self setupGL];

}

- (void)dealloc
{
    if ([EAGLContext currentContext] == self.context) {
        [EAGLContext setCurrentContext:nil];
    }
}

- (void)didReceiveMemoryWarning
{
    [super didReceiveMemoryWarning];

    if ([self isViewLoaded] && ([[self view] window] == nil)) {
        self.view = nil;

        if ([EAGLContext currentContext] == self.context) {
            [EAGLContext setCurrentContext:nil];
        }
        self.context = nil;
    }

    // Dispose of any resources that can be recreated.
}

- (void)setupGL
{
    [EAGLContext setCurrentContext:self.context];

    self.map->setupGL();

    int width = self.view.bounds.size.width;
    int height = self.view.bounds.size.height;

    self.map->resize(width * self.contentScaleFactor, height * self.contentScaleFactor);

    self.map->setPixelScale(self.contentScaleFactor);
}

- (void)tearDownGL
{
    if (!self.map) { return; }

    delete self.map;
    self.map = nullptr;
}

- (void)viewWillTransitionToSize:(CGSize)size withTransitionCoordinator:(id<UIViewControllerTransitionCoordinator>)coordinator
{
    self.map->resize(size.width * self.contentScaleFactor, size.height * self.contentScaleFactor);

    [self renderOnce];
}

- (void)requestRender
{
    if (!self.map) { return; }

    self.renderRequested = YES;
}

- (void)renderOnce
{
    if (!self.continuous) {
        self.renderRequested = YES;
        self.paused = NO;
    }
}

- (void)setContinuous:(BOOL)c
{
    _continuous = c;
    self.paused = !c;
}

- (void)update
{
    bool viewComplete = self.map->update([self timeSinceLastUpdate]);

    if (viewComplete && [self.mapViewDelegate respondsToSelector:@selector(mapViewDidCompleteLoading:)]) {
        [self.mapViewDelegate mapViewDidCompleteLoading:self];
    }

    if (!self.continuous && !self.renderRequested) {
        self.paused = YES;
    }

    self.renderRequested = NO;
}

- (void)glkView:(GLKView *)view drawInRect:(CGRect)rect
{
    self.map->render();
}

@end
