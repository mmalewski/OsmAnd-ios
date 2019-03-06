//
//  OABasicEditingViewController.m
//  OsmAnd
//
//  Created by Paul on 2/20/19.
//  Copyright © 2019 OsmAnd. All rights reserved.
//

#import "OABasicEditingViewController.h"
#import "OAOsmEditingViewController.h"
#import "OAEditPOIData.h"
#import "Localization.h"
#import "OATextInputFloatingCell.h"
#import "OASettingsTableViewCell.h"
#import "OAEntity.h"
#import "MaterialTextFields.h"
#import "OAColors.h"
#import "OAPOICategory.h"
#import "OAPOIType.h"
#import "OAPoiTypeSelectionViewController.h"
#import "OAPOIHelper.h"
#import "OAOSMSettings.h"
#import "OAButtonCell.h"
#import "OAOpeningHoursSelectionViewController.h"

#include <openingHoursParser.h>

#define kCellTypeTextInput @"text_input_cell"
#define kCellTypeSetting @"settings_cell"
#define kCellTypeButton @"button"

@interface OABasicEditingViewController () <UITextViewDelegate, MDCMultilineTextInputLayoutDelegate>

@end

static const NSInteger _nameSectionIndex = 0;
static const NSInteger _nameSectionItemCount = 1;
static const NSInteger _poiSectionIndex = 1;
static const NSInteger _hoursSectionIndex = 2;
static const NSInteger _contactInfoSectionIndex = 3;
static const NSInteger _contactInfoSectionCount = 5;

@implementation OABasicEditingViewController
{
    OAEditPOIData *_poiData;
    id<OAOsmEditingDataProtocol> _dataProvider;
    
    NSArray *_poiSectionItems;
    NSArray *_hoursSectionItems;
    NSArray *_contactInfoItems;
    
    OATextInputFloatingCell *_poiNameCell;
    
    NSMutableArray *_floatingTextFieldControllers;
    
    std::shared_ptr<OpeningHoursParser::OpeningHours> _openingHours;
}

- (instancetype)initWithFrame:(CGRect)frame
{
    self = [[OABasicEditingViewController alloc] initWithNibName:@"OABasicEditingViewController" bundle:nil];
    if (self)
    {
        self.view.frame = frame;
    }
    return self;
}

-(void) setDataProvider:(id<OAOsmEditingDataProtocol>)provider
{
    _dataProvider = provider;
}

- (OATextInputFloatingCell *)getInputCellWithHint:(NSString *)hint text:(NSString *)text isFloating:(BOOL)isFloating
{
    NSArray *nib = [[NSBundle mainBundle] loadNibNamed:@"OATextInputFloatingCell" owner:self options:nil];
    OATextInputFloatingCell *resultCell = (OATextInputFloatingCell *)[nib objectAtIndex:0];
    
    [resultCell.inputField.underline removeFromSuperview];
    resultCell.inputField.placeholder = hint;
    [resultCell.inputField.textView setText:text];
    resultCell.inputField.textView.delegate = self;
    resultCell.inputField.layoutDelegate = self;
    resultCell.inputField.font = [UIFont systemFontOfSize:17.0];
    resultCell.inputField.clearButton.imageView.tintColor = UIColorFromRGB(color_icon_color);
    [resultCell.inputField.clearButton setImage:[[UIImage imageNamed:@"ic_custom_clear_field"] imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate] forState:UIControlStateNormal];
    [resultCell.inputField.clearButton setImage:[[UIImage imageNamed:@"ic_custom_clear_field"] imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate] forState:UIControlStateHighlighted];
    if (!_floatingTextFieldControllers)
        _floatingTextFieldControllers = [NSMutableArray new];
    if (isFloating)
    {
        MDCTextInputControllerUnderline *fieldController = [[MDCTextInputControllerUnderline alloc] initWithTextInput:resultCell.inputField];
        fieldController.inlinePlaceholderFont = [UIFont systemFontOfSize:16.0];
        fieldController.floatingPlaceholderActiveColor = fieldController.floatingPlaceholderNormalColor;
        fieldController.textInput.textInsetsMode = MDCTextInputTextInsetsModeIfContent;
        [_floatingTextFieldControllers addObject:fieldController];
        
    }
    return resultCell;
}

