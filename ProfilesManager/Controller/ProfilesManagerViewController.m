//
//  ProfilesToolViewController.m
//  ProfilesManager
//
//  Created by Jakey on 15/4/30.
//  Copyright (c) 2015年 Jakey. All rights reserved.
//

#import "ProfilesManagerViewController.h"
#import "ProfilesNode.h"
#import "NSOutlineView+Menu.h"
#import "NSFileManager+Trash.h"
#import "iAlert.h"
#import "PreviewViewController.h"
#import "PlistManager.h"
#import "DateManager.h"
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>
//#include <unistd.h>
//#include <sys/types.h>
//#include <pwd.h>
//#include <assert.h>
static NSString *kColumnIdentifierKey = @"key";
//    static NSString *kColumnIdentifierName = @"name";
static NSString *kColumnIdentifierType = @"type";
static NSString *kColumnIdentifierDetal = @"detail";
//    static NSString *kColumnIdentifierUUID = @"uuid";
static NSString *kColumnIdentifierExpirationDate = @"expirationDate";
static NSString *kColumnIdentifierCreateDate = @"creationDate";
static NSString *kColumnIdentifierCreateDays = @"days";
static NSString *kColumnIdentifierProfileType = @"profileType";
static NSString *kColumnIdentifierPlatform = @"platform";
static NSString *kColumnIdentifierTeam = @"teamName";
static NSString *kColumnIdentifierDevices = @"deviceCount";
static NSString *kColumnIdentifierSigning = @"signStatus";
static NSString *kColumnIdentifierManaged = @"managed";
static NSString *kColumnIdentifierCapabilities = @"capabilities";
static NSString *kHiddenColumnsKey = @"HiddenColumns";

@implementation ProfilesManagerViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    // Do view setup here.
    [self createDir];
    [self treeViewBuilder];
}

- (void)createDir {
    _profileDir = [NSString stringWithFormat:@"%@/Library/MobileDevice/Provisioning Profiles/", [[NSFileManager defaultManager] realHomeDirectory]];
    _profileDir2 = [NSString stringWithFormat:@"%@/Library/Developer/Xcode/UserData/Provisioning Profiles/", [[NSFileManager defaultManager] realHomeDirectory]];
    _backupDir = [NSString stringWithFormat:@"%@/Library/MobileDevice/Provisioning Profiles Rename Backup/", [[NSFileManager defaultManager] realHomeDirectory]];

    if (![[NSFileManager defaultManager] fileExistsAtPath:_backupDir]) {
        [[NSFileManager defaultManager] createDirectoryAtPath:_backupDir withIntermediateDirectories:YES attributes:nil error:nil];
    }
   
    if (![[NSFileManager defaultManager] fileExistsAtPath:_profileDir]) {
        [[NSFileManager defaultManager] createDirectoryAtPath:_profileDir withIntermediateDirectories:YES attributes:nil error:nil];
    }
}

//Xcode 16+ 只读取 UserData/Provisioning Profiles，存在该目录时优先安装到这里
- (NSString *)installDir {
    if ([[NSFileManager defaultManager] fileExistsAtPath:_profileDir2]) {
        return _profileDir2;
    }
    return _profileDir;
}

- (void)installProfileAtPath:(NSString *)path {
    NSError *error;
    [[NSFileManager defaultManager] copyItemAtPath:path toPath:[[self installDir] stringByAppendingString:[path lastPathComponent] ? : @""] error:&error];
    if (error) {
        [iAlert showMessage:[error localizedDescription]
                     window:self.view.window completionHandler:^(NSModalResponse returnCode) {
        }];
    }
}

