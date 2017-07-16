//
//  OARouteProvider.m
//  OsmAnd
//
//  Created by Alexey Kulish on 27/06/2017.
//  Copyright © 2017 OsmAnd. All rights reserved.
//

#import "OARouteProvider.h"
#import "OAGPXDocument.h"
#import "OAAppSettings.h"
#import "OAGPXDocumentPrimitives.h"
#import "OARouteDirectionInfo.h"
#import "OsmAndApp.h"
#import "OARouteCalculationResult.h"
#import "OARouteCalculationParams.h"
#import "QuadRect.h"
#import "Localization.h"

#include <precalculatedRouteDirection.h>
#include <routePlannerFrontEnd.h>
#include <routingConfiguration.h>
#include <routingContext.h>

#define OSMAND_ROUTER @"OsmAndRouter"

@interface OARouteProvider()

+ (NSArray<OARouteDirectionInfo *> *) parseOsmAndGPXRoute:(NSArray<CLLocation *> *)res gpxFile:(OAGPXDocument *)gpxFile osmandRouter:(BOOL)osmandRouter leftSide:(BOOL)leftSide defSpeed:(float)defSpeed;

@end

@interface OARouteService()

@property (nonatomic) EOARouteService service;

@end

@implementation OARouteService

+ (instancetype)withService:(EOARouteService)service
{
    OARouteService *obj = [[OARouteService alloc] init];
    if (obj)
    {
        obj.service = service;
    }
    return obj;
}

+ (NSString *)getName:(EOARouteService)service
{
    switch (service)
    {
        case OSMAND:
            return @"OsmAnd (offline)";
        case YOURS:
            return @"YOURS";
        case OSRM:
            return @"OSRM (only car)";
        case BROUTER:
            return @"BRouter (offline)";
        case STRAIGHT:
            return @"Straight line";
        default:
            return @"";
    }
}

+ (BOOL) isOnline:(EOARouteService)service
{
    return service != OSMAND && service != BROUTER;
}

+ (BOOL) isAvailable:(EOARouteService)service
{
    if (service == BROUTER) {
        return NO; //ctx.getBRouterService() != null;
    }
    return YES;
}

+ (NSArray<OARouteService *> *) getAvailableRouters
{
    NSMutableArray<OARouteService *> *res = [NSMutableArray array];
    if ([OARouteService isAvailable:OSMAND])
        [res addObject:[OARouteService withService:OSMAND]];
    if ([OARouteService isAvailable:YOURS])
        [res addObject:[OARouteService withService:YOURS]];
    if ([OARouteService isAvailable:OSRM])
        [res addObject:[OARouteService withService:OSRM]];
    if ([OARouteService isAvailable:BROUTER])
        [res addObject:[OARouteService withService:BROUTER]];
    if ([OARouteService isAvailable:STRAIGHT])
        [res addObject:[OARouteService withService:STRAIGHT]];
    return [NSArray arrayWithArray:res];
}

@end

@interface OAGPXRouteParams()

@end

@implementation OAGPXRouteParams

- (instancetype)init
{
    self = [super init];
    if (self)
    {
        _addMissingTurns = YES;
    }
    return self;
}

- (OAGPXRouteParams *) prepareGPXFile:(OAGPXRouteParamsBuilder *)builder
{
    OAGPXDocument *file = builder.file;
    BOOL reverse = builder.reverse;
    self.passWholeRoute = builder.passWholeRoute;
    self.calculateOsmAndRouteParts = builder.calculateOsmAndRouteParts;
    self.useIntermediatePointsRTE = builder.useIntermediatePointsRTE;
    builder.calculateOsmAndRoute = NO; // Disabled temporary builder.calculateOsmAndRoute;
    if (file.locationMarks.count > 0)
    {
        self.wpt = [NSArray arrayWithArray:file.locationMarks];
    }
    if ([file isCloudmadeRouteFile] || [OSMAND_ROUTER isEqualToString:file.creator])
    {
        NSMutableArray<CLLocation *> *points = [NSMutableArray arrayWithArray:self.points];
        self.directions = [OARouteProvider parseOsmAndGPXRoute:points gpxFile:file osmandRouter:[OSMAND_ROUTER isEqualToString:file.creator] leftSide:builder.leftSide defSpeed:10];
        self.points = [NSArray arrayWithArray:points];
        if ([OSMAND_ROUTER isEqualToString:file.creator])
        {
            // For files generated by OSMAND_ROUTER use directions contained unaltered
            self.addMissingTurns = NO;
        }
        if (reverse)
        {
            // clear directions all turns should be recalculated
            self.directions = nil;
            self.points = [[self.points reverseObjectEnumerator] allObjects];
            self.addMissingTurns = YES;
        }
    }
    else
    {
        NSMutableArray<CLLocation *> *points = [NSMutableArray arrayWithArray:self.points];
        // first of all check tracks
        if (!self.useIntermediatePointsRTE)
        {
            for (OAGpxTrk *tr in file.tracks)
            {
                for (OAGpxTrkSeg *tkSeg in tr.segments)
                {
                    for (OAGpxTrkPt *pt in tkSeg.points)
                    {
                        CLLocation *loc = [[CLLocation alloc] initWithCoordinate:CLLocationCoordinate2DMake(pt.position.latitude, pt.position.longitude) altitude:pt.elevation horizontalAccuracy:pt.horizontalDilutionOfPrecision verticalAccuracy:pt.verticalDilutionOfPrecision course:0 speed:pt.speed timestamp:[NSDate dateWithTimeIntervalSince1970:pt.time]];

                        [points addObject:loc];
                    }
                }
            }
        }
        if (points.count == 0)
        {
            for (OAGpxRte *rte in file.routes)
            {
                for (OAGpxRtePt *pt in rte.points)
                {
                    CLLocation *loc = [[CLLocation alloc] initWithCoordinate:CLLocationCoordinate2DMake(pt.position.latitude, pt.position.longitude) altitude:pt.elevation horizontalAccuracy:pt.horizontalDilutionOfPrecision verticalAccuracy:pt.verticalDilutionOfPrecision course:0 speed:pt.speed timestamp:[NSDate dateWithTimeIntervalSince1970:pt.time]];
                    
                    [points addObject:loc];
                }
            }
        }
        if (reverse)
        {
            self.points = [[points reverseObjectEnumerator] allObjects];
        }
        else
        {
            self.points = [NSArray arrayWithArray:points];
        }
    }
    return self;
}