- (void)viewDidLoad {
    [super viewDidLoad];
}

- (void) viewWillAppear:(BOOL)animated
{
    [super viewWillAppear:animated];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(keyboardWillShow:) name:UIKeyboardWillShowNotification object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(keyboardWillHide:) name:UIKeyboardWillHideNotification object:nil];
    [self setupView];
}

- (void) viewWillDisappear:(BOOL)animated
{
    [super viewWillDisappear:animated];
    
    [[NSNotificationCenter defaultCenter] removeObserver:self name:UIKeyboardWillShowNotification object:nil];
    [[NSNotificationCenter defaultCenter] removeObserver:self name:UIKeyboardWillHideNotification object:nil];
}

-(void) populatePoiSection
{
    NSMutableArray *dataArr = [NSMutableArray new];
    [dataArr addObject:@{
                         @"name" : @"poi_category",
                         @"title" : OALocalizedString(@"shared_string_category"),
                         @"value" : _poiData.getPoiCategory != [OAPOIHelper sharedInstance].otherPoiCategory ? _poiData.getPoiCategory.nameLocalized :
                             OALocalizedString(@"shared_string_select"),
                         @"type" : kCellTypeSetting,
                         }];
    [dataArr addObject:@{
                         @"name" : @"poi_type",
                         @"title" : OALocalizedString(@"poi_type"),
                         @"value" : _poiData.getPoiTypeString.length > 0 ? _poiData.getPoiTypeString :
                             OALocalizedString(@"shared_string_select"),
                         @"type" : kCellTypeSetting,
                         }];
    _poiSectionItems = [NSArray arrayWithArray:dataArr];
}

- (void) setupView
{
    _poiData = _dataProvider.getData;
    _poiNameCell = [self getInputCellWithHint:OALocalizedString(@"fav_name") text:[_poiData getTag:[OAOSMSettings getOSMKey:NAME]] isFloating:NO];
    [self populatePoiSection];
    [self populateOpeningHours];
    [self populateContactInfo];
}

-(void)populateContactInfo
{
    _floatingTextFieldControllers = [[NSMutableArray alloc] initWithCapacity:_contactInfoSectionCount];
    NSMutableArray *dataArr = [NSMutableArray new];
    NSArray *hints = @[OALocalizedString(@"osm_str_name"), OALocalizedString(@"osm_building_num"),
                       OALocalizedString(@"osm_phone"), OALocalizedString(@"osm_website"), OALocalizedString(@"description")];
    for (NSInteger i  = 0; i < _contactInfoSectionCount; i++) {
        OATextInputFloatingCell *cell = [self getInputCellWithHint:hints[i] text:[self getDataForField:i] isFloating:YES];
        cell.inputField.contentScaleFactor = 0.5;
        [dataArr addObject:cell];
    }
    _contactInfoItems = [NSArray arrayWithArray:dataArr];
}

-(NSString *)getDataForField:(NSInteger)index
{
    switch (index) {
        case 0:
            return [_poiData getTag:[OAOSMSettings getOSMKey:ADDR_STREET]];
        case 1:
            return [_poiData getTag:[OAOSMSettings getOSMKey:ADDR_HOUSE_NUMBER]];
        case 2:
            return [_poiData getTag:[OAOSMSettings getOSMKey:PHONE]];
        case 3:
            return [_poiData getTag:[OAOSMSettings getOSMKey:WEBSITE]];
        case 4:
            return [_poiData getTag:[OAOSMSettings getOSMKey:DESCRIPTION]];
        default:
            return @"";
    }
}