- (void)treeViewBuilder {
    //当拖拽窗口大小，NSOutlineView frame自动更改时，Column宽等比增减
    [self.treeView setColumnAutoresizingStyle:NSTableViewUniformColumnAutoresizingStyle];
    //最后一行自动宽等比增减
    //    [self.treeView sizeLastColumnToFit];
    //app第一次运行Column 最后一行自动宽等比增减，否则会有滚动条
    [self.treeView sizeToFit];
    self.treeView.allowsMultipleSelection = YES;
    [self setupHeaderMenu];
    
    [self loadProfileFilesWithSearchWord:_searchWord];
    //drag file
    [self.treeView didDragEndBlock:^(NSArray *list, NSOutlineView *view) {
        for (NSString *result in list) {
            if (result && ([[result lowercaseString] hasSuffix:@"mobileprovision"] || [[result lowercaseString] hasSuffix:@"provisionprofile"])) {
                [self installProfileAtPath:result];
            }
        }
        [self loadProfileFilesWithSearchWord:_searchWord];
        if ([list count] == 1 && [[[list firstObject]lowercaseString] hasSuffix:@"ipa"]) {
            PreviewViewController *preview = [[PreviewViewController alloc]initWithIPA:[list firstObject]];
            [self presentViewControllerAsModalWindow:preview];
        }
    }];
}
- (void)scanProfiles:(NSString *)path into:(NSMutableDictionary *)provisions plistStrings:(NSMutableDictionary *)plistStrings {
    NSArray *profileNames =  [[[NSFileManager defaultManager] subpathsAtPath:path] pathsMatchingExtensions:@[@"mobileprovision", @"MOBILEPROVISION", @"provisionprofile", @"PROVISIONPROFILE"]];

    for (NSString *fileName in profileNames) {
        NSString *plistString;
        NSMutableDictionary *dic = [[PlistManager readPlist:[path stringByAppendingString:fileName] plistString:&plistString] mutableCopy];
        
        if (dic) {
            dic[@"filePath"] = [path stringByAppendingString:fileName];
            dic[@"baseDir"] = path;
            provisions[fileName] = dic;
            plistStrings[fileName] = [plistString lowercaseString] ?: @"";
        }
    }
}

//同一 AppID、类型、Team 有多个描述文件时，只有最新创建的那个是当前版本
- (NSSet *)outdatedUUIDsInProvisions:(NSDictionary *)provisions {
    NSMutableDictionary<NSString *, NSDictionary *> *newest = [NSMutableDictionary dictionary];
    for (NSDictionary *info in provisions.allValues) {
        NSString *groupKey = [self groupKeyForProfile:info];
        NSDictionary *current = newest[groupKey];
        if (!current || [info[@"CreationDate"] compare:current[@"CreationDate"]] == NSOrderedDescending) {
            newest[groupKey] = info;
        }
    }
    NSMutableSet *outdated = [NSMutableSet set];
    for (NSDictionary *info in provisions.allValues) {
        NSDictionary *current = newest[[self groupKeyForProfile:info]];
        if ([info[@"CreationDate"] compare:current[@"CreationDate"]] == NSOrderedAscending && info[@"UUID"]) {
            [outdated addObject:info[@"UUID"]];
        }
    }
    return outdated;
}

- (NSString *)groupKeyForProfile:(NSDictionary *)info {
    NSDictionary *entitlements = info[@"Entitlements"];
    NSString *appID = [entitlements isKindOfClass:[NSDictionary class]] ? [entitlements[@"application-identifier"] ?: entitlements[@"com.apple.application-identifier"] description] : nil;
    return [NSString stringWithFormat:@"%@|%@|%@", appID ?: info[@"AppIDName"], [ProfilesNode profileTypeForInfo:info], [info[@"TeamIdentifier"] description]];
}

- (void)reloadProfiles {
    //钥匙串里的证书可能有变化
    [CertificateManager clearCache];
    [self loadProfileFilesWithSearchWord:_searchWord];
}

- (void)loadProfileFilesWithSearchWord:(NSString *)searchWord {
    _searchWord = searchWord;
    
    NSMutableDictionary *allProvisions = [NSMutableDictionary dictionary];
    NSMutableDictionary *plistStrings = [NSMutableDictionary dictionary];
    [self scanProfiles:_profileDir into:allProvisions plistStrings:plistStrings];
    [self scanProfiles:_profileDir2 into:allProvisions plistStrings:plistStrings];
    
    //先在全部描述文件里找旧版本，再按关键字过滤，避免过滤后误判
    NSSet *outdatedUUIDs = [self outdatedUUIDsInProvisions:allProvisions];
    
    NSMutableDictionary *provisions = allProvisions;
    if (searchWord.length > 0) {
        NSString *word = [searchWord lowercaseString];
        provisions = [NSMutableDictionary dictionary];
        [allProvisions enumerateKeysAndObjectsUsingBlock:^(NSString *fileName, NSDictionary *info, BOOL *stop) {
            if ([plistStrings[fileName] rangeOfString:word].location != NSNotFound) {
                provisions[fileName] = info;
            }
        }];
    }

    ProfilesNode *node = [[ProfilesNode alloc]initWithRootNode:nil originInfo:provisions key:@"Mobile Provisions"];
    for (ProfilesNode *child in node.childrenNodes) {
        if (child.status != ProfileStatusExpired && [outdatedUUIDs containsObject:child.uuid ?: @""]) {
            child.status = ProfileStatusOutdated;
        }
    }
    _rootNode = node;
    [self.treeView reloadData];
    [self updateStatus];
    
    for (NSTableColumn *tableColumn in self.treeView.tableColumns) {
        NSSortDescriptor *sortStates = [NSSortDescriptor sortDescriptorWithKey:tableColumn.identifier
                                                                     ascending:NO comparator:^(id obj1, id obj2) {
            if (!obj1 || !obj2) {
                return obj1 ? NSOrderedDescending : (obj2 ? NSOrderedAscending : NSOrderedSame);
            }
            //剩余天数等数字字符串按数值排序
            if ([obj1 isKindOfClass:[NSString class]] && [obj2 isKindOfClass:[NSString class]]) {
                return [obj1 localizedStandardCompare:obj2];
            }
            return [obj1 compare:obj2];
        }];
        [tableColumn setSortDescriptorPrototype:sortStates];
    }
}

