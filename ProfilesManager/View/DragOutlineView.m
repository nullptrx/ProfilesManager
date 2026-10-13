//
//  DragOutlineView.m
//  ProfilesManager
//
//  Created by Jakey on 15/5/6.
//  Copyright (c) 2015年 Jakey. All rights reserved.
//

#import "DragOutlineView.h"

@implementation DragOutlineView
- (id)initWithFrame:(NSRect)frame
{
    self = [super initWithFrame:frame];
    if (self) {
        [self registerForDraggedTypes:@[NSPasteboardTypeFileURL]];

    }
    
    return self;
}
- (void)awakeFromNib {
    [self registerForDraggedTypes:@[NSPasteboardTypeFileURL]];
}

-(NSDragOperation)draggingEntered:(id<NSDraggingInfo>)sender{
    NSPasteboard *pboard = [sender draggingPasteboard];
    
    if ([[pboard types] containsObject:NSPasteboardTypeFileURL]) {
        return NSDragOperationCopy;
    }
    if(_didEnterDraging){
        _didEnterDraging();
    }
    return NSDragOperationNone;
}

- (void)draggingEnded:(id <NSDraggingInfo>)sender{
    NSPasteboard *zPasteboard = [sender draggingPasteboard];
    NSArray<NSURL *> *urls = [zPasteboard readObjectsForClasses:@[[NSURL class]] options:@{NSPasteboardURLReadingFileURLsOnlyKey: @YES}];
    if (urls.count == 0) {
        return;
    }
    NSArray *list = [urls valueForKey:@"path"];
    if(_didDragEnd){
        _didDragEnd(list,self);
    }

}
-(void)didDragEndBlock:(DidDragEnd)didDragEnd{
    _didDragEnd = [didDragEnd copy];
}
-(void)didEnterDragingBlock:(DidEnterDraging)didEnterDraging{
    _didEnterDraging  = [didEnterDraging copy];
}

@end
