//
//  OAQuickActionListViewController.m
//  OsmAnd
//
//  Created by Paul on 8/15/19.
//  Copyright © 2019 OsmAnd. All rights reserved.
//

#import "OAQuickActionListViewController.h"
#import "OAActionConfigurationViewController.h"
#import "OAAddQuickActionViewController.h"
#import "Localization.h"
#import "OAQuickActionRegistry.h"
#import "OAQuickActionFactory.h"
#import "OAQuickAction.h"
#import "MGSwipeButton.h"
#import "OATitleDescrDraggableCell.h"
#import "OAMultiselectableHeaderView.h"
#import "OASizes.h"
#import "OAColors.h"

#import <AudioToolbox/AudioServices.h>

#define kHeaderId @"TableViewSectionHeader"

@interface OAQuickActionListViewController () <UITableViewDelegate, UITableViewDataSource, MGSwipeTableCellDelegate, OAMultiselectableHeaderDelegate>
@property (weak, nonatomic) IBOutlet UIView *navBarView;
@property (weak, nonatomic) IBOutlet UITableView *tableView;
@property (weak, nonatomic) IBOutlet UILabel *titleView;
@property (weak, nonatomic) IBOutlet UIButton *backBtn;
@property (weak, nonatomic) IBOutlet UIButton *btnAdd;
@property (weak, nonatomic) IBOutlet UIButton *btnEdit;
@property (weak, nonatomic) IBOutlet UIToolbar *toolBarView;
@property (weak, nonatomic) IBOutlet UIBarButtonItem *selectAllAction;
@property (weak, nonatomic) IBOutlet UIBarButtonItem *deleteAction;

@end

@implementation OAQuickActionListViewController
{
    OAQuickActionRegistry *_registry;
    NSMutableArray<OAQuickAction *> *_data;
    
    UIView *_tableHeaderView;
}

- (void)viewDidLoad
{
    [super viewDidLoad];
    [self commonInit];
    self.tableView.dataSource = self;
    self.tableView.delegate = self;
    [self.tableView registerClass:OAMultiselectableHeaderView.class forHeaderFooterViewReuseIdentifier:kHeaderId];
    [self.backBtn setImage:[[UIImage imageNamed:@"ic_navbar_chevron"] imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate] forState:UIControlStateNormal];
    [self.backBtn setTintColor:UIColor.whiteColor];
    [self.btnAdd setImage:[[UIImage imageNamed:@"ic_custom_plus"] imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate] forState:UIControlStateNormal];
    [self.btnAdd setTintColor:UIColor.whiteColor];
    [self.btnEdit setImage:[[UIImage imageNamed:@"ic_custom_edit"] imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate] forState:UIControlStateNormal];
    [self.btnEdit setTintColor:UIColor.whiteColor];
    self.tableView.tableHeaderView = _tableHeaderView;
}

- (void)viewWillAppear:(BOOL)animated
{
    [super viewWillAppear:animated];
    [self applySafeAreaMargins];
}

-(void) commonInit
{
    _registry = [OAQuickActionRegistry sharedInstance];
    _data = [NSMutableArray arrayWithArray:_registry.getQuickActions];
    
    CGFloat textWidth = DeviceScreenWidth - 32.0 - OAUtilities.getLeftMargin * 2;
    UIFont *labelFont = [UIFont systemFontOfSize:15.0];
    CGSize labelSize = [OAUtilities calculateTextBounds:OALocalizedString(@"quick_action_add_actions_descr") width:textWidth font:labelFont];
    _tableHeaderView = [[UIView alloc] initWithFrame:CGRectMake(0.0, 0.0, DeviceScreenWidth, labelSize.height + 30.0)];
    UILabel *label = [[UILabel alloc] initWithFrame:CGRectMake(16.0 + OAUtilities.getLeftMargin, 20.0, textWidth, labelSize.height)];
    label.text = OALocalizedString(@"quick_action_add_actions_descr");
    label.font = labelFont;
    label.textColor = UIColor.blackColor;
    label.backgroundColor = UIColor.clearColor;
    label.textAlignment = NSTextAlignmentCenter;
    label.numberOfLines = 0;
    label.lineBreakMode = NSLineBreakByWordWrapping;
    label.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    _tableHeaderView.backgroundColor = UIColor.clearColor;
    [_tableHeaderView addSubview:label];
}

- (void)applyLocalization
{
    _titleView.text = OALocalizedString(@"quick_action_name");
    [_deleteAction setTitle:OALocalizedString(@"shared_string_delete")];
    [_selectAllAction setTitle:OALocalizedString(@"select_all")];
}

-(UIView *) getTopView
{
    return _navBarView;
}

-(UIView *) getMiddleView
{
    return _tableView;
}

- (IBAction)backPressed:(id)sender
{
    [self.navigationController popViewControllerAnimated:YES];
}

- (void)saveChanges
{
    [_registry updateQuickActions:[NSArray arrayWithArray:_data]];
    [_registry.quickActionListChangedObservable notifyEvent];
}