@end

@interface OAGPXRouteParamsBuilder()

@end

@implementation OAGPXRouteParamsBuilder

- (instancetype)initWithDoc:(OAGPXDocument *)document
{
    self = [super init];
    if (self) {
        _file = document;
        _leftSide = [OADrivingRegion isLeftHandDriving:[OAAppSettings sharedManager].settingDrivingRegion];
    }
    return self;
}

- (OAGPXRouteParams *) build:(CLLocation *)start
{
    OAGPXRouteParams *res = [[OAGPXRouteParams alloc] init];
    [res prepareGPXFile:self];
    //			if (passWholeRoute && start != null) {
    //				res.points.add(0, start);
    //			}
    return res;
}

- (NSArray<CLLocation *> *) getPoints
{
    OAGPXRouteParams *copy = [[OAGPXRouteParams alloc] init];
    [copy prepareGPXFile:self];
    return copy.points;
}

@end


@implementation OARouteProvider
{
    NSMutableSet<NSString *> *_nativeFiles;
}

- (instancetype)init
{
    self = [super init];
    if (self)
    {
        _nativeFiles = [NSMutableSet set];
    }
    return self;
}

+ (NSString *) getExtensionValue:(OAGpxExtensions *)exts key:(NSString *)key
{
    for (OAGpxExtension *e in exts.extensions) {
        if ([e.name isEqualToString:key]) {
            return e.value;
        }
    }
    return nil;
}

