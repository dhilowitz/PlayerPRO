//
//  PPNoteTranslatePlug.m
//  PPMacho
//
//  Created by C.W. Betts on 9/7/14.
//
//

#import "PPNoteTranslatePlug.h"
#import "NoteTranslateController.h"

@implementation PPNoteTranslatePlug

- (BOOL)hasUIConfiguration
{
	return YES;
}

- (instancetype)initForPlugIn
{
	return self = [self init];
}

- (BOOL)runWithPcmd:(inout Pcmd *)aPcmd driver:(PPDriver *)driver error:(NSError * _Nullable __autoreleasing * _Nonnull)error
{
	if (error) {
		*error = [NSError errorWithDomain:PPMADErrorDomain code:MADOrderNotImplemented userInfo:nil];
	}
	
	return NO;
}

- (void)beginRunWithPcmd:(Pcmd *)aPcmd driver:(PPDriver *)driver parentWindow:(NSWindow *)document handler:(PPPlugErrorBlock)handle
{
	NoteTranslateController *controller = [[NoteTranslateController alloc] initWithWindowNibName:@"NoteTranslateController"];
	controller.thePcmd = aPcmd;
	controller.transAmount = 0;
	controller.currentBlock = handle;
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