- (IBAction)editPressed:(id)sender
{
    [self.tableView beginUpdates];
    BOOL shouldEdit = ![self.tableView isEditing];
    [self.tableView setEditing:shouldEdit animated:YES];
    [UIView transitionWithView:_toolBarView
                      duration:0.3
                       options:UIViewAnimationOptionTransitionCrossDissolve
                    animations:^(void){
                        _toolBarView.hidden = !shouldEdit;
                    }
                    completion:nil];
    [self applySafeAreaMargins];
    if (!shouldEdit)
    {
        [self saveChanges];
    }
    [self.tableView endUpdates];
}

- (IBAction)addActionPressed:(id)sender
{
    OAAddQuickActionViewController *vc = [[OAAddQuickActionViewController alloc] init];
    [self.navigationController pushViewController:vc animated:YES];
}


- (void) openQuickActionSetupFor:(NSIndexPath *)indexPath
{
    OAQuickAction *item = [self getAction:indexPath];
    OAActionConfigurationViewController *actionScreen = [[OAActionConfigurationViewController alloc] initWithAction:item isNew:NO];
    [self.navigationController pushViewController:actionScreen animated:YES];
}

- (NSInteger)getScreensCount
{
    NSInteger numOfItems = _data.count;
    BOOL oneSection = numOfItems / 6 < 1;
    BOOL hasRemainder = numOfItems % 6 != 0;
    if (oneSection)
        return 1;
    else
        return (numOfItems / 6) + (hasRemainder ? 1 : 0);
}

- (OAQuickAction *) getAction:(NSIndexPath *)indexPath
{
    return _data[6 * indexPath.section + indexPath.row];
}

- (IBAction)selectAllPressed:(id)sender
{
    NSInteger sections = self.tableView.numberOfSections;
    
    [self.tableView beginUpdates];
    for (NSInteger section = 0; section < sections; section++)
    {
        NSInteger rowsCount = [self.tableView numberOfRowsInSection:section];
        for (NSInteger row = 0; row < rowsCount; row++)
        {
            [self.tableView selectRowAtIndexPath:[NSIndexPath indexPathForRow:row inSection:section] animated:YES scrollPosition:UITableViewScrollPositionNone];
        }
    }
    [self.tableView endUpdates];
}

- (IBAction)deletePressed:(id)sender
{
    
    NSArray *indexes = [self.tableView indexPathsForSelectedRows];
    if (indexes.count > 0)
    {
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:nil message:
                                    [NSString stringWithFormat:OALocalizedString(@"confirm_bulk_delete"), indexes.count]
                                                                preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:OALocalizedString(@"shared_string_cancel") style:UIAlertActionStyleDefault handler:nil]];
        [alert addAction:[UIAlertAction actionWithTitle:OALocalizedString(@"shared_string_ok") style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
            for (NSIndexPath *path in indexes)
            {
                OAQuickAction *item = [self getAction:path];
                [_data removeObject:item];
            }
            [self saveChanges];
            [self.tableView reloadData];
        }]];
        [self presentViewController:alert animated:YES completion:nil];
    }
    [self editPressed:nil];
}

- (void)applySafeAreaMargins
{
    [super applySafeAreaMargins];
    UIEdgeInsets contentInset = _tableView.contentInset;
    contentInset.bottom = _toolBarView.hidden ? 0. : _toolBarView.frame.size.height;
    _tableView.contentInset = contentInset;
}

- (void)viewWillTransitionToSize:(CGSize)size withTransitionCoordinator:(id<UIViewControllerTransitionCoordinator>)coordinator
{
    [super viewWillTransitionToSize:size withTransitionCoordinator:coordinator];
    [coordinator animateAlongsideTransition:^(id<UIViewControllerTransitionCoordinatorContext>  _Nonnull context) {
        CGFloat textWidth = DeviceScreenWidth - 32.0 - OAUtilities.getLeftMargin * 2;
        UIFont *labelFont = [UIFont systemFontOfSize:15.0];
        CGSize labelSize = [OAUtilities calculateTextBounds:OALocalizedString(@"quick_action_add_actions_descr") width:textWidth font:labelFont];
        _tableHeaderView.frame = CGRectMake(0.0, 0.0, DeviceScreenWidth, labelSize.height + 30.0);
        _tableHeaderView.subviews.firstObject.frame = CGRectMake(16.0 + OAUtilities.getLeftMargin, 20.0, textWidth, labelSize.height);
    } completion:nil];
    
}

#pragma mark - UITableViewDelegate

- (UIView *)tableView:(UITableView *)tableView viewForHeaderInSection:(NSInteger)section
{
    OAMultiselectableHeaderView *vw = (OAMultiselectableHeaderView *)[tableView dequeueReusableHeaderFooterViewWithIdentifier:kHeaderId];
    [vw setTitleText:[NSString stringWithFormat:OALocalizedString(@"quick_action_screen_header"), section + 1]];
    vw.delegate = self;
    return vw;
}