+ (NSArray<OARouteDirectionInfo *> *) parseOsmAndGPXRoute:(NSMutableArray<CLLocation *> *)res gpxFile:(OAGPXDocument *)gpxFile osmandRouter:(BOOL)osmandRouter leftSide:(BOOL)leftSide defSpeed:(float)defSpeed
{
    NSMutableArray<OARouteDirectionInfo *> *directions = nil;
    if (!osmandRouter)
    {
        for (OAGpxWpt *pt in gpxFile.locationMarks)
        {
            CLLocation *loc = [[CLLocation alloc] initWithCoordinate:CLLocationCoordinate2DMake(pt.position.latitude, pt.position.longitude) altitude:pt.elevation horizontalAccuracy:pt.horizontalDilutionOfPrecision verticalAccuracy:pt.verticalDilutionOfPrecision course:0 speed:pt.speed timestamp:[NSDate dateWithTimeIntervalSince1970:pt.time]];
            
            [res addObject:loc];
        }
    }
    else
    {
        for (OAGpxTrk *tr in gpxFile.tracks)
        {
            for (OAGpxTrkSeg *ts in tr.segments)
            {
                for (OAGpxTrkPt *pt in ts.points)
                {
                    CLLocation *loc = [[CLLocation alloc] initWithCoordinate:CLLocationCoordinate2DMake(pt.position.latitude, pt.position.longitude) altitude:pt.elevation horizontalAccuracy:pt.horizontalDilutionOfPrecision verticalAccuracy:pt.verticalDilutionOfPrecision course:0 speed:pt.speed timestamp:[NSDate dateWithTimeIntervalSince1970:pt.time]];
                    
                    [res addObject:loc];
                }
            }
        }
    }
    NSMutableArray<NSNumber *> *distanceToEnd  = [NSMutableArray arrayWithCapacity:res.count];
    for (int i = (int)res.count - 2; i >= 0; i--)
    {
        distanceToEnd[i] = @(distanceToEnd[i + 1].floatValue + [res[i] distanceFromLocation:res[i + 1]]);
    }
    
    OARoute *route = nil;
    if (gpxFile.routes.count > 0)
    {
        route = gpxFile.routes[0];
    }
    //OALocationServices *locationServices = [OsmAndApp instance].locationServices;
    OARouteDirectionInfo *previous = nil;
    if (route && route.points.count > 0)
    {
        directions = [NSMutableArray array];
        for (int i = 0; i < route.points.count; i++)
        {
            OAGpxRtePt *item = route.points[i];
            try
            {
                OAGpxExtensions *exts = (OAGpxExtensions *)item.extraData;
                
                NSString *stime = [OARouteProvider getExtensionValue:exts key:@"time"];
                int time  = 0;
                if (stime)
                    time = [stime intValue];
                
                int offset = [[OARouteProvider getExtensionValue:exts key:@"offset"] intValue];
                if (directions.count > 0)
                {
                    OARouteDirectionInfo *last = directions[directions.count - 1];
                    // update speed using time and idstance
                    last.averageSpeed = ((distanceToEnd[last.routePointOffset].floatValue - distanceToEnd[offset].floatValue) / last.averageSpeed);
                    last.distance = (int) round(distanceToEnd[last.routePointOffset].floatValue - distanceToEnd[offset].floatValue);
                } 
                // save time as a speed because we don't know distance of the route segment
                float avgSpeed = time;
                if (i == route.points.count - 1 && time > 0)
                    avgSpeed = distanceToEnd[offset].floatValue / time;
                
                NSString *stype = [OARouteProvider getExtensionValue:exts key:@"turn"];
                std::shared_ptr<TurnType> turnType = nullptr;
                if (stype)
                    turnType = std::make_shared<TurnType>(TurnType::fromString([[stype uppercaseString] UTF8String], leftSide));
                else
                    turnType = TurnType::ptrStraight();
                
                NSString *sturn = [OARouteProvider getExtensionValue:exts key:@"turn-angle"];
                if (sturn)
                    turnType->setTurnAngle([sturn floatValue]);
                
                OARouteDirectionInfo *dirInfo = [[OARouteDirectionInfo alloc] initWithAverageSpeed:avgSpeed turnType:turnType];
                [dirInfo setDescriptionRoute:item.desc];
                dirInfo.routePointOffset = offset;
                
                // Issue #2894
                NSString *sref = [OARouteProvider getExtensionValue:exts key:@"ref"];
                if (sref && ![@"null" isEqualToString:sref])
                    dirInfo.ref = sref;

                NSString *sstreetname = [OARouteProvider getExtensionValue:exts key:@"street-name"];
                if (sstreetname && ![@"null" isEqualToString:sstreetname])
                    dirInfo.streetName = sstreetname;
                
                NSString *sdest = [OARouteProvider getExtensionValue:exts key:@"dest"];
                if (sdest && ![@"null" isEqualToString:sdest])
                    dirInfo.destinationName = sdest;
                
                if (previous && TurnType::C != previous.turnType->getValue() && !osmandRouter)
                {
                    // calculate angle
                    if (previous.routePointOffset > 0)
                    {
                        double bearing = [res[previous.routePointOffset - 1] bearingTo:res[previous.routePointOffset]];
                        float paz = bearing;
                        float caz;
                        if (previous.turnType->isRoundAbout() && dirInfo.routePointOffset < res.count - 1)
                        {
                            bearing = [res[previous.routePointOffset] bearingTo:res[previous.routePointOffset + 1]];
                            caz = bearing;
                        }
                        else
                        {
                            bearing = [res[previous.routePointOffset - 1] bearingTo:res[previous.routePointOffset]];
                            caz = bearing;
                        }
                        float angle = caz - paz;
                        if (angle < 0)
                            angle += 360;
                        else if (angle > 360)
                            angle -= 360;
                        
                        // that magic number helps to fix some errors for turn
                        angle += 75;
                        
                        if (previous.turnType->getTurnAngle() < 0.5f) {
                            previous.turnType->setTurnAngle(angle);
                        }
                    }
                }
                
                [directions addObject:dirInfo];
                
                previous = dirInfo;
            } catch (NSException *e) {
            }
        }
    }
    
    if (previous && TurnType::C != previous.turnType->getValue())
    {
        // calculate angle
        if (previous.routePointOffset > 0 && previous.routePointOffset < res.count - 1)
        {
            double bearing = [res[previous.routePointOffset - 1] bearingTo:res[previous.routePointOffset]];
            float paz = bearing;

            bearing = [res[previous.routePointOffset] bearingTo:res[res.count - 1]];
            float caz = bearing;
            
            float angle = caz - paz;
            if (angle < 0)
                angle += 360;
            
            if (previous.turnType->getTurnAngle() < 0.5f)
                previous.turnType->setTurnAngle(angle);
        }
    }
    return directions;
}

- (OARouteCalculationResult *) applicationModeNotSupported:(OARouteCalculationParams *)params
{
    return [[OARouteCalculationResult alloc] initWithErrorMessage:[NSString stringWithFormat:@"Application mode '%@'is not supported.", [OAApplicationMode getVariantStr:params.mode]]];
}

- (OARouteCalculationResult *) interrupted
{
    return [[OARouteCalculationResult alloc] initWithErrorMessage:@"Route calculation was interrupted"];
}

- (OARouteCalculationResult *) emptyResult
{
    return [[OARouteCalculationResult alloc] initWithErrorMessage:@"Empty result"];
}

