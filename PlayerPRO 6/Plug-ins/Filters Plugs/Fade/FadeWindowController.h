//
//  FadeWindowController.h
//  PPMacho
//
//  Created by C.W. Betts on 9/10/13.
//
//

#import <Cocoa/Cocoa.h>
#import <PlayerPROKit/PlayerPROKit.h>

@interface FadeWindowController : NSWindowController <NSControlTextEditingDelegate>
@property double fadeFrom;
@property double fadeTo;
@property NSRange selectionRange;
@property BOOL stereoMode;
@property (copy) PPPlugErrorBlock currentBlock;
@property (strong) PPSampleObject *theData;

@property (strong) NSWindow *parentWindow;

@property (weak) IBOutlet NSForm *fadeForm;

- (IBAction)okay:(id)sender;
- (IBAction)cancel:(id)sender;
@end