#pragma mark - Column

- (void)setupHeaderMenu {
    NSArray *hiddenColumns = [[NSUserDefaults standardUserDefaults] arrayForKey:kHiddenColumnsKey];
    NSMenu *menu = [[NSMenu alloc] init];
    for (NSTableColumn *tableColumn in self.treeView.tableColumns) {
        if ([tableColumn.identifier isEqualToString:kColumnIdentifierKey]) {
            continue;
        }
        tableColumn.hidden = [hiddenColumns containsObject:tableColumn.identifier];
        NSMenuItem *item = [[NSMenuItem alloc] initWithTitle:tableColumn.headerCell.stringValue action:@selector(toggleColumn:) keyEquivalent:@""];
        item.target = self;
        item.representedObject = tableColumn;
        item.state = tableColumn.hidden ? NSControlStateValueOff : NSControlStateValueOn;
        [menu addItem:item];
    }
    self.treeView.headerView.menu = menu;
}

- (void)toggleColumn:(NSMenuItem *)item {
    NSTableColumn *tableColumn = item.representedObject;
    tableColumn.hidden = !tableColumn.hidden;
    item.state = tableColumn.hidden ? NSControlStateValueOff : NSControlStateValueOn;
    
    NSMutableArray *hiddenColumns = [NSMutableArray array];
    for (NSTableColumn *column in self.treeView.tableColumns) {
        if (column.hidden) {
            [hiddenColumns addObject:column.identifier];
        }
    }
    [[NSUserDefaults standardUserDefaults] setObject:hiddenColumns forKey:kHiddenColumnsKey];
}

#pragma mark - Outline

- (NSInteger)outlineView:(NSOutlineView *)outlineView numberOfChildrenOfItem:(id)item {
    ProfilesNode *realItem = item ? : _rootNode;
    return [realItem.childrenNodes count];
}

- (BOOL)outlineView:(NSOutlineView *)outlineView isItemExpandable:(id)item {
    ProfilesNode *realItem = item ? : _rootNode;
    return realItem.childrenNodes != nil;
}

- (id)outlineView:(NSOutlineView *)outlineView child:(NSInteger)index ofItem:(id)item {
    ProfilesNode *realItem = item ? : _rootNode;
    return realItem.childrenNodes[index];
}

- (id)outlineView:(NSOutlineView *)outlineView objectValueForTableColumn:(NSTableColumn *)tableColumn byItem:(id)item {
    ProfilesNode *realItem = item ? : _rootNode;
    
    if ([[tableColumn identifier] isEqualToString:kColumnIdentifierKey]) {
        return realItem.key;
    } else if ([[tableColumn identifier] isEqualToString:kColumnIdentifierType]) {
        return realItem.type;
    } else if ([[tableColumn identifier] isEqualToString:kColumnIdentifierDetal]) {
        return realItem.detail;
    } else if ([[tableColumn identifier] isEqualToString:kColumnIdentifierExpirationDate]) {
        return  [[DateManager sharedManager] stringConvert_YMDHM_FromDate:realItem.expirationDate];
    } else if ([[tableColumn identifier] isEqualToString:kColumnIdentifierCreateDate]) {
        return [[DateManager sharedManager] stringConvert_YMDHM_FromDate:realItem.creationDate];
    } else if ([[tableColumn identifier] isEqualToString:kColumnIdentifierCreateDays]) {
        return realItem.days;
    } else if ([[tableColumn identifier] isEqualToString:kColumnIdentifierProfileType]) {
        return realItem.profileType;
    } else if ([[tableColumn identifier] isEqualToString:kColumnIdentifierPlatform]) {
        return realItem.platform;
    } else if ([[tableColumn identifier] isEqualToString:kColumnIdentifierTeam]) {
        return realItem.teamName;
    } else if ([[tableColumn identifier] isEqualToString:kColumnIdentifierDevices]) {
        if (!realItem.deviceCount) return @"";
        if ([realItem.deviceCount integerValue] < 0) return JKLocalizedString(@"All", nil);
        if ([realItem.deviceCount integerValue] == 0) return @"-";
        return [realItem.deviceCount stringValue];
    } else if ([[tableColumn identifier] isEqualToString:kColumnIdentifierSigning]) {
        return realItem.signStatus;
    } else if ([[tableColumn identifier] isEqualToString:kColumnIdentifierManaged]) {
        return realItem.managed;
    } else if ([[tableColumn identifier] isEqualToString:kColumnIdentifierCapabilities]) {
        return realItem.capabilities;
    }
    return @"";
}

