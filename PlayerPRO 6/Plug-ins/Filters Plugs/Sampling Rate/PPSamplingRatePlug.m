//
//  PPSamplingRatePlug.m
//  PPMacho
//
//  Created by C.W. Betts on 9/7/14.
//
//

#import "PPSamplingRatePlug.h"
#import "SamplingRateWindowController.h"

@implementation PPSamplingRatePlug

- (BOOL)hasUIConfiguration
{
	return YES;
}

- (instancetype)initForPlugIn
{
	return self = [self init];
}

- (BOOL)runWithData:(inout PPSampleObject*)theData selectionRange:(NSRange)selRange onlyCurrentChannel:(BOOL)StereoMode driver:(PPDriver*)driver error:(NSError * _Nullable __autoreleasing * _Nonnull)error
{
	if (error) {
		*error = [NSError errorWithDomain:PPMADErrorDomain code:MADOrderNotImplemented userInfo:nil];
	}
	
	return NO;
}

- (void)beginRunWithData:(PPSampleObject*)theData selectionRange:(NSRange)selRange onlyCurrentChannel:(BOOL)StereoMode driver:(PPDriver*)driver parentWindow:(NSWindow*)document handler:(PPPlugErrorBlock)handle;
{
	SamplingRateWindowController *controller = [[SamplingRateWindowController alloc] initWithWindowNibName:@"SamplingRateWindowController"];
	controller.currentRate = controller.changedRate = theData.c2spd;
	controller.theData = theData;
	controller.currentBlock = handle;
	controller.selectionRange = selRange;
	controller.stereoMode = StereoMode;
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