-(void) populateOpeningHours
{
    NSMutableArray *dataArr = [NSMutableArray new];
    NSString *openingHoursString = [_poiData getTag:[OAOSMSettings getOSMKey:OPENING_HOURS]];
    if (openingHoursString && openingHoursString.length > 0)
    {
        _openingHours = OpeningHoursParser::parseOpenedHours([openingHoursString UTF8String]);
        for (const auto& rule : _openingHours->getRules())
        {
            [dataArr addObject:@{
                                 @"title" : [NSString stringWithUTF8String:rule->toLocalRuleString().c_str()],
                                 @"type" : kCellTypeSetting
                                 }];
        }
    }
    [dataArr addObject:@{
                         @"title" : OALocalizedString(@"osm_add_timespan"),
                         @"type" : kCellTypeButton
                         }];
    _hoursSectionItems = [NSArray arrayWithArray:dataArr];
}

-(NSDictionary *)getItem:(NSIndexPath *)indexPath
{
    if (indexPath.section == _poiSectionIndex)
        return _poiSectionItems[indexPath.row];
    else if (indexPath.section == _hoursSectionIndex)
        return _hoursSectionItems[indexPath.row];
    else
        return [NSDictionary new];
}

#pragma mark - Table view data source

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return 4;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    switch (section) {
        case _nameSectionIndex:
            return _nameSectionItemCount;
        case _poiSectionIndex:
            return _poiSectionItems.count;
        case _hoursSectionIndex:
            return _hoursSectionItems.count;
        case _contactInfoSectionIndex:
            return _contactInfoSectionCount;
        default:
            return 1;
    }
}


- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    NSDictionary *item = [self getItem:indexPath];
    if (indexPath.section == _nameSectionIndex && indexPath.row == 0)
        return _poiNameCell;
    else if (indexPath.section == _contactInfoSectionIndex)
    {
        OATextInputFloatingCell *cell = _contactInfoItems[indexPath.row];
        switch (indexPath.row) {
            case 1:
                cell.inputField.textView.keyboardType = UIKeyboardTypeNumberPad;
                break;
            case 2:
                cell.inputField.textView.keyboardType = UIKeyboardTypePhonePad;
                break;
            case 3:
                cell.inputField.textView.keyboardType = UIKeyboardTypeURL;
                break;
            default:
                break;
        }
        return cell;
    }
    
    else if ([item[@"type"] isEqualToString:kCellTypeSetting])
    {
        static NSString* const identifierCell = @"OASettingsTableViewCell";
        OASettingsTableViewCell* cell = [tableView dequeueReusableCellWithIdentifier:identifierCell];
        if (cell == nil)
        {
            NSArray *nib = [[NSBundle mainBundle] loadNibNamed:@"OASettingsCell" owner:self options:nil];
            cell = (OASettingsTableViewCell *)[nib objectAtIndex:0];
        }
        
        if (cell) {
            [cell.textView setText:item[@"title"]];
            [cell.descriptionView setText:item[@"value"]];
        }
        return cell;
    }
    else if ([item[@"type"] isEqualToString:kCellTypeButton])
    {
        static NSString* const identifierCell = @"OAButtonCell";
        OAButtonCell* cell = nil;
        
        cell = [self.tableView dequeueReusableCellWithIdentifier:identifierCell];
        if (cell == nil)
        {
            NSArray *nib = [[NSBundle mainBundle] loadNibNamed:@"OAButtonCell" owner:self options:nil];
            cell = (OAButtonCell *)[nib objectAtIndex:0];
        }
        if (cell)
        {
            [cell.button setTitle:item[@"title"] forState:UIControlStateNormal];
            [cell.button addTarget:self action:@selector(addOpeningHours) forControlEvents:UIControlEventTouchDown];
        }
        return cell;
    }

    return nil;
}

-(void) addOpeningHours
{
    OAOpeningHoursSelectionViewController *openingHoursSelection = [[OAOpeningHoursSelectionViewController alloc] initWithEditData:_poiData openingHours:_openingHours ruleIndex:-1];
    [self.navigationController pushViewController:openingHoursSelection animated:YES];
}

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath {
    NSDictionary *item = [self getItem:indexPath];
    if (indexPath.section == _nameSectionIndex)
        return MAX(_poiNameCell.inputField.intrinsicContentSize.height, 44.0);
    else if ([item[@"type"] isEqualToString:kCellTypeSetting])
        return [OASettingsTableViewCell getHeight:item[@"title"] value:item[@"value"] cellWidth:self.tableView.bounds.size.width];
    else if (indexPath.section == _contactInfoSectionIndex)
        return MAX(((OATextInputFloatingCell *)_contactInfoItems[indexPath.row]).inputField.intrinsicContentSize.height, 60.0);
    else
        return 44.0;
}