- (BOOL)outlineView:(NSOutlineView *)outlineView shouldSelectItem:(id)item {
    NSInteger selectedRow = [outlineView clickedRow];
    //    [outlineView setNeedsDisplayInRect:[outlineView rectOfRow:selectedRow]];
    NSLog(@"select is %zd", selectedRow);
    return YES;
}

- (void)outlineView:(NSOutlineView *)outlineView willDisplayCell:(NSTextFieldCell *)cell forTableColumn:(NSTableColumn *)tableColumn item:(id)item {
    ProfilesNode *realItem = item ? : _rootNode;
    NSString *identifier = [tableColumn identifier];
    
    if ([outlineView parentForItem:item] == nil) {
        if ([identifier isEqualToString:kColumnIdentifierType]) {
            cell.textColor = [NSColor labelColor];
        } else {
            cell.textColor = [NSColor secondaryLabelColor];
        }
        NSColor *statusColor = [self statusColorForItem:realItem];
        if (statusColor && ([identifier isEqualToString:kColumnIdentifierDetal] || [identifier isEqualToString:kColumnIdentifierCreateDays])) {
            cell.textColor = statusColor;
        }
        if ([identifier isEqualToString:kColumnIdentifierSigning]) {
            cell.textColor = realItem.signingStatus == CertificateSigningStatusReady ? [NSColor systemGreenColor] : [NSColor systemRedColor];
        }
        //旧版本整行变淡，方便清理
        if (realItem.status == ProfileStatusOutdated && ![identifier isEqualToString:kColumnIdentifierDetal]) {
            cell.textColor = [NSColor tertiaryLabelColor];
        }
        [cell setMenu:[self itemMenu]];
    } else {
        cell.textColor = [NSColor secondaryLabelColor];
        ProfilesNode *realItem = item;
        if ([realItem.rootNode.key isEqualToString:@"DeveloperCertificates"]) {
            [cell setMenu:[self certificateMenu]];
        } else {
            [cell setMenu:nil];
        }
    }
    
    if (cell.highlighted) {
        cell.textColor = [NSColor alternateSelectedControlTextColor];
    }
}

- (NSColor *)statusColorForItem:(ProfilesNode *)item {
    switch (item.status) {
        case ProfileStatusExpired:
            return [NSColor systemRedColor];
        case ProfileStatusExpiringSoon:
            return [NSColor systemOrangeColor];
        case ProfileStatusOutdated:
            return [NSColor systemBrownColor];
        default:
            return nil;
    }
}

- (void)outlineView:(NSOutlineView *)outlineView sortDescriptorsDidChange:(NSArray<NSSortDescriptor *> *)oldDescriptors {
    NSSortDescriptor *sortDescriptor = [[outlineView sortDescriptors] objectAtIndex:0];
    
    NSArray *sortedArray;
    NSMutableArray *currChildren = [_rootNode.childrenNodes mutableCopy];
    sortedArray = [currChildren sortedArrayUsingDescriptors:@[sortDescriptor]];
    _rootNode.childrenNodes = sortedArray;
    [outlineView reloadData];
}

- (void)outlineViewSelectionDidChange:(NSNotification *)notification {
    [self updateStatus];
}

#pragma mark -
#pragma mark NSMenuDelegate
- (void)rightMouseDown:(NSEvent *)theEvent {
    NSPoint location = [self.treeView convertPoint:[theEvent locationInWindow] fromView:nil];
    //    NSInteger i =  [self.treeView rowAtPoint:pt];
    [[self mainMenu] popUpMenuPositioningItem:nil atLocation:location inView:self.treeView];
}

- (NSMenu *)certificateMenu {
    if (!_certificateMenu) {
        _certificateMenu = [[NSMenu alloc]init];
        _certificateMenu.delegate = self;
    }
    return _certificateMenu;
}

- (NSMenu *)itemMenu {
    if (!_itemMenu) {
        _itemMenu = [[NSMenu alloc]init];
        _itemMenu.delegate = self;
    }
    return _itemMenu;
}

