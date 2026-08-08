//
//  DigitalViewController.h
//  PPMacho
//
//  Created by C.W. Betts on 7/26/14.
//
//

#import <Cocoa/Cocoa.h>

@class PPDocument;
@class PPClassicGridView;

// Hosts the "Classic" tab's piano-roll (ClassicGridView.swift) despite the
// class name -- see the hosting note at the top of ClassicGridView.swift.
@interface DigitalViewController : NSViewController

@property (weak) IBOutlet PPDocument *currentDocument;
@property (nonatomic, strong, readonly) PPClassicGridView *gridView;

@end
