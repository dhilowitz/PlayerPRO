//
//  PPAmplitudePlug.m
//  PPMacho
//
//  Created by C.W. Betts on 9/11/14.
//
//

#import "PPAmplitudePlug.h"
#import "AmplitudeController.h"
#import <PlayerPROKit/PPErrors.h>

@implementation PPAmplitudePlug

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
	AmplitudeController *controller = [[AmplitudeController alloc] initWithWindowNibName:@"AmplitudeController"];
	controller.theData = theData;
	controller.selectionRange = selRange;
	controller.stereoMode = StereoMode;
	controller.currentBlock = handle;
	controller.amplitudeAmount = 120;
	controller.parentWindow = document;

	[document beginSheet:controller.window completionHandler:^(NSModalResponse returnCode) {
		// See PPFadePlug.m's identical fix -- an empty block here captured
		// nothing, so controller (target of the sheet's OK/Cancel) was
		// deallocated the instant this method returned, leaving the sheet
		// permanently undismissable.
		(void)controller;
	}];
}

@end