- (NSMenu *)mainMenu {
    if (!_mainMenu) {
        _mainMenu = [[NSMenu alloc]init];
        _mainMenu.delegate = self;
    }
    return _mainMenu;
}

- (void)menuWillOpen:(NSMenu *)menu
{
    if (menu == _itemMenu) {
        NSMenuItem *copyPathItem = [menu itemWithTag:1007];
        if (!copyPathItem) {
            copyPathItem = [[NSMenuItem alloc] initWithTitle:JKLocalizedString(@"Copy Profile path", nil) action:@selector(copyProfilePath:) keyEquivalent:@""];
            [copyPathItem setTarget:self];
            [copyPathItem setTag:1007];
            [menu addItem:copyPathItem];
        }
        
        NSMenuItem *gotoItemName = [menu itemWithTag:1002];
        if (!gotoItemName) {
            gotoItemName = [[NSMenuItem alloc] initWithTitle:JKLocalizedString(@"Show in Finder", nil) action:@selector(showInFinder:) keyEquivalent:@""];
            [gotoItemName setTarget:self];
            [gotoItemName setTag:1002];
            [menu addItem:gotoItemName];
        }
        NSMenuItem *moveTrashItem = [menu itemWithTag:1000];
        if (!moveTrashItem) {
            moveTrashItem = [[NSMenuItem alloc] initWithTitle:JKLocalizedString(@"Move to Trash", nil) action:@selector(moveTrashItemClick:) keyEquivalent:@""];
            [moveTrashItem setTarget:self];
            [moveTrashItem setTag:1000];
            [menu addItem:moveTrashItem];
        }
        NSMenuItem *deleteItem = [menu itemWithTag:1001];
        if (!deleteItem) {
            deleteItem = [[NSMenuItem alloc] initWithTitle:JKLocalizedString(@"Delete", nil) action:@selector(deleteItemClick:) keyEquivalent:@""];
            [deleteItem setTarget:self];
            [deleteItem setTag:1001];
            [menu addItem:deleteItem];
        }
        NSMenuItem *exportItem = [menu itemWithTag:1003];
        if (!exportItem) {
            exportItem = [[NSMenuItem alloc] initWithTitle:JKLocalizedString(@"Export", nil) action:@selector(exportItemClick:) keyEquivalent:@""];
            [exportItem setTarget:self];
            [exportItem setTag:1003];
            [menu addItem:exportItem];
        }
        NSMenuItem *renameItem = [menu itemWithTag:1004];
        if (!renameItem) {
            renameItem = [[NSMenuItem alloc] initWithTitle:JKLocalizedString(@"Beautify Filename", nil) action:@selector(renameItemClick:) keyEquivalent:@""];
            [renameItem setTarget:self];
            [renameItem setTag:1004];
            [menu addItem:renameItem];
        }
    }
    if (menu == _mainMenu) {
        NSMenuItem *refreshItem = [menu itemWithTag:2000];
        if (!refreshItem) {
            refreshItem = [[NSMenuItem alloc] initWithTitle:JKLocalizedString(@"Refresh Table", nil) action:@selector(refreshItemClick:) keyEquivalent:@""];
            [refreshItem setTarget:self];
            [refreshItem setTag:2000];
            [menu addItem:refreshItem];
        }
        NSMenuItem *importItem = [menu itemWithTag:2001];
        if (!importItem) {
            importItem = [[NSMenuItem alloc] initWithTitle:JKLocalizedString(@"Import Profile", nil) action:@selector(importItemClick:) keyEquivalent:@""];
            [importItem setTarget:self];
            [importItem setTag:2001];
            [menu addItem:importItem];
        }
    }
    if (menu  == _certificateMenu) {
        NSMenuItem *exportItem = [menu itemWithTag:3001];
        if (!exportItem) {
            exportItem = [[NSMenuItem alloc] initWithTitle:JKLocalizedString(@"Export Certificate File", nil) action:@selector(exportCerItemClick:) keyEquivalent:@""];
            [exportItem setTarget:self];
            [exportItem setTag:3001];
            [menu addItem:exportItem];
        }
      
        
        NSMenuItem *copySha1Item = [menu itemWithTag:3003];
        if (!copySha1Item) {
            copySha1Item = [[NSMenuItem alloc] initWithTitle:JKLocalizedString(@"Copy Certificate SHA1", nil) action:@selector(copyCertificateSha1ItemClick:) keyEquivalent:@""];
            [copySha1Item setTarget:self];
            [copySha1Item setTag:3003];
            [menu addItem:copySha1Item];
        }
        NSMenuItem *copySha256Item = [menu itemWithTag:3004];
        if (!copySha256Item) {
            copySha256Item = [[NSMenuItem alloc] initWithTitle:JKLocalizedString(@"Copy Certificate SHA256", nil) action:@selector(copyCertificateSha256ItemClick:) keyEquivalent:@""];
            [copySha256Item setTarget:self];
            [copySha256Item setTag:3004];
            [menu addItem:copySha256Item];
        }
    }
}