- (CGFloat)tableView:(UITableView *)tableView heightForHeaderInSection:(NSInteger)section
{
    return 46.0;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath
{
    if (_tableView.isEditing)
        return;
    
    [self openQuickActionSetupFor:indexPath];
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
}

- (void)tableView:(UITableView *)tableView moveRowAtIndexPath:(NSIndexPath *)sourceIndexPath toIndexPath:(NSIndexPath *)destinationIndexPath
{
    AudioServicesPlayAlertSound(kSystemSoundID_Vibrate);
    OAQuickAction *sourceAction = [self getAction:sourceIndexPath];
    OAQuickAction *destAction = [self getAction:destinationIndexPath];
    [_data setObject:sourceAction atIndexedSubscript:destinationIndexPath.section * 6 + destinationIndexPath.row];
    [_data setObject:destAction atIndexedSubscript:sourceIndexPath.section * 6 + sourceIndexPath.row];
    [_tableView reloadData];
}

- (BOOL)tableView:(UITableView *)tableView canEditRowAtIndexPath:(NSIndexPath *)indexPath
{
    return tableView.isEditing;
}

#pragma mark - UITableViewDataSource

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
    OAQuickAction *action = [self getAction:indexPath];
    OATitleDescrDraggableCell* cell = (OATitleDescrDraggableCell *)[tableView dequeueReusableCellWithIdentifier:@"OATitleDescrDraggableCell"];
    if (cell == nil)
    {
        NSArray *nib = [[NSBundle mainBundle] loadNibNamed:@"OATitleDescrDraggableCell" owner:self options:nil];
        cell = (OATitleDescrDraggableCell *)[nib objectAtIndex:0];
    }
    
    if (cell)
    {
        [cell.textView setText:action.getName];
        [cell.descView setText:@""];
        [cell.iconView setImage:[UIImage imageNamed:action.getIconResName]];
        if (cell.iconView.subviews.count > 0)
            [[cell.iconView subviews] makeObjectsPerformSelector:@selector(removeFromSuperview)];
        
        if (action.hasSecondaryIcon)
        {
            CGRect frame = CGRectMake(0., 0., cell.iconView.frame.size.width, cell.iconView.frame.size.height);
            UIImage *imgBackground = [[UIImage imageNamed:@"ic_custom_compound_action_background"] imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
            UIImageView *background = [[UIImageView alloc] initWithImage:imgBackground];
            [background setTintColor:UIColor.whiteColor];
            [cell.iconView addSubview:background];
            UIImage *img = [UIImage imageNamed:action.getSecondaryIconName];
            UIImageView *view = [[UIImageView alloc] initWithImage:img];
            view.frame = frame;
            [cell.iconView addSubview:view];
        }
        cell.delegate = self;
        cell.allowsSwipeWhenEditing = NO;
        [cell.overflowButton setImage:[[UIImage imageNamed:@"menu_cell_pointer.png"] imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate] forState:UIControlStateNormal];
        [cell.overflowButton setTintColor:UIColorFromRGB(color_tint_gray)];
        [cell.overflowButton.imageView setContentMode:UIViewContentModeCenter];
        cell.separatorInset = UIEdgeInsetsMake(0.0, 62.0, 0.0, 0.0);
        cell.tintColor = UIColorFromRGB(color_primary_purple);
    }
    return cell;
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView
{
    return [self getScreensCount];
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section
{
    BOOL oneSection = _data.count / 6 < 1;
    BOOL lastSection = section == _data.count / 6;
    return oneSection || lastSection ? _data.count % 6 : 6;
}

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath
{
    return [OATitleDescrDraggableCell getHeight:_data.firstObject.getName value:@"" cellWidth:DeviceScreenWidth];
}

#pragma mark - Swipe Delegate

- (BOOL) swipeTableCell:(MGSwipeTableCell *)cell canSwipe:(MGSwipeDirection)direction;
{
    return _tableView.isEditing;
}

- (void) swipeTableCell:(MGSwipeTableCell *)cell didChangeSwipeState:(MGSwipeState)state gestureIsActive:(BOOL)gestureIsActive
{
    if (state != MGSwipeStateNone)
        cell.showsReorderControl = NO;
    else
        cell.showsReorderControl = YES;
}

#pragma mark - OAMultiselectableHeaderDelegate

-(void)headerCheckboxChanged:(id)sender value:(BOOL)value
{
    OAMultiselectableHeaderView *headerView = (OAMultiselectableHeaderView *)sender;
    NSInteger section = headerView.section;
    NSInteger rowsCount = [self.tableView numberOfRowsInSection:section];
    
    [self.tableView beginUpdates];
    if (value)
    {
        for (int i = 0; i < rowsCount; i++)
            [self.tableView selectRowAtIndexPath:[NSIndexPath indexPathForRow:i inSection:section] animated:YES scrollPosition:UITableViewScrollPositionNone];
    }
    else
    {
        for (int i = 0; i < rowsCount; i++)
            [self.tableView deselectRowAtIndexPath:[NSIndexPath indexPathForRow:i inSection:section] animated:YES];
    }
    [self.tableView endUpdates];
}

@end