- (std::shared_ptr<RoutingConfiguration>) initOsmAndRoutingConfig:(std::shared_ptr<RoutingConfigurationBuilder>)config params:(OARouteCalculationParams *)params generalRouter:(std::shared_ptr<GeneralRouter>)generalRouter
{
    GeneralRouterProfile p;
    string profileName;
    if (params.mode == OAMapVariantBicycle)
    {
        p = GeneralRouterProfile::BICYCLE;
        profileName = "bicycle";
    }
    else if (params.mode == OAMapVariantPedestrian)
    {
        p = GeneralRouterProfile::PEDESTRIAN;
        profileName = "pedestrian";
    }
    else if(params.mode == OAMapVariantCar)
    {
        p = GeneralRouterProfile::CAR;
        profileName = "car";
    }
    else
        return nullptr;
    
    OAAppSettings *settings = [OAAppSettings sharedManager];
    MAP_STR_STR paramsR;
    auto& routerParams = generalRouter->getParameters();
    auto it = routerParams.begin();
    for(;it != routerParams.end(); it++)
    {
        const auto& key = it->first;
        const auto& pr = it->second;

        string vl;
        if (key == USE_SHORTEST_WAY)
        {
            BOOL b = ![settings.fastRouteMode get:params.mode];
            vl = b ? "true" : "";
        }
        else if (pr.type == RoutingParameterType::BOOLEAN)
        {
            OAProfileBoolean *pref = [settings getCustomRoutingBooleanProperty:[NSString stringWithUTF8String:key.c_str()] defaulfValue:pr.defaultBoolean];
            BOOL b = [pref get:params.mode];
            vl = b ? "true" : "";
        }
        else
        {
            vl = [[[settings getCustomRoutingProperty:[NSString stringWithUTF8String:key.c_str()] defaulfValue:@""] get:params.mode] UTF8String];
        }
        
        if (vl.length() > 0)
            paramsR[key] = vl;
    }
    
    float mb = (1 << 20);
    // make visible
    int memoryLimit = (int) (0.3 * ([NSProcessInfo processInfo].physicalMemory / mb)); // TODO
    int memoryTotal = (int) ([NSProcessInfo processInfo].physicalMemory / mb);
    NSLog(@"Use %d MB of %d", memoryLimit, memoryTotal);
    
    auto cf = config->build(profileName, params.start.course >= 0.0 ? params.start.course / 180.0 * M_PI : 0.0, memoryLimit, paramsR);
    return cf;
}

- (NSArray<CLLocation *> *) findStartAndEndLocationsFromRoute:(NSArray<CLLocation *> *)route startLoc:(CLLocation *)startLoc endLoc:(CLLocation *)endLoc startI:(NSMutableArray<NSNumber *> *)startI endI:(NSMutableArray<NSNumber *> *)endI
{
    float minDist = FLT_MAX;
    int start = 0;
    int end = (int)route.count;
    if (startLoc)
    {
        for (int i = 0; i < route.count; i++)
        {
            float d = [route[i] distanceFromLocation:startLoc];
            if (d < minDist)
            {
                start = i;
                minDist = d;
            }
        }
    }
    else
    {
        startLoc = route[0];
    }
    CLLocation *l = [[CLLocation alloc] initWithLatitude:endLoc.coordinate.latitude longitude:endLoc.coordinate.longitude];
    minDist = FLT_MAX;
    // get in reverse order taking into account ways with cycle
    for (int i = (int)route.count - 1; i >= start; i--)
    {
        float d = [route[i] distanceFromLocation:l];
        if (d < minDist)
        {
            end = i + 1;
            // slightly modify to allow last point to be added
            minDist = d - 40;
        }
    }
    NSArray<CLLocation *> *sublist = [route subarrayWithRange:NSMakeRange(start, end - start)];
    if (startI)
        startI[0] = @(start);
    
    if (endI)
        endI[0] = @(end);
    
    return sublist;
}

- (BOOL) containsData:(NSString *)localResourceId rect:(QuadRect *)rect desiredDataTypes:(OsmAnd::ObfDataTypesMask)desiredDataTypes zoomLevel:(OsmAnd::ZoomLevel)zoomLevel
{
    OsmAndAppInstance app = [OsmAndApp instance];
    const auto& localResource = app.resourcesManager->getLocalResource(QString::fromNSString(localResourceId));
    if (localResource)
    {
        const auto& obfMetadata = std::static_pointer_cast<const OsmAnd::ResourcesManager::ObfMetadata>(localResource->metadata);
        if (obfMetadata)
        {
            OsmAnd::AreaI pBbox31 = OsmAnd::AreaI((int)rect.top, (int)rect.left, (int)rect.bottom, (int)rect.right);
            if (zoomLevel == OsmAnd::InvalidZoomLevel)
                return obfMetadata->obfFile->obfInfo->containsDataFor(&pBbox31, OsmAnd::MinZoomLevel, OsmAnd::MaxZoomLevel, desiredDataTypes);
            else
                return obfMetadata->obfFile->obfInfo->containsDataFor(&pBbox31, zoomLevel, zoomLevel, desiredDataTypes);
        }
    }
    return NO;
}