#pragma mark -
#pragma mark Operation
- (void)updateStatus {
    if ([self selectedRowIndexes].count > 0) {
        self.statusLabel.stringValue = [NSString stringWithFormat:@"%@ of %@ items selected", [@([self selectedRowIndexes].count) stringValue], [@([_rootNode.childrenNodes count]) stringValue]];
    } else {
        self.statusLabel.stringValue = [NSString stringWithFormat:@"%@ items", [@([_rootNode.childrenNodes count]) stringValue]];
    }
}

- (NSIndexSet *)selectedRowIndexes {
    NSIndexSet *selectedRowIndexes = [self.treeView selectedRowIndexes];
    //多选
    if (selectedRowIndexes.count == 0) {
        //直接右键
        NSInteger index = [self.treeView clickedRow];
        if (index > -1) {
            selectedRowIndexes = [NSIndexSet indexSetWithIndex:index];
        }
    }
    return selectedRowIndexes;
}

- (NSArray *)activateFileURLs {
    NSArray *selectedItems = [_rootNode.childrenNodes objectsAtIndexes:[self selectedRowIndexes]];
    NSMutableArray *activateFileURLs = [NSMutableArray array];
    for (ProfilesNode *node in selectedItems) {
        if ([node.filePath length] > 0) {
            [activateFileURLs addObject:[NSURL fileURLWithPath:node.filePath]];
        }
    }
    return activateFileURLs;
}

- (void)deleteItemClick:(id)sender
{
    NSIndexSet *selectedRowIndexes = [self selectedRowIndexes];
    NSArray *selectedItems = [_rootNode.childrenNodes objectsAtIndexes:selectedRowIndexes];
    
    NSMutableArray *selectedItemNames = [NSMutableArray array];
    for (ProfilesNode *node in selectedItems) {
        [selectedItemNames addObject:node.type ? : node.filePath];
    }
    
    iAlert *alert = [iAlert alertWithTitle:JKLocalizedString(@"Are you sure delete selected items from disk? After delete operation can't rollback!", nil) message:[selectedItemNames componentsJoinedByString:@",\n"] style:NSAlertStyleWarning];
    [alert addCommonButtonWithTitle:JKLocalizedString(@"Ok", nil) handler:^(iAlertItem *item) {
        [self.treeView beginUpdates];
        [self.treeView removeItemsAtIndexes:selectedRowIndexes inParent:nil withAnimation:NSTableViewAnimationEffectFade];
        [self.treeView endUpdates];
        
        for (ProfilesNode *node in selectedItems) {
            if ([self deleteProfile:node.filePath option:YES]) {
                NSMutableArray *temp = [_rootNode.childrenNodes mutableCopy];
                [temp removeObject:node];
                _rootNode.childrenNodes = temp;
            }
        }
        [self updateStatus];
    }];
    [alert addButtonWithTitle:JKLocalizedString(@"Cancle", nil)];
    [alert show:self.view.window];
}

- (void)moveTrashItemClick:(id)sender {
    NSIndexSet *selectedRowIndexes = [self selectedRowIndexes];
    NSArray *selectedItems = [_rootNode.childrenNodes objectsAtIndexes:selectedRowIndexes];
    
    NSMutableArray *selectedItemNames = [NSMutableArray array];
    for (ProfilesNode *node in selectedItems) {
        [selectedItemNames addObject:node.type ? : node.filePath];
    }
    
    iAlert *alert = [iAlert alertWithTitle:JKLocalizedString(@"Are you sure move selected items to trash?", nil) message:[selectedItemNames componentsJoinedByString:@",\n"] style:NSAlertStyleWarning];
    
    [alert addCommonButtonWithTitle:JKLocalizedString(@"Ok", nil) handler:^(iAlertItem *item) {
        [self.treeView beginUpdates];
        [self.treeView removeItemsAtIndexes:selectedRowIndexes inParent:nil withAnimation:NSTableViewAnimationEffectFade];
        [self.treeView endUpdates];
        
        for (ProfilesNode *node in selectedItems) {
            if ([self deleteProfile:node.filePath option:NO]) {
                NSMutableArray *temp = [_rootNode.childrenNodes mutableCopy];
                [temp removeObject:node];
                _rootNode.childrenNodes = temp;
            }
        }
        [self updateStatus];
        
        //        [self loadProfileFilesWithSearchWord:_searchWord];
    }];
    
    [alert addButtonWithTitle:JKLocalizedString(@"Cancle", nil)];
    [alert show:self.view.window];
}

