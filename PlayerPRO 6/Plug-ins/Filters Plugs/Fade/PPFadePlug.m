//
//  PPFadePlug.m
//  PPMacho
//
//  Created by C.W. Betts on 9/11/14.
//
//

#import "PPFadePlug.h"
#import "FadeWindowController.h"

@implementation PPFadePlug

- (BOOL)hasUIConfiguration
{
	return YES;
}

- (instancetype)initForPlugIn
{
	return self = [self init];
}

- (BOOL)runWithData:(inout PPSampleObject *)theData selectionRange:(NSRange)selRange onlyCurrentChannel:(BOOL)StereoMode driver:(PPDriver *)driver error:(NSError * _Nullable __autoreleasing * _Nonnull)error
{
	if (error) {
		*error = [NSError errorWithDomain:PPMADErrorDomain code:MADOrderNotImplemented userInfo:nil];
	}
	
	return NO;
}

- (void)beginRunWithData:(PPSampleObject *)theData selectionRange:(NSRange)selRange onlyCurrentChannel:(BOOL)StereoMode driver:(PPDriver *)driver parentWindow:(NSWindow*)document handler:(PPPlugErrorBlock)handle
{
	FadeWindowController *controller = [[FadeWindowController alloc] initWithWindowNibName:@"FadeWindowController"];
	controller.theData = theData;
	controller.selectionRange = selRange;
	controller.currentBlock = handle;
	controller.fadeTo = 1.0;
	controller.fadeFrom = .70;
	controller.stereoMode = StereoMode;
	controller.parentWindow = document;
	
	[document beginSheet:controller.window completionHandler:^(NSModalResponse returnCode) {
		// Keeps controller alive for the sheet's lifetime -- an ARC block
		// only retains what it actually references, and this handler used
		// to be empty, so controller (the target of the sheet's own OK/
		// Cancel actions) was deallocated the instant this method
		// returned. With a dead target, nothing could ever dismiss the
		// sheet: not OK, not Cancel, not even Quit (app termination has to
		// end every open sheet first).
		(void)controller;
	}];
}

@end