- (void) checkInitialized:(int)zoom leftX:(int)leftX rightX:(int)rightX bottomY:(int)bottomY topY:(int)topY
{
    OsmAndAppInstance app = [OsmAndApp instance];
    const auto& localResources = app.resourcesManager->getLocalResources();
    QuadRect *rect = [[QuadRect alloc] initWithLeft:leftX top:topY right:rightX bottom:bottomY];
    auto dataTypes = OsmAnd::ObfDataTypesMask();
    dataTypes.set(OsmAnd::ObfDataType::Map);
    dataTypes.set(OsmAnd::ObfDataType::Routing);
    for (const auto& resource : localResources)
    {
        if (resource->origin == OsmAnd::ResourcesManager::ResourceOrigin::Installed)
        {
            NSString *localPath = resource->localPath.toNSString();
            if (![_nativeFiles containsObject:localPath] && [self containsData:localPath rect:rect desiredDataTypes:dataTypes zoomLevel:(OsmAnd::ZoomLevel)zoom])
            {
                [_nativeFiles addObject:localPath];
                initBinaryMapFile(resource->localPath.toStdString());
            }
        }
    }
}

- (OARouteCalculationResult *) calcOfflineRouteImpl:(OARouteCalculationParams *)params router:(std::shared_ptr<RoutePlannerFrontEnd>)router ctx:(std::shared_ptr<RoutingContext>)ctx complexCtx:(std::shared_ptr<RoutingContext>)complexCtx st:(CLLocation *)st en:(CLLocation *)en inters:(NSArray<CLLocation *> *)inters precalculated:(std::shared_ptr<PrecalculatedRouteDirection>)precalculated
{
    try
    {
        std::vector<std::shared_ptr<RouteSegmentResult> > result;
        
        int startX = get31TileNumberX(st.coordinate.longitude);
        int startY = get31TileNumberY(st.coordinate.latitude);
        int endX = get31TileNumberX(en.coordinate.longitude);
        int endY = get31TileNumberY(en.coordinate.latitude);
        vector<int> intX;
        vector<int> intY;
        for (CLLocation *l in inters)
        {
            intX.push_back(get31TileNumberX(l.coordinate.longitude));
            intY.push_back(get31TileNumberY(l.coordinate.latitude));
        }
        if (complexCtx)
        {
            try
            {
                result = router->searchRoute(complexCtx, startX, startY, endX, endY, intX, intY, precalculated);
                // discard ctx and replace with calculated
                ctx = complexCtx;
            }
            catch (NSException *e)
            {
                /* TODO toast
                params.ctx.runInUIThread(new Runnable() {
                    @Override
                    public void run() {
                        params.ctx.showToastMessage(R.string.complex_route_calculation_failed, e.getMessage());
                    }
                });
                 */
                result = router->searchRoute(ctx, startX, startY, endX, endY, intX, intY);
            }
        }
        else
        {
            result = router->searchRoute(ctx, startX, startY, endX, endY, intX, intY);
        }
        
        if (result.empty())
        {
            if (ctx->progress->segmentNotFound == 0)
            {
                return [[OARouteCalculationResult alloc] initWithErrorMessage:OALocalizedString(@"starting_point_too_far")];
            }
            else if(ctx->progress->segmentNotFound == inters.count + 1)
            {
                return [[OARouteCalculationResult alloc] initWithErrorMessage:OALocalizedString(@"ending_point_too_far")];
            }
            else if(ctx->progress->segmentNotFound > 0)
            {
                return [[OARouteCalculationResult alloc] initWithErrorMessage:[NSString stringWithFormat:OALocalizedString(@"ending_point_too_far"), ctx->progress->segmentNotFound]];
            }
            if (ctx->progress->directSegmentQueueSize == 0)
            {
                return [[OARouteCalculationResult alloc] initWithErrorMessage:[NSString stringWithFormat:@"Route can not be found from start point (%f km)", ctx->progress->distanceFromBegin / 1000]];
            }
            else if(ctx->progress->reverseSegmentQueueSize == 0)
            {
                return [[OARouteCalculationResult alloc] initWithErrorMessage:[NSString stringWithFormat:@"Route can not be found from end point (%f km)", ctx->progress->distanceFromEnd / 1000]];
            }
            if (ctx->progress->isCancelled())
                return [self interrupted];
            
            // something really strange better to see that message on the scren
            return [self emptyResult];
        }
        else
        {
            return [[OARouteCalculationResult alloc] initWithSegmentResults:result start:params.start end:params.end intermediates:params.intermediates leftSide:params.leftSide routingTime:ctx->routingTime waypoints:!params.gpxRoute ? nil : params.gpxRoute.wpt mode:params.mode];
        }
    }
    catch (NSException *e)
    {
        return [[OARouteCalculationResult alloc] initWithErrorMessage:e.reason];
    }
}

