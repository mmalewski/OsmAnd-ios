//
//  OARouteTripSettingsViewController.h
//  OsmAnd
//
//  Created by Paul on 10/30/19.
//  Copyright © 2019 OsmAnd. All rights reserved.
//

#import "OARouteSettingsBaseViewController.h"
#import "OANavigationSettingsViewController.h"

@interface OARouteTripSettingsViewController : OARouteSettingsBaseViewController<UITableViewDelegate, UITableViewDataSource>

@property (nonatomic) id<OANavigationSettingsDelegate> delegate;

@end
