//
//  ClassicalViewController.h
//  PPMacho
//
//  Created by C.W. Betts on 7/26/14.
//
//

#import <Cocoa/Cocoa.h>

@class PPDocument;
@class PPPatternGridView;

@interface ClassicalViewController : NSViewController

@property (weak) IBOutlet PPDocument *currentDocument;
@property (nonatomic, strong, readonly) PPPatternGridView *gridView;

@end