- (OARouteCalculationResult *) findVectorMapsRoute:(OARouteCalculationParams *)params calcGPXRoute:(BOOL)calcGPXRoute
{
    auto router = std::make_shared<RoutePlannerFrontEnd>();
    OsmAndAppInstance app = [OsmAndApp instance];
    OAAppSettings *settings = [OAAppSettings sharedManager];
    router->setUseFastRecalculation(settings.useFastRecalculation);
    
    auto config = app.defaultRoutingConfig;
    auto generalRouter = config->getRouter([[OAApplicationMode getAppModeByVariantType:params.mode] UTF8String]);
    if (!generalRouter)
        return [self applicationModeNotSupported:params];
    
    auto cf = [self initOsmAndRoutingConfig:config params:params generalRouter:generalRouter];
    if (!cf)
        return [self applicationModeNotSupported:params];
    
    std::shared_ptr<PrecalculatedRouteDirection> precalculated = nullptr;
    if (calcGPXRoute)
    {
        NSArray<CLLocation *> *sublist = [self findStartAndEndLocationsFromRoute:params.gpxRoute.points startLoc:params.start endLoc:params.end startI:nil endI:nil];
        vector<int> x31;
        vector<int> y31(sublist.count);
        for (int k = 0; k < sublist.count; k ++)
        {
            x31.push_back(get31TileNumberX(sublist[k].coordinate.longitude));
            y31.push_back(get31TileNumberY(sublist[k].coordinate.latitude));
        }
        precalculated = PrecalculatedRouteDirection::build(x31, y31, generalRouter->getMaxDefaultSpeed());
        precalculated->followNext = true;
        //cf.planRoadDirection = 1;
    }
    // BUILD context
    // check loaded files
    int leftX = get31TileNumberX(params.start.coordinate.longitude);
    int rightX = leftX;
    int bottomY = get31TileNumberY(params.start.coordinate.latitude);
    int topY = bottomY;
    if (params.intermediates)
    {
        for (CLLocation *l in params.intermediates)
        {
            leftX = MIN(get31TileNumberX(l.coordinate.longitude), leftX);
            rightX = MAX(get31TileNumberX(l.coordinate.longitude), rightX);
            bottomY = MAX(get31TileNumberY(l.coordinate.latitude), bottomY);
            topY = MIN(get31TileNumberY(l.coordinate.latitude), topY);
        }
    }
    CLLocation *l = params.end;
    leftX = MIN(get31TileNumberX(l.coordinate.longitude), leftX);
    rightX = MAX(get31TileNumberX(l.coordinate.longitude), rightX);
    bottomY = MAX(get31TileNumberY(l.coordinate.latitude), bottomY);
    topY = MIN(get31TileNumberY(l.coordinate.latitude), topY);
    
    [self checkInitialized:15 leftX:leftX rightX:rightX bottomY:bottomY topY:topY];
    
    auto ctx = router->buildRoutingContext(cf, RouteCalculationMode::NORMAL);
    
    std:shared_ptr<RoutingContext> complexCtx = nullptr;
    BOOL complex = params.mode == OAMapVariantCar && !settings.disableComplexRouting && !precalculated;
    ctx->leftSideNavigation = params.leftSide;
    ctx->progress = params.calculationProgress;
    if (params.previousToRecalculate && params.onlyStartPointChanged)
    {
        int currentRoute = params.previousToRecalculate.currentRoute;
        const auto& originalRoute = [params.previousToRecalculate getOriginalRoute];
        if (currentRoute < originalRoute.size())
        {
            std::vector<std::shared_ptr<RouteSegmentResult>> prevCalcRoute(originalRoute.begin() + currentRoute, originalRoute.end());
            ctx->previouslyCalculatedRoute = prevCalcRoute;
        }
    }
    
    if (complex && router->getRecalculationEnd(ctx.get()))
        complex = false;
    
    if (complex)
    {
        complexCtx = router->buildRoutingContext(cf, RouteCalculationMode::COMPLEX);
        complexCtx->progress = params.calculationProgress;
        complexCtx->leftSideNavigation = params.leftSide;
        complexCtx->previouslyCalculatedRoute = ctx->previouslyCalculatedRoute;
    }
    
    return [self calcOfflineRouteImpl:params router:router ctx:ctx complexCtx:complexCtx st:params.start en:params.end inters:params.intermediates precalculated:precalculated];
}

- (OARouteCalculationResult *) calculateOsmAndRouteWithIntermediatePoints:(OARouteCalculationParams *)routeParams intermediates:(NSArray<CLLocation *> *)intermediates
{
    OARouteCalculationParams *rp = [[OARouteCalculationParams alloc] init];
    rp.calculationProgress = routeParams.calculationProgress;
    rp.mode = routeParams.mode;
    rp.start = routeParams.start;
    rp.end = routeParams.end;
    rp.leftSide = routeParams.leftSide;
    rp.type = routeParams.type;
    rp.fast = routeParams.fast;
    rp.onlyStartPointChanged = routeParams.onlyStartPointChanged;
    rp.previousToRecalculate =  routeParams.previousToRecalculate;
    NSMutableArray<CLLocation *> *rpIntermediates = [NSMutableArray array];
    int closest = 0;
    double maxDist = DBL_MAX;
    for (int i = 0; i < intermediates.count; i++)
    {
        CLLocation *loc = intermediates[i];
        double dist = [loc distanceFromLocation:rp.start];
        if (dist <= maxDist)
        {
            closest = i;
            maxDist = dist;
        }
    }
    for (int i = closest; i < intermediates.count ; i++ )
    {
        CLLocation *w = intermediates[i];
        [rpIntermediates addObject:[[CLLocation alloc] initWithLatitude:w.coordinate.latitude longitude:w.coordinate.longitude]];
    }
    rp.intermediates = [NSArray arrayWithArray:rpIntermediates];
    return [self findVectorMapsRoute:rp calcGPXRoute:NO];
}