//copyProfilePath
- (void)copyProfilePath:(id)sender
{
    NSArray *selectedItems = [_rootNode.childrenNodes objectsAtIndexes:[self selectedRowIndexes]];
    if (selectedItems.count > 0) {
        ProfilesNode *node = selectedItems.firstObject;
        NSPasteboard *paste = [NSPasteboard generalPasteboard];
        [paste clearContents];
        [paste setString:node.filePath forType:NSPasteboardTypeString];
    }
}

//showInFinder
- (void)showInFinder:(id)sender
{
    NSArray *activateFileURLs = [self activateFileURLs];
    [[NSWorkspace sharedWorkspace] activateFileViewerSelectingURLs:activateFileURLs];
}

//beautify filename
- (void)renameItemClick:(id)sender {
    NSInteger index = [self.treeView clickedRow];
    if (index == -1) return;
    ProfilesNode *node = [self.treeView itemAtRow:index];
    
    if ([node.filePath.lastPathComponent hasPrefix:node.type]) {
        [iAlert showMessage:JKLocalizedString(@"The filename no need beautify", nil) window:self.view.window completionHandler:^(NSModalResponse returnCode) {
        }];
        return;
    }
    
    NSString *msg = JKLocalizedString(@"The profile installed by double click fileaname format is 'uuid+ext',it‘s very hard identify.\nare you sure rename profile filename? this will take 5 seconds！\nthe new filename is: ", nil);
    
    iAlert *alert = [iAlert alertWithTitle:JKLocalizedString(@"Warning", nil) message:[NSString stringWithFormat:@"%@%@", msg, node.type] style:NSAlertStyleWarning];
    [alert addCommonButtonWithTitle:JKLocalizedString(@"Ok", nil) handler:^(iAlertItem *item) {
        [self renameFileAtPath:node.filePath toName:node.type basePath:node.baseDir completion:^(NSString *newPath) {
            if (newPath && newPath.length > 0) {
                node.filePath = newPath;
                node.key = [newPath lastPathComponent];
                [self.treeView beginUpdates];
                [self.treeView reloadItem:node];
                [self.treeView endUpdates];
            }
        }];
    }];
    
    [alert addButtonWithTitle:JKLocalizedString(@"Cancle", nil)];
    [alert show:self.view.window];
}

//export Item to file
- (void)exportItemClick:(id)sender {
    NSInteger index = [self.treeView clickedRow];
    if (index == -1) return;
    ProfilesNode *node = [self.treeView itemAtRow:index];
    
    NSSavePanel *savePanel = [NSSavePanel savePanel];
    NSString *ext = [node.filePath.pathExtension lowercaseString].length > 0 ? [node.filePath.pathExtension lowercaseString] : @"mobileprovision";
    UTType *type = [UTType typeWithFilenameExtension:ext];
    if (type) {
        savePanel.allowedContentTypes = @[type];
    }
    savePanel.nameFieldStringValue = node.type ? : node.key;
    savePanel.extensionHidden = NO;
    
    [savePanel beginSheetModalForWindow:self.view.window completionHandler:^(NSInteger result) {
        NSString *savePath = savePanel.URL.path;
        if (result == NSModalResponseOK) {
            if ([[NSFileManager defaultManager] fileExistsAtPath:savePath]) {
                [[NSFileManager defaultManager] removeItemAtPath:savePath error:nil];
            }
            [[NSFileManager defaultManager] copyItemAtPath:node.filePath toPath:savePath error:nil];
        }
    }];
}

//main
- (void)refreshItemClick:(id)sender {
    [self reloadProfiles];
}

//import
- (void)importItemClick:(id)sender {
    NSOpenPanel *oPanel = [NSOpenPanel openPanel];
    [oPanel setCanChooseDirectories:NO];
    [oPanel setAllowsMultipleSelection:YES];
    [oPanel setDirectoryURL:[NSURL fileURLWithPath:NSHomeDirectory()]];
    NSMutableArray<UTType *> *types = [NSMutableArray array];
    for (NSString *ext in @[@"mobileprovision", @"provisionprofile"]) {
        UTType *type = [UTType typeWithFilenameExtension:ext];
        if (type) {
            [types addObject:type];
        }
    }
    oPanel.allowedContentTypes = types;
    
    if ([oPanel runModal] == NSModalResponseOK) {
        for (NSURL *url in [oPanel URLs]) {
            [self installProfileAtPath:url.path];
        }
    }
    [self loadProfileFilesWithSearchWord:_searchWord];
}

