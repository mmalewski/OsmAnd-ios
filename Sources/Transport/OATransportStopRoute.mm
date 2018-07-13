//
//  OATransportStopRoute.m
//  OsmAnd
//
//  Created by Alexey on 11/07/2018.
//  Copyright © 2018 OsmAnd. All rights reserved.
//

#import "OATransportStopRoute.h"
#import "OsmAndApp.h"
#import "OATransportStopType.h"
#import "OAPOIHelper.h"
#import "OARootViewController.h"
#import "OAMapViewController.h"
#import "OAColors.h"
#import "OAUtilities.h"

#include <OsmAndCore.h>
#include <OsmAndCore/Utilities.h>
#include <OsmAndCore/Data/TransportStop.h>

@interface OATransportStopRoute ()

@property (nonatomic) UIColor *cachedColor;
@property (nonatomic) BOOL cachedNight;

@end

@implementation OATransportStopRoute

- (NSString *) getDescription:(BOOL)useDistance
{
    OsmAndAppInstance app = [OsmAndApp instance];
    auto lang = QStringLiteral("");
    if (useDistance && self.distance > 0) {
        NSString *nm = [app getFormattedDistance:self.distance];
        if (_refStop && _refStop->getName(lang, false) != _stop->getName(lang, false))
            nm = [NSString stringWithFormat:@"%@, %@", _refStop->getName(lang, false).toNSString(), nm];
        
        return [NSString stringWithFormat:@"%@ (%@)", self.desc, nm];
    }
    return self.desc;
}

- (void) initBounds:(OAGpxBounds)bounds
{
    bounds.topLeft.latitude = DBL_MAX;
    bounds.topLeft.longitude = DBL_MAX;
    bounds.bottomRight.latitude = DBL_MAX;
    bounds.bottomRight.longitude = DBL_MAX;
}

- (void) processBounds:(OAGpxBounds)bounds coord:(CLLocationCoordinate2D)coord
{
    if (bounds.topLeft.longitude == DBL_MAX)
    {
        bounds.topLeft.longitude = coord.longitude;
        bounds.bottomRight.longitude = coord.longitude;
        bounds.topLeft.latitude = coord.latitude;
        bounds.bottomRight.latitude = coord.latitude;
    }
    else
    {
        bounds.topLeft.longitude = MIN(bounds.topLeft.longitude, coord.longitude);
        bounds.bottomRight.longitude = MAX(bounds.bottomRight.longitude, coord.longitude);
        bounds.topLeft.latitude = MAX(bounds.topLeft.latitude, coord.latitude);
        bounds.bottomRight.latitude = MIN(bounds.bottomRight.latitude, coord.latitude);
    }
}

- (void) applyBounds:(OAGpxBounds)bounds
{
    double clat = bounds.bottomRight.latitude / 2.0 + bounds.topLeft.latitude / 2.0;
    double clon = bounds.topLeft.longitude / 2.0 + bounds.bottomRight.longitude / 2.0;
    bounds.center = CLLocationCoordinate2DMake(clat, clon);
}

- (OAGpxBounds) calculateBounds:(int)startPosition
{
    OAGpxBounds bounds;
    [self initBounds:bounds];
    
    auto& sts = _route->forwardStops;
    for (int i = startPosition; i < sts.size(); i++)
    {
        auto st = sts[startPosition];
        const auto& latLon = OsmAnd::Utilities::convert31ToLatLon(st->position31);
        [self processBounds:bounds coord:CLLocationCoordinate2DMake(latLon.latitude, latLon.longitude)];
    }
    [self applyBounds:bounds];
    return bounds;
}

- (UIColor *) getColor:(BOOL)nightMode
{
    if (!_cachedColor || _cachedNight != nightMode)
    {
        _cachedColor = UIColorFromARGB(color_transport_route_line_argb);
        _cachedNight = nightMode;
        if (self.type)
        {
            NSString *color = _route->color.toNSString();
            NSString *typeStr = color.length == 0 ? self.type.renderAttr : color;
            _cachedColor = [[OARootViewController instance].mapPanel.mapViewController getTransportRouteColor:nightMode renderAttrName:typeStr];
        }
    }
    
    return _cachedColor;
}

- (NSString *) getTypeStr
{
    OAPOIHelper *poiHelper = [OAPOIHelper sharedInstance];
    if (self.type)
    {
        switch (self.type.type)
        {
            case TST_BUS:
                return [poiHelper getPhraseByName:@"route_bus_ref"];
            case TST_TRAM:
                return [poiHelper getPhraseByName:@"route_tram_ref"];
            case TST_FERRY:
                return [poiHelper getPhraseByName:@"route_ferry_ref"];
            case TST_TRAIN:
                return [poiHelper getPhraseByName:@"route_train_ref"];
            case TST_SHARE_TAXI:
                return [poiHelper getPhraseByName:@"route_share_taxi_ref"];
            case TST_FUNICULAR:
                return [poiHelper getPhraseByName:@"route_funicular_ref"];
            case TST_LIGHT_RAIL:
                return [poiHelper getPhraseByName:@"route_light_rail_ref"];
            case TST_MONORAIL:
                return [poiHelper getPhraseByName:@"route_monorail_ref"];
            case TST_TROLLEYBUS:
                return [poiHelper getPhraseByName:@"route_trolleybus_ref"];
            case TST_RAILWAY:
                return [poiHelper getPhraseByName:@"route_railway_ref"];
            case TST_SUBWAY:
                return [poiHelper getPhraseByName:@"route_subway_ref"];
            default:
                return [poiHelper getPhraseByName:@"filter_public_transport"];
        }
    }
    else
    {
        return [poiHelper getPhraseByName:@"filter_public_transport"];
    }
}

@end