- (NSMutableArray<OARouteDirectionInfo *> *) calcDirections:(NSMutableArray<NSNumber *> *)startI endI:(NSMutableArray<NSNumber *> *)endI inputDirections:(NSArray<OARouteDirectionInfo *> *)inputDirections
{
    NSMutableArray<OARouteDirectionInfo *> *directions = [NSMutableArray array];
    if (inputDirections)
    {
        for (OARouteDirectionInfo *info in inputDirections)
        {
            if (info.routePointOffset >= startI[0].intValue && info.routePointOffset < endI[0].intValue)
            {
                OARouteDirectionInfo *ch = [[OARouteDirectionInfo alloc] initWithAverageSpeed:info.averageSpeed turnType:info.turnType];
                ch.routePointOffset = info.routePointOffset - startI[0].intValue;
                if (info.routeEndPointOffset != 0)
                    ch.routeEndPointOffset = info.routeEndPointOffset - startI[0].intValue;
                
                [ch setDescriptionRoute:[info getDescriptionRoutePart]];
                
                // Issue #2894
                if (info.ref && ![@"null" isEqualToString:info.ref])
                    ch.ref = info.ref;
                
                if (info.streetName && ![@"null" isEqualToString:info.streetName])
                    ch.streetName = info.streetName;
                
                if (info.destinationName && ![@"null" isEqualToString:info.destinationName])
                    ch.destinationName = info.destinationName;
                
                [directions addObject:ch];
            }
        }
    }
    return directions;
}

- (OARouteCalculationResult *) findOfflineRouteSegment:(OARouteCalculationParams *)rParams start:(CLLocation *)start end:(CLLocation  *)end
{
    OARouteCalculationParams *newParams = [[OARouteCalculationParams alloc] init];
    newParams.start = start;
    newParams.end = end;
    newParams.calculationProgress = rParams.calculationProgress;
    newParams.mode = rParams.mode;
    newParams.type = EOARouteService::OSMAND;
    newParams.leftSide = rParams.leftSide;
    OARouteCalculationResult *newRes = nil;
    try
    {
        newRes = [self findVectorMapsRoute:newParams calcGPXRoute:NO];
    }
    catch (NSException *e)
    {
    }
    return newRes;
}

- (void) insertFinalSegment:(OARouteCalculationParams *)routeParams points:(NSMutableArray<CLLocation *> *)points
                 directions:(NSMutableArray<OARouteDirectionInfo *> *)directions calculateOsmAndRouteParts:(BOOL)calculateOsmAndRouteParts
{
    if (points.count > 0)
    {
        CLLocation *routeEnd = points[points.count - 1];
        CLLocation *finalEnd = routeParams.end;
        if (finalEnd && [finalEnd distanceFromLocation:routeEnd] > 60)
        {
            OARouteCalculationResult *newRes = nil;
            if (calculateOsmAndRouteParts)
                newRes = [self findOfflineRouteSegment:routeParams start:routeEnd end:finalEnd];
            
            NSArray<CLLocation *> *loct = nil;
            NSArray<OARouteDirectionInfo *> *dt = nil;
            if (newRes && [newRes isCalculated])
            {
                loct = [newRes getImmutableAllLocations];
                dt = [newRes getImmutableAllDirections];
            } else {
                NSMutableArray<CLLocation *> *lct = [NSMutableArray array];
                [lct addObject:finalEnd];
                dt = [NSArray array];
            }
            for (OARouteDirectionInfo *i in dt)
                i.routePointOffset += (int)points.count;
            
            [points addObjectsFromArray:loct];
            [directions addObjectsFromArray:dt];
        }
    }
}

- (void) insertInitialSegment:(OARouteCalculationParams *)routeParams points:(NSMutableArray<CLLocation *> *)points
                 directions:(NSMutableArray<OARouteDirectionInfo *> *)directions calculateOsmAndRouteParts:(BOOL)calculateOsmAndRouteParts
{
    CLLocation *realStart = routeParams.start;
    if (realStart && points.count > 0 && [realStart distanceFromLocation:points[0]] > 60)
    {
        CLLocation *trackStart = points[0];
        OARouteCalculationResult *newRes = nil;
        if (calculateOsmAndRouteParts)
            newRes = [self findOfflineRouteSegment:routeParams start:realStart end:trackStart];

        NSArray<CLLocation *> *loct = nil;
        NSArray<OARouteDirectionInfo *> *dt = nil;
        if (newRes && [newRes isCalculated])
        {
            loct = [newRes getImmutableAllLocations];
            dt = [newRes getImmutableAllDirections];
        } else {
            NSMutableArray<CLLocation *> *lct = [NSMutableArray array];
            [lct addObject:realStart];
            dt = [NSArray array];
        }
        NSMutableIndexSet *inds = [NSMutableIndexSet indexSetWithIndexesInRange:NSMakeRange(0, loct.count)];
        [points insertObjects:loct atIndexes:inds];
        inds = [NSMutableIndexSet indexSetWithIndexesInRange:NSMakeRange(0, dt.count)];
        [directions insertObjects:dt atIndexes:inds];

        for (int i = (int)dt.count; i < directions.count; i++)
            directions[i].routePointOffset += (int)loct.count;
    }
}