- (void)exportCerItemClick:(id)sender
{
    NSInteger index = [self.treeView clickedRow];
    if (index == -1) return;
    ProfilesNode *node = [self.treeView itemAtRow:index];
    if ([node.detail length] > 0) {
        NSOpenPanel *oPanel = [NSOpenPanel openPanel];
        [oPanel setCanChooseDirectories:YES];
        [oPanel setCanChooseFiles:NO];
        [oPanel setDirectoryURL:[NSURL fileURLWithPath:NSHomeDirectory()]];
        if ([oPanel runModal] == NSModalResponseOK) {
            NSString *path = [[[oPanel URLs] objectAtIndex:0] path];
            NSString *savePath = [[path stringByAppendingPathComponent:[node.extra objectForKey:@"summary"] ]stringByAppendingPathExtension:@"cer"];
            
            NSString *formaterCer = [NSString stringWithFormat:@"-----BEGIN CERTIFICATE-----\n%@\n-----END CERTIFICATE-----", node.detail];
            
            BOOL haveCreate =  [[NSFileManager defaultManager]createFileAtPath:savePath contents:[formaterCer dataUsingEncoding:NSUTF8StringEncoding] attributes:nil];
            if (haveCreate) {
                [[NSWorkspace sharedWorkspace] selectFile:savePath inFileViewerRootedAtPath:@""];
            }
        }
    }
}

- (void)copyCertificateSha1ItemClick:(id)sender{
       NSInteger index = [self.treeView clickedRow];
    if (index == -1) return;
    ProfilesNode *node = [self.treeView itemAtRow:index];
    NSPasteboard *paste = [NSPasteboard generalPasteboard];
    [paste clearContents];
    [paste setString:[node.extra objectForKey:@"sha1"]?:@"" forType:NSPasteboardTypeString];
}

- (void)copyCertificateSha256ItemClick:(id)sender{
    NSInteger index = [self.treeView clickedRow];
    if (index == -1) return;
    ProfilesNode *node = [self.treeView itemAtRow:index];
    NSPasteboard *paste = [NSPasteboard generalPasteboard];
    [paste clearContents];
    [paste setString:[node.extra objectForKey:@"sha256"]?:@"" forType:NSPasteboardTypeString];
}
#pragma mark --filemanager

//delete and move
- (BOOL)deleteProfile:(NSString *)filePath option:(BOOL)completely {
    NSError *error;
    BOOL result = NO;
    if (completely) {
        result =  [[NSFileManager defaultManager] removeItemAtPath:filePath error:&error];
    } else {
        result = [[NSFileManager defaultManager] mr_moveFileAtPathToTrash:filePath error:&error];
    }
    if (error) {
        [iAlert showMessage:[error localizedDescription] window:self.view.window completionHandler:^(NSModalResponse returnCode) {
        }];
    }
    return result;
}

- (void)renameFileAtPath:(NSString *)oldPath toName:(NSString *)toName basePath:(NSString *)basePath completion:(void (^)(NSString *newPath))completion {
    NSString *ext = oldPath.pathExtension;
    
    NSString *time = [[DateManager sharedManager] stringConvert_Y_M_D_H_M_FromDate:[NSDate date]];
    
    NSString *toPath = [[[_backupDir stringByAppendingPathComponent:toName] stringByAppendingString:time] stringByAppendingPathExtension:ext];
    
    NSString *newPath = [[basePath stringByAppendingPathComponent:toName] stringByAppendingPathExtension:ext];
    
    //在后台等待，避免卡住界面
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        NSError *error = nil;
        BOOL result = [[NSFileManager defaultManager] moveItemAtPath:oldPath toPath:toPath error:&error];
        if (result) {
            //Provisioning Profiles文件比较特殊 直接改名会被系统自动删掉
            sleep(5);
            result = [[NSFileManager defaultManager] copyItemAtURL:[NSURL fileURLWithPath:toPath] toURL:[NSURL fileURLWithPath:newPath] error:&error];
        }
        dispatch_async(dispatch_get_main_queue(), ^{
            if (error) {
                [iAlert showAlert:NSAlertStyleWarning title:@"" message:[error localizedDescription]];
                NSLog(@"重命名失败：%@", [error localizedDescription]);
            }
            completion(result ? newPath : nil);
        });
    });
}

@end