- (NSString *) tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section
{
    if (section == _nameSectionIndex)
        return OALocalizedString(@"fav_name");
    else if (section == _poiSectionIndex)
        return OALocalizedString(@"poi_category_and_type");
    else if (section == _hoursSectionIndex)
        return OALocalizedString(@"poi_opening_hours");
    else if (section == _contactInfoSectionIndex)
        return OALocalizedString(@"osm_editing_contact_info");
    else
        return @"";
}

#pragma mark - UITextViewDelegate
-(void)textViewDidChange:(UITextView *)textView
{
//    [UIView setAnimationsEnabled:NO];
//    [textView sizeToFit];
//    [self.tableView beginUpdates];
//    [self.tableView endUpdates];
//    [UIView setAnimationsEnabled:YES];
}

- (void)multilineTextField:(id<MDCMultilineTextInput> _Nonnull)multilineTextField
      didChangeContentSize:(CGSize)size
{
    [self.tableView beginUpdates];
    [self.tableView endUpdates];
}


#pragma mark - Table view delegate

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    NSDictionary *item = [self getItem:indexPath];
    if ([item[@"type"] isEqualToString:kCellTypeSetting] && indexPath.section == _poiSectionIndex)
    {
        OAPoiTypeSelectionViewController *detailViewController = [[OAPoiTypeSelectionViewController alloc]
                                                                  initWithType:(indexPath.row == 0 ? CATEGORY_SCREEN : POI_TYPE_SCREEN)];
        detailViewController.dataProvider = _dataProvider;
        [self.navigationController pushViewController:detailViewController animated:YES];
    }
    else if ([item[@"type"] isEqualToString:kCellTypeSetting] && indexPath.section == _hoursSectionIndex)
    {
        OAOpeningHoursSelectionViewController *openingHoursSelection = [[OAOpeningHoursSelectionViewController alloc] initWithEditData:_poiData openingHours:_openingHours ruleIndex:indexPath.row];
        [self.navigationController pushViewController:openingHoursSelection animated:YES];
    }
}

#pragma mark - Keyboard Notifications

- (void) keyboardWillShow:(NSNotification *)notification;
{
//    NSDictionary *userInfo = [notification userInfo];
//    NSValue *keyboardBoundsValue = [userInfo objectForKey:UIKeyboardFrameEndUserInfoKey];
//    CGFloat keyboardHeight = [keyboardBoundsValue CGRectValue].size.height;
//
//    CGFloat duration = [[userInfo objectForKey:UIKeyboardAnimationDurationUserInfoKey] floatValue];
//    NSInteger animationCurve = [[userInfo objectForKey:UIKeyboardAnimationCurveUserInfoKey] integerValue];
//    UIEdgeInsets insets = [[self tableView] contentInset];
//    [UIView animateWithDuration:duration delay:0. options:animationCurve animations:^{
//        [[self tableView] setContentInset:UIEdgeInsetsMake(insets.top, insets.left, keyboardHeight, insets.right)];
//        [[self view] layoutIfNeeded];
//    } completion:nil];
}

- (void) keyboardWillHide:(NSNotification *)notification;
{
//    NSDictionary *userInfo = [notification userInfo];
//    CGFloat duration = [[userInfo objectForKey:UIKeyboardAnimationDurationUserInfoKey] floatValue];
//    NSInteger animationCurve = [[userInfo objectForKey:UIKeyboardAnimationCurveUserInfoKey] integerValue];
//    UIEdgeInsets insets = [[self tableView] contentInset];
//    [UIView animateWithDuration:duration delay:0. options:animationCurve animations:^{
//        [[self tableView] setContentInset:UIEdgeInsetsMake(insets.top, insets.left, 0., insets.right)];
//        [[self view] layoutIfNeeded];
//    } completion:nil];
}


@end