- (OARouteCalculationResult *) calculateGpxRoute:(OARouteCalculationParams *)routeParams
{
    // get the closest point to start and to end
    OAGPXRouteParams *gpxParams = routeParams.gpxRoute;
    if (routeParams.gpxRoute.useIntermediatePointsRTE)
        return [self calculateOsmAndRouteWithIntermediatePoints:routeParams intermediates:gpxParams.points];
    
    NSMutableArray<CLLocation *> *gpxRoute = [NSMutableArray array];
    NSMutableArray<NSNumber *> *startI = [NSMutableArray array];
    NSMutableArray<NSNumber *> *endI = [NSMutableArray arrayWithCapacity:gpxParams.points.count];
    if (routeParams.gpxRoute.passWholeRoute)
        gpxRoute = [NSMutableArray arrayWithArray:gpxParams.points];
    else
        gpxRoute = [NSMutableArray arrayWithArray:[self findStartAndEndLocationsFromRoute:gpxParams.points startLoc:routeParams.start endLoc:routeParams.end startI:startI endI:endI]];
    
    NSArray<OARouteDirectionInfo *> *inputDirections = gpxParams.directions;
    NSMutableArray<OARouteDirectionInfo *> *gpxDirections = [self calcDirections:startI endI:endI inputDirections:inputDirections];
    BOOL calculateOsmAndRouteParts = gpxParams.calculateOsmAndRouteParts;
    [self insertInitialSegment:routeParams points:gpxRoute directions:gpxDirections calculateOsmAndRouteParts:calculateOsmAndRouteParts];
    [self insertFinalSegment:routeParams points:gpxRoute directions:gpxDirections calculateOsmAndRouteParts:calculateOsmAndRouteParts];
    
    for (OARouteDirectionInfo *info in gpxDirections)
    {
        // recalculate
        info.distance = 0;
        info.afterLeftTime = 0;
    }
    return [[OARouteCalculationResult alloc] initWithLocations:gpxRoute directions:gpxDirections params:routeParams waypoints:!gpxParams ? nil: gpxParams.wpt addMissingTurns:routeParams.gpxRoute.addMissingTurns];
}

- (OARouteCalculationResult *) recalculatePartOfflineRoute:(OARouteCalculationResult *)res params:(OARouteCalculationParams *)params
{
    OARouteCalculationResult *rcr = params.previousToRecalculate;
    NSMutableArray<CLLocation *> *locs = [NSMutableArray arrayWithArray:[rcr getRouteLocations]];
    try
    {
        NSMutableArray<NSNumber *> *startI = [NSMutableArray array];
        NSMutableArray<NSNumber *> *endI = [NSMutableArray arrayWithCapacity:locs.count];
        locs = [NSMutableArray arrayWithArray:[self findStartAndEndLocationsFromRoute:locs startLoc:params.start endLoc:params.end startI:startI endI:endI]];
        NSMutableArray<OARouteDirectionInfo *> *directions = [self calcDirections:startI endI:endI inputDirections:[rcr getRouteDirections]];;
        [self insertInitialSegment:params points:locs directions:directions calculateOsmAndRouteParts:YES];
        res = [[OARouteCalculationResult alloc] initWithLocations:locs directions:directions params:params waypoints:nil addMissingTurns:YES];
    }
    catch (NSException *e)
    {
    }
    return res;
}

- (OARouteCalculationResult *) calculateRouteImpl:(OARouteCalculationParams *)params
{
    float time = [[NSDate date] timeIntervalSince1970];
    if (params.start && params.end)
    {
        NSLog(@"Start finding route from %@ to %@ using %@", params.start, params.end, [OARouteService getName:params.type]);
        try
        {
            OARouteCalculationResult *res = nil;
            BOOL calcGPXRoute = params.gpxRoute && params.gpxRoute.points.count > 0;
            if (calcGPXRoute && !params.gpxRoute.calculateOsmAndRoute)
            {
                res = [self calculateGpxRoute:params];
            }
            else if (params.type == OSMAND)
            {
                res = [self findVectorMapsRoute:params calcGPXRoute:calcGPXRoute];
            }
            else if (params.type == BROUTER)
            {
                //res = findBROUTERRoute(params);
            }
            else if (params.type == YOURS)
            {
                //res = findYOURSRoute(params);
            }
            else if (params.type == OSRM)
            {
                //res = findOSRMRoute(params);
            }
            else if (params.type == STRAIGHT)
            {
                //res = findStraightRoute(params);
            }
            else
            {
                res = [[OARouteCalculationResult alloc] initWithErrorMessage:@"Selected route service is not available"];
            }

            if (res)
            {
                NSLog(@"Finding route contained  %d points for %f s", (int)[res getImmutableAllLocations].count, [[NSDate date] timeIntervalSince1970] - time);
            }

            return res;
        }
        catch (NSException *e)
        {
            NSLog(@"Failed to find route %@", e.reason);
        }
    }
    return [[OARouteCalculationResult alloc] initWithErrorMessage:nil];
}

@end